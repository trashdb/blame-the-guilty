using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Contracts;
using Statefalse.Api.Data;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// workflow_run webhook handler: tracks in_progress/completed runs, supersedes
/// stale siblings, persists punishment events for failures and fans out SignalR.
/// </summary>
public class WorkflowRunWebhookHandler : IWebhookHandler
{
    private readonly AppDbContext _db;
    private readonly GitHubTokenResolver _tokens;
    private readonly SignalRNotifier _notifier;
    private readonly ILogger<WorkflowRunWebhookHandler> _logger;

    public WorkflowRunWebhookHandler(
        AppDbContext db,
        GitHubTokenResolver tokens,
        SignalRNotifier notifier,
        ILogger<WorkflowRunWebhookHandler> logger)
    {
        _db = db;
        _tokens = tokens;
        _notifier = notifier;
        _logger = logger;
    }

    public string EventType => "workflow_run";

    public async Task<ApiResult> HandleAsync(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var repo = TryGetRepo(payload);
        var name = TryGetWorkflowName(payload);

        if (action is "in_progress" or "requested") return await HandleInProgress(payload);
        if (action == "completed") return await HandleCompleted(payload);

        WebhookLog.Log("workflow_run", action, repo, name, "ignored", $"Unsupported action '{action}'");
        return ApiResult.Ok($"Ignored: workflow_run action '{action}'.");
    }

    private async Task<ApiResult> HandleInProgress(JsonElement payload)
    {
        var run = payload.GetProperty("workflow_run");
        var culprit = ResolveCulprit(payload);
        if (culprit == null)
        {
            WebhookLog.Log("workflow_run", "in_progress", TryGetRepo(payload), TryGetWorkflowName(payload), "ignored", "Could not resolve actor");
            return ApiResult.Ok("Could not resolve actor.");
        }

        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var name = run.TryGetProperty("name", out var wn) ? wn.GetString() : "Workflow";
        var isIgnored = IgnoredWorkflows.IsIgnored(name);
        var branch = run.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var headSha = run.TryGetProperty("head_sha", out var hs) ? hs.GetString() : null;
        var url = run.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
        var runId = run.GetProperty("id").GetInt64();
        var startedAt = run.TryGetProperty("run_started_at", out var rsa) ? rsa.GetDateTime() : DateTime.UtcNow;
        var trigger = run.TryGetProperty("event", out var ev) ? ev.GetString() : null;

        var existingInProgress = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && w.Status == "in_progress")
            .FirstOrDefaultAsync();
        if (existingInProgress != null)
        {
            // Already tracking this run — likely a duplicate webhook event
            await _db.SaveChangesAsync();
            return ApiResult.Ok(new { runId });
        }

        var gitHubId = culprit.Id ?? (await _tokens.FindByLoginAsync(culprit.Login))?.GitHubId;
        var newRun = new WorkflowRun
        {
            RunId = runId,
            GitHubId = gitHubId ?? 0,
            WorkflowName = name,
            Repo = repo,
            Actor = culprit.Login,
            HeadBranch = branch,
            HeadSha = headSha,
            Trigger = trigger,
            HtmlUrl = url,
            Status = "in_progress",
            StartedAt = startedAt,
            IsIgnored = isIgnored
        };
        _db.WorkflowRuns.Add(newRun);
        await _db.SaveChangesAsync();

        // Mark previous in_progress runs for same repo+workflow+branch as superseded
        // (GitHub does not send completed webhooks for superseded runs)
        if (branch != null)
        {
            var superseded = await _db.WorkflowRuns
                .Where(w => w.Id != newRun.Id && w.Repo == repo && w.WorkflowName == name
                    && w.HeadBranch == branch && w.Status == "in_progress")
                .ToListAsync();
            if (superseded.Count > 0)
            {
                foreach (var s in superseded)
                    s.Status = "superseded";
                await _db.SaveChangesAsync();
                _logger.LogInformation("Superseded {Count} previous run(s) for {Repo} {Name} on {Branch}", superseded.Count, repo, name, branch);
            }
        }

        // Notify via SignalR only for non-ignored workflows
        if (!isIgnored)
        {
            var user = await _tokens.FindConnectedUserAsync(culprit.Login, culprit.Id);
            if (user != null)
            {
                await _notifier.NotifyUserAsync(user.GitHubId, "WorkflowRunStarted", new WorkflowRunStartedPayload(
                    Id: newRun.Id,
                    RunId: runId,
                    WorkflowName: name,
                    Repo: repo,
                    Branch: branch,
                    Trigger: trigger,
                    Actor: culprit.Login,
                    HtmlUrl: url));
                _logger.LogInformation("Running workflow {RunId} notified to {Login}", runId, culprit.Login);
            }
        }

        // Always notify PR update so ciStatus refreshes even for ignored workflows
        await _notifier.NotifyPullRequestsUpdatedAsync();

        var actor = culprit?.Login ?? "unknown";
        WebhookLog.Log("workflow_run", "in_progress", repo, name, isIgnored ? "ignored" : "processed", $"actor={actor}, runId={runId}");
        return ApiResult.Ok(new { runId });
    }

    private async Task<ApiResult> HandleCompleted(JsonElement payload)
    {
        var workflowRun = payload.GetProperty("workflow_run");
        var conclusion = workflowRun.GetProperty("conclusion").GetString();

        var culprit = ResolveCulprit(payload);
        if (culprit == null)
        {
            _logger.LogWarning("Could not determine culprit for failed workflow run.");
            return ApiResult.Ok("Could not resolve culprit.");
        }

        var repoFullName = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var runId = workflowRun.GetProperty("id").GetInt64();
        var workflowName = workflowRun.TryGetProperty("name", out var wn) ? wn.GetString() : null;
        var isIgnored = IgnoredWorkflows.IsIgnored(workflowName);
        var workflowUrl = workflowRun.TryGetProperty("html_url", out var wu) ? wu.GetString() : null;
        var trigger = workflowRun.TryGetProperty("event", out var ev) ? ev.GetString() : null;

        var dbStatus = WorkflowConclusionMapper.ToDbStatus(conclusion);

        // Update the latest in_progress row for this runId
        var dbRun = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && w.Status == "in_progress")
            .OrderByDescending(w => w.Id)
            .FirstOrDefaultAsync();

        if (dbRun != null)
        {
            if (dbStatus != null)
                dbRun.Status = dbStatus;
            dbRun.IsIgnored = isIgnored;
        }
        else if (dbStatus != null)
        {
            var gitHubId = culprit.Id ?? (await _tokens.FindByLoginAsync(culprit.Login))?.GitHubId;
            _db.WorkflowRuns.Add(new WorkflowRun
            {
                RunId = runId,
                GitHubId = gitHubId ?? 0,
                WorkflowName = workflowName,
                Repo = repoFullName,
                Actor = culprit.Login,
                HeadBranch = workflowRun.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null,
                HeadSha = workflowRun.TryGetProperty("head_sha", out var hs) ? hs.GetString() : null,
                Trigger = trigger,
                HtmlUrl = workflowUrl,
                Status = dbStatus,
                StartedAt = DateTime.UtcNow,
                IsIgnored = isIgnored
            });
        }

        await _db.SaveChangesAsync();

        // Always notify PR update so ciStatus refreshes for ignored workflows too
        await _notifier.NotifyPullRequestsUpdatedAsync();

        // Skip SignalR completion notifications for ignored workflows
        if (isIgnored) return ApiResult.Ok(new { runId });

        // Notify both the culprit and the target user (if set) via SignalR
        async Task NotifyCompleted(long gitHubId, bool succeeded)
        {
            await _notifier.NotifyUserAsync(gitHubId, "WorkflowRunCompleted", new WorkflowRunCompletedPayload(
                RunId: runId,
                Succeeded: succeeded,
                Conclusion: conclusion,
                WorkflowName: workflowName,
                Repo: repoFullName,
                Actor: culprit.Login,
                HtmlUrl: workflowUrl,
                Trigger: trigger));
        }

        if (conclusion == "success")
        {
            var user = await _tokens.FindConnectedUserAsync(culprit.Login, culprit.Id);
            if (user != null)
            {
                await NotifyCompleted(user.GitHubId, true);
                _logger.LogInformation("Workflow success notified to {Login}", culprit.Login);
            }

            var targetIds = IdListSerializer.Deserialize(dbRun?.TargetGitHubIds);
            foreach (var tid in targetIds)
            {
                if (tid != user?.GitHubId)
                {
                    await NotifyCompleted(tid, true);
                    _logger.LogInformation("Workflow success also notified to target {TargetId}", tid);
                }
            }

            WebhookLog.Log("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, notified");
            return ApiResult.Ok(new { runId, conclusion });
        }

        if (WorkflowConclusionMapper.IsNonFailure(conclusion))
        {
            WebhookLog.Log("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, no notification (non-failure)");
            return ApiResult.Ok(new { runId, conclusion });
        }

        // Save punishment event (always for failures)
        var historyEvent = new PunishmentEvent
        {
            RunId = runId, CulpritLogin = culprit.Login, CulpritGitHubId = culprit.Id,
            RepoFullName = repoFullName, WorkflowName = workflowName, WorkflowUrl = workflowUrl,
            OccurredAt = DateTime.UtcNow
        };

        var user2 = await _tokens.FindConnectedUserAsync(culprit.Login, culprit.Id);
        historyEvent.WasNotified = user2 != null;
        _db.PunishmentEvents.Add(historyEvent);
        await _db.SaveChangesAsync();

        // Notify via SignalR if connected
        if (user2 != null)
        {
            await NotifyCompleted(user2.GitHubId, false);
            _logger.LogInformation("Punishment sent to {Login}", culprit.Login);
        }

        var failTargetIds = IdListSerializer.Deserialize(dbRun?.TargetGitHubIds);
        foreach (var tid in failTargetIds)
        {
            if (tid != user2?.GitHubId)
            {
                await NotifyCompleted(tid, false);
                _logger.LogInformation("Punishment also notified to target {TargetId}", tid);
            }
        }

        WebhookLog.Log("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, failure handled");
        return ApiResult.Ok(new { runId, conclusion });
    }

    private CulpritInfo? ResolveCulprit(JsonElement payload)
    {
        try
        {
            var run = payload.GetProperty("workflow_run");

            if (run.TryGetProperty("pull_requests", out var prs) && prs.GetArrayLength() > 0)
            {
                var pr = prs[0];

                if (pr.TryGetProperty("merged_by", out var mergedBy))
                {
                    var id = mergedBy.TryGetProperty("id", out var mid) ? mid.GetInt64() : (long?)null;
                    var login = mergedBy.GetProperty("login").GetString()!;
                    return new CulpritInfo(login, id);
                }

                if (pr.TryGetProperty("user", out var prUser))
                {
                    var id = prUser.TryGetProperty("id", out var pid) ? pid.GetInt64() : (long?)null;
                    var login = prUser.GetProperty("login").GetString()!;
                    return new CulpritInfo(login, id);
                }
            }

            if (payload.TryGetProperty("sender", out var sender))
            {
                var id = sender.TryGetProperty("id", out var sid) ? sid.GetInt64() : (long?)null;
                var login = sender.GetProperty("login").GetString()!;
                return new CulpritInfo(login, id);
            }

            if (run.TryGetProperty("head_commit", out var commit) &&
                commit.ValueKind != JsonValueKind.Null &&
                commit.TryGetProperty("author", out var author))
            {
                var username = author.TryGetProperty("username", out var uname)
                    ? uname.GetString()
                    : author.GetProperty("name").GetString();

                if (!string.IsNullOrEmpty(username))
                    return new CulpritInfo(username, null);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resolving culprit from webhook payload.");
        }

        return null;
    }

    private static string? TryGetRepo(JsonElement payload)
    {
        if (payload.TryGetProperty("repository", out var repo) &&
            repo.TryGetProperty("full_name", out var name))
            return name.GetString();
        return null;
    }

    private static string? TryGetWorkflowName(JsonElement payload)
    {
        if (payload.TryGetProperty("workflow_run", out var run) &&
            run.TryGetProperty("name", out var name))
            return name.GetString();
        return null;
    }
}

internal record CulpritInfo(string Login, long? Id);
