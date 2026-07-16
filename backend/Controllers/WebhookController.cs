using System.Collections.Concurrent;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Hubs;
using BlameTheGuilty.Api.Models;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/webhook")]
public class WebhookController : ControllerBase
{
    private static readonly HashSet<string> IgnoredWorkflows = new(StringComparer.OrdinalIgnoreCase)
    {
        "CodeQL High Severity",
        "Dependency Review",
        "Label PR by Team Member",
        "Verify ForgeRock Secrets"
    };

    private static readonly ConcurrentQueue<WebhookLogEntry> _recentLogs = new();

    private readonly IHubContext<PunishmentHub> _hubContext;
    private readonly AppDbContext _db;
    private readonly ILogger<WebhookController> _logger;

    public WebhookController(
        IHubContext<PunishmentHub> hubContext,
        AppDbContext db,
        ILogger<WebhookController> logger)
    {
        _hubContext = hubContext;
        _db = db;
        _logger = logger;
    }

    [HttpGet("logs")]
    public IActionResult GetLogs([FromQuery] int limit = 30)
    {
        return Ok(_recentLogs.Reverse().Take(limit).ToList());
    }

    private static void LogWebhook(string eventType, string? action, string? repo, string? workflowName, string outcome, string? message = null)
    {
        _recentLogs.Enqueue(new WebhookLogEntry
        {
            EventType = eventType,
            Action = action,
            Repo = repo,
            WorkflowName = workflowName,
            Outcome = outcome,
            Message = message,
            OccurredAt = DateTime.UtcNow
        });
        while (_recentLogs.Count > 100)
            _recentLogs.TryDequeue(out _);
    }

    [HttpPost("github")]
    public async Task<IActionResult> HandleGitHubWebhook([FromBody] JsonElement payload)
    {
        var eventType = Request.Headers["X-GitHub-Event"].FirstOrDefault() ?? "";

        if (eventType == "workflow_run") return await HandleWorkflowRun(payload);
        if (eventType == "check_suite") return await HandleCheckSuite(payload);
        if (eventType == "pull_request") return await HandlePullRequest(payload);
        if (eventType == "pull_request_review") return await HandlePullRequestReview(payload);
        if (eventType == "issue_comment") return await HandleIssueComment(payload);
        LogWebhook(eventType, null, TryGetRepo(payload), null, "ignored", "Unsupported event type");
        return Ok($"Ignored: unsupported event '{eventType}'.");
    }

    // ─── workflow_run: dispatch by action ──────────────────────────────────

    private async Task<IActionResult> HandleWorkflowRun(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var repo = TryGetRepo(payload);
        var name = TryGetWorkflowName(payload);

        if (action == "in_progress" || action == "requested") return await HandleWorkflowRunInProgress(payload);
        if (action == "completed") return await HandleWorkflowRunCompleted(payload);
        LogWebhook("workflow_run", action, repo, name, "ignored", $"Unsupported action '{action}'");
        return Ok($"Ignored: workflow_run action '{action}'.");
    }

    private async Task<IActionResult> HandleWorkflowRunInProgress(JsonElement payload)
    {
        var run = payload.GetProperty("workflow_run");
        var culprit = ResolveWorkflowCulprit(payload);
        if (culprit == null)
        {
            LogWebhook("workflow_run", "in_progress", TryGetRepo(payload), TryGetWorkflowName(payload), "ignored", "Could not resolve actor");
            return Ok("Could not resolve actor.");
        }

        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var name = run.TryGetProperty("name", out var wn) ? wn.GetString() : "Workflow";
        var isIgnored = IgnoredWorkflows.Contains(name);
        var branch = run.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var headSha = run.TryGetProperty("head_sha", out var hs) ? hs.GetString() : null;
        var url = run.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
        var runId = run.GetProperty("id").GetInt64();
        var startedAt = run.TryGetProperty("run_started_at", out var rsa) ? rsa.GetDateTime() : DateTime.UtcNow;
        var trigger = run.TryGetProperty("event", out var ev) ? ev.GetString() : null;

        // Update existing in_progress row, or create new one for reruns
        var existingInProgress = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && w.Status == "in_progress")
            .FirstOrDefaultAsync();
        if (existingInProgress != null)
        {
            // Already tracking this run — likely a duplicate webhook event
            await _db.SaveChangesAsync();
            return Ok(new { runId });
        }

        var existingFinal = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && (w.Status == "success" || w.Status == "failure"))
            .FirstOrDefaultAsync();
        if (existingFinal != null)
        {
            // This is a rerun — create a new entry
        }

        var gitHubId = culprit.Id ?? (await FindUserByLogin(culprit.Login))?.GitHubId;
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

        // Mark previous in_progress runs for same repo+workflow+branch as failure
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
            var user = await FindConnectedUser(culprit.Login, culprit.Id);
            if (user != null)
            {
                await _hubContext.Clients.Group(user.GitHubId.ToString()).SendAsync("WorkflowRunStarted", new
                {
                    id = newRun.Id, runId, workflowName = name, repo, branch, trigger, actor = culprit.Login, htmlUrl = url
                });
                _logger.LogInformation("Running workflow {RunId} notified to {Login}", runId, culprit.Login);
            }
        }

        // Always notify PR update so ciStatus refreshes even for ignored workflows
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");

        var actor = culprit?.Login ?? "unknown";
        LogWebhook("workflow_run", "in_progress", repo, name, isIgnored ? "ignored" : "processed", $"actor={actor}, runId={runId}");
        return Ok(new { runId });
    }

    private async Task<IActionResult> HandleWorkflowRunCompleted(JsonElement payload)
    {
        var workflowRun = payload.GetProperty("workflow_run");
        var conclusion = workflowRun.GetProperty("conclusion").GetString();

        var culprit = ResolveWorkflowCulprit(payload);
        if (culprit == null)
        {
            _logger.LogWarning("Could not determine culprit for failed workflow run.");
            return Ok("Could not resolve culprit.");
        }

        var repoFullName = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var runId = workflowRun.GetProperty("id").GetInt64();
        var workflowName = workflowRun.TryGetProperty("name", out var wn) ? wn.GetString() : null;
        var isIgnored = workflowName != null && IgnoredWorkflows.Contains(workflowName);
        var workflowUrl = workflowRun.TryGetProperty("html_url", out var wu) ? wu.GetString() : null;

        // Update the latest in_progress row for this runId
        var dbRun = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && w.Status == "in_progress")
            .OrderByDescending(w => w.Id)
            .FirstOrDefaultAsync();
        var isTerminal = conclusion is "success" or "failure" or "cancelled" or "timed_out" or "stale" or "action_required" or "skipped" or "neutral" or "startup_failure";
        var dbStatus = isTerminal
            ? conclusion == "success" ? "success"
            : conclusion == "failure" ? "failure"
            : "cancelled"
            : (string?)null;

        if (dbRun != null)
        {
            if (dbStatus != null)
                dbRun.Status = dbStatus;
        }
        else if (isTerminal)
        {
            var gitHubId = culprit.Id ?? (await FindUserByLogin(culprit.Login))?.GitHubId;
            _db.WorkflowRuns.Add(new WorkflowRun
            {
                RunId = runId,
                GitHubId = gitHubId ?? 0,
                WorkflowName = workflowName,
                Repo = repoFullName,
                Actor = culprit.Login,
                HeadBranch = workflowRun.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null,
                HeadSha = workflowRun.TryGetProperty("head_sha", out var hs) ? hs.GetString() : null,
                Trigger = workflowRun.TryGetProperty("event", out var ev) ? ev.GetString() : null,
                HtmlUrl = workflowUrl,
                Status = dbStatus ?? "failure",
                StartedAt = DateTime.UtcNow,
                IsIgnored = isIgnored
            });
        }

        // Mark existing run as ignored if it was matched
        if (dbRun != null)
        {
            dbRun.IsIgnored = isIgnored;
        }

        await _db.SaveChangesAsync();

        // Always notify PR update so ciStatus refreshes for ignored workflows too
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");

        // Skip SignalR completion notifications for ignored workflows
        if (isIgnored) return Ok(new { runId });

        // Notify both the culprit and the target user (if set) via SignalR
        async Task NotifyCompleted(long gitHubId, bool succeeded)
        {
            await _hubContext.Clients.Group(gitHubId.ToString()).SendAsync("WorkflowRunCompleted", new
            {
                runId, succeeded, conclusion,
                workflowName, repo = repoFullName, actor = culprit.Login,
                htmlUrl = workflowUrl, trigger = workflowRun.TryGetProperty("event", out var ev2) ? ev2.GetString() : null
            });
        }

        if (conclusion == "success")
        {
            var user = await FindConnectedUser(culprit.Login, culprit.Id);
            if (user != null)
            {
                await NotifyCompleted(user.GitHubId, true);
                _logger.LogInformation("Workflow success notified to {Login}", culprit.Login);
            }

            var targetIds = DeserializeTargetIds(dbRun?.TargetGitHubIds);
            foreach (var tid in targetIds)
            {
                if (tid != user?.GitHubId)
                {
                    await NotifyCompleted(tid, true);
                    _logger.LogInformation("Workflow success also notified to target {TargetId}", tid);
                }
            }

            LogWebhook("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, notified");
            return Ok(new { runId, conclusion });
        }

        if (conclusion is "cancelled" or "timed_out" or "stale" or "action_required" or "skipped" or "neutral" or "startup_failure")
        {
            var cancelUser = await FindConnectedUser(culprit.Login, culprit.Id);
            if (cancelUser != null)
                await NotifyCompleted(cancelUser.GitHubId, false);
            var cancelTargetIds = DeserializeTargetIds(dbRun?.TargetGitHubIds);
            foreach (var tid in cancelTargetIds)
            {
                if (tid != cancelUser?.GitHubId)
                    await NotifyCompleted(tid, false);
            }
            LogWebhook("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, no punishment");
            return Ok(new { runId, conclusion });
        }

        // Save punishment event (always)
        var historyEvent = new PunishmentEvent
        {
            RunId = runId, CulpritLogin = culprit.Login, CulpritGitHubId = culprit.Id,
            RepoFullName = repoFullName, WorkflowName = workflowName, WorkflowUrl = workflowUrl,
            OccurredAt = DateTime.UtcNow
        };

        var user2 = await FindConnectedUser(culprit.Login, culprit.Id);
        historyEvent.WasNotified = user2 != null;
        _db.PunishmentEvents.Add(historyEvent);
        await _db.SaveChangesAsync();

        // Notify via SignalR if connected
        if (user2 != null)
        {
            await NotifyCompleted(user2.GitHubId, false);
            _logger.LogInformation("Punishment sent to {Login}", culprit.Login);
        }

        var failTargetIds = DeserializeTargetIds(dbRun?.TargetGitHubIds);
        foreach (var tid in failTargetIds)
        {
            if (tid != user2?.GitHubId)
            {
                await NotifyCompleted(tid, false);
                _logger.LogInformation("Punishment also notified to target {TargetId}", tid);
            }
        }

        LogWebhook("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, failure handled");
        return Ok(new { runId, conclusion });
    }

    private CulpritInfo? ResolveWorkflowCulprit(JsonElement payload)
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

    // ─── check_suite: dispatch by action ───────────────────────────────────

    private async Task<IActionResult> HandleCheckSuite(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var repo = TryGetRepo(payload);

        if (action == "requested" || action == "rerequested") return await HandleCheckSuiteRequested(payload);
        if (action == "completed") return await HandleCheckSuiteCompleted(payload);
        LogWebhook("check_suite", action, repo, null, "ignored", $"Unsupported action '{action}'");
        return Ok($"Ignored: check_suite action '{action}'.");
    }

    private async Task<IActionResult> HandleCheckSuiteRequested(JsonElement payload)
    {
        var checkSuite = payload.GetProperty("check_suite");
        var (authorLogin, authorId, prNumber) = ResolveCheckSuiteAuthor(payload);

        if (authorLogin == null)
        {
            _logger.LogWarning("Could not determine PR author for check_suite requested.");
            return Ok("Could not resolve author.");
        }

        var user = await FindConnectedUser(authorLogin, authorId);
        if (user == null) return Ok($"User '{authorLogin}' not connected.");

        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var branch = checkSuite.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var appName = checkSuite.TryGetProperty("app", out var app) &&
                      app.TryGetProperty("name", out var an)
            ? an.GetString() : "Checks";

        await _hubContext.Clients.Group(user.GitHubId.ToString()).SendAsync("CheckSuiteStarted", new
        {
            checkSuiteId = checkSuite.GetProperty("id").GetInt64(),
            appName, repo, branch, prNumber, author = authorLogin
        });

        _logger.LogInformation("Check suite started notified to {Login}", authorLogin);
        return Ok(new { notified = authorLogin });
    }

    private async Task<IActionResult> HandleCheckSuiteCompleted(JsonElement payload)
    {
        var checkSuite = payload.GetProperty("check_suite");
        var conclusion = checkSuite.GetProperty("conclusion").GetString();

        if (conclusion != "success" && conclusion != "failure")
            return Ok($"Ignored: conclusion is '{conclusion}'.");

        var repoFullName = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var checkSuiteId = checkSuite.GetProperty("id").GetInt64();
        var headBranch = checkSuite.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var headSha = checkSuite.TryGetProperty("head_sha", out var hs) ? hs.GetString() : null;

        var (authorLogin, authorId, prNumber) = ResolveCheckSuiteAuthor(payload);

        if (authorLogin == null)
        {
            _logger.LogWarning("Could not determine PR author for check_suite {Id}.", checkSuiteId);
            return Ok("Could not resolve author.");
        }

        _logger.LogInformation(
            "Check suite completed: author={Login}, conclusion={Conclusion}", authorLogin, conclusion);

        // Save event
        var checkEvent = new CheckSuiteEvent
        {
            CheckSuiteId = checkSuiteId, Conclusion = conclusion,
            HeadBranch = headBranch, HeadSha = headSha,
            PrAuthorLogin = authorLogin, PrAuthorGitHubId = authorId,
            PrNumber = prNumber, RepoFullName = repoFullName,
            OccurredAt = DateTime.UtcNow
        };

        var user = await FindConnectedUser(authorLogin, authorId);
        checkEvent.WasNotified = user != null;
        _db.CheckSuiteEvents.Add(checkEvent);
        await _db.SaveChangesAsync();

        if (user == null)
        {
            _logger.LogInformation("User '{Login}' not connected.", authorLogin);
            return Ok($"User '{authorLogin}' is not currently connected.");
        }

        var succeeded = conclusion == "success";
        await _hubContext.Clients.Group(user.GitHubId.ToString()).SendAsync("CheckSuiteCompleted", new
        {
            checkSuiteId, conclusion, succeeded, prNumber,
            repo = repoFullName, headBranch, prAuthor = authorLogin
        });

        _logger.LogInformation("Check suite notification sent to {Login} ({Conclusion})", authorLogin, conclusion);
        return Ok(new { notified = authorLogin, conclusion });
    }

    // ─── shared helpers ────────────────────────────────────────────────────

    // ─── pull_request: dispatch by action ──────────────────────────────────

    private async Task<IActionResult> HandlePullRequest(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var pr = payload.GetProperty("pull_request");
        var prNumber = pr.GetProperty("number").GetInt32();
        var title = pr.GetProperty("title").GetString() ?? "";
        var htmlUrl = pr.GetProperty("html_url").GetString() ?? "";
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var baseBranch = pr.GetProperty("base").GetProperty("ref").GetString() ?? "";
        var headBranch = pr.GetProperty("head").GetProperty("ref").GetString() ?? "";
        var authorLogin = pr.GetProperty("user").GetProperty("login").GetString() ?? "";
        var authorId = pr.GetProperty("user").TryGetProperty("id", out var aid) ? aid.GetInt64() : (long?)null;
        var draft = pr.TryGetProperty("draft", out var d) && d.GetBoolean();

        if (action == "opened") return await HandlePullRequestOpened(prNumber, title, htmlUrl, repo, baseBranch, headBranch, authorLogin, authorId, draft,
            pr.TryGetProperty("head", out var head) && head.TryGetProperty("sha", out var sha) ? sha.GetString() : null);
        if (action == "synchronize") return await HandlePullRequestSynchronize(prNumber, repo,
            pr.TryGetProperty("head", out var head2) && head2.TryGetProperty("sha", out var sha2) ? sha2.GetString() : null);
        if (action == "ready_for_review") return await HandlePullRequestReadyForReview(prNumber, repo);
        if (action == "converted_to_draft") return await HandlePullRequestConvertedToDraft(prNumber, repo);
        if (action == "closed") return await HandlePullRequestClosed(prNumber, title, htmlUrl, repo, baseBranch, headBranch, authorLogin, authorId, pr);
        LogWebhook("pull_request", action, repo, null, "ignored", $"Unsupported action '{action}'");
        return Ok($"Ignored: pull_request action '{action}'.");
    }

    private async Task<IActionResult> HandlePullRequestOpened(
        int prNumber, string title, string htmlUrl, string repo,
        string baseBranch, string headBranch, string authorLogin, long? authorId,
        bool draft, string? headSha)
    {
        _db.PullRequestEvents.Add(new PullRequestEvent
        {
            PrNumber = prNumber, Title = title, AuthorLogin = authorLogin,
            AuthorGitHubId = authorId, RepoFullName = repo,
            HeadBranch = headBranch, BaseBranch = baseBranch, PrUrl = htmlUrl,
            Status = "open", Draft = draft, HeadSha = headSha, OccurredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        _logger.LogInformation("PR #{PrNumber} opened by {Author} (draft={Draft})", prNumber, authorLogin, draft);
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, status = "tracking" });
    }

    private async Task<IActionResult> HandlePullRequestSynchronize(int prNumber, string repo, string? headSha)
    {
        var existing = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        if (existing != null)
        {
            existing.ReviewApproved = false;
            existing.ApprovedBy = null;
            existing.HeadSha = headSha;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} synchronized — approval reset, headSha={headSha}", prNumber, headSha);
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, status = "synchronized" });
    }

    private async Task<IActionResult> HandlePullRequestReadyForReview(int prNumber, string repo)
    {
        var existing = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        if (existing != null)
        {
            existing.Draft = false;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} marked as ready for review", prNumber);
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, status = "ready_for_review" });
    }

    private async Task<IActionResult> HandlePullRequestConvertedToDraft(int prNumber, string repo)
    {
        var existing = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        if (existing != null)
        {
            existing.Draft = true;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} converted to draft", prNumber);
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, status = "converted_to_draft" });
    }

    private async Task<IActionResult> HandlePullRequestClosed(
        int prNumber, string title, string htmlUrl, string repo,
        string baseBranch, string headBranch, string authorLogin, long? authorId,
        JsonElement pr)
    {
        var merged = pr.TryGetProperty("merged", out var m) && m.GetBoolean();
        var status = merged ? "merged" : "closed";

        var existing = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        if (existing != null)
        {
            existing.Status = status;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} {Status} by {Author}", prNumber, status, authorLogin);

        if (merged)
        {
            var mergedByLogin = pr.TryGetProperty("merged_by", out var mb)
                ? mb.TryGetProperty("login", out var ml) ? ml.GetString() : null
                : null;
            var headSha = pr.TryGetProperty("merge_commit_sha", out var mcs) ? mcs.GetString() : null;

            await _hubContext.Clients.All.SendAsync("MainBranchUpdated", new
            {
                repo,
                prNumber,
                mergedBy = mergedByLogin ?? "unknown",
                headSha
            });
            _logger.LogInformation("MainBranchUpdate sent for {Repo} PR #{PrNumber} by {MergedBy}", repo, prNumber, mergedByLogin);
        }

        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, status });
    }

    private async Task<IActionResult> HandlePullRequestReview(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        if (action != "submitted")
        {
            LogWebhook("pull_request_review", action, TryGetRepo(payload), null, "ignored", $"Unsupported action '{action}'");
            return Ok($"Ignored: pull_request_review action '{action}'.");
        }

        var review = payload.GetProperty("review");
        var reviewState = review.GetProperty("state").GetString();
        var pr = payload.GetProperty("pull_request");
        var prNumber = pr.GetProperty("number").GetInt32();
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var reviewerLogin = review.GetProperty("user").GetProperty("login").GetString() ?? "unknown";

        var existing = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        if (existing == null)
        {
            LogWebhook("pull_request_review", action, repo, null, "ignored", "PR not tracked");
            return Ok("PR not tracked, ignoring.");
        }

        var approved = reviewState == "approved";
        existing.ReviewApproved = approved;
        existing.ApprovedBy = approved ? reviewerLogin : null;
        await _db.SaveChangesAsync();

        LogWebhook("pull_request_review", action, repo, null, approved ? "approved" : reviewState!,
            $"PR #{prNumber} reviewed by {reviewerLogin}: {reviewState}");

        // Notify PR author when approved
        if (approved && existing.AuthorGitHubId.HasValue)
        {
            var approverToken = await _db.GitHubUsers
                .Where(u => u.GitHubId == existing.AuthorGitHubId.Value)
                .Select(u => u.SignalRConnectionId)
                .FirstOrDefaultAsync();

            if (!string.IsNullOrEmpty(approverToken))
            {
                await _hubContext.Clients.Client(approverToken)
                    .SendAsync("PrApproved", new { prNumber, repo, reviewerLogin, title = existing.Title });
            }
        }

        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, approved });
    }

    private async Task<IActionResult> HandleIssueComment(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        if (action != "created")
        {
            LogWebhook("issue_comment", action, TryGetRepo(payload), null, "ignored", $"Unsupported action '{action}'");
            return Ok($"Ignored: issue_comment action '{action}'.");
        }

        var issue = payload.GetProperty("issue");
        if (!issue.TryGetProperty("pull_request", out _))
        {
            LogWebhook("issue_comment", action, TryGetRepo(payload), null, "ignored", "Not a PR comment");
            return Ok("Not a PR comment, ignoring.");
        }

        var comment = payload.GetProperty("comment");
        var commenterType = comment.GetProperty("user").GetProperty("type").GetString();
        if (commenterType != "User")
        {
            LogWebhook("issue_comment", action, TryGetRepo(payload), null, "ignored", $"Commenter type={commenterType}, skipping");
            return Ok($"Ignored: commenter type '{commenterType}'.");
        }

        var prNumber = issue.GetProperty("number").GetInt32();
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var commenterLogin = comment.GetProperty("user").GetProperty("login").GetString() ?? "unknown";
        var commentBody = comment.TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";

        var existing = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        if (existing == null)
        {
            LogWebhook("issue_comment", action, repo, null, "ignored", "PR not tracked");
            return Ok("PR not tracked, ignoring.");
        }

        existing.LastCommentBy = commenterLogin;
        existing.LastCommentBody = commentBody.Length > 500 ? commentBody[..500] : commentBody;
        existing.LastCommentAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        LogWebhook("issue_comment", action, repo, null, "processed",
            $"PR #{prNumber} comment by {commenterLogin}");

        // Notify PR author
        if (existing.AuthorGitHubId.HasValue)
        {
            var authorConn = await _db.GitHubUsers
                .Where(u => u.GitHubId == existing.AuthorGitHubId.Value)
                .Select(u => u.SignalRConnectionId)
                .FirstOrDefaultAsync();

            if (!string.IsNullOrEmpty(authorConn))
            {
                await _hubContext.Clients.Client(authorConn)
                    .SendAsync("PrCommented", new
                    {
                        prNumber, repo, commenterLogin,
                        title = existing.Title,
                        commentBody = existing.LastCommentBody
                    });
            }
        }

        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, commenterLogin });
    }

    private (string? login, long? id, int? prNumber) ResolveCheckSuiteAuthor(JsonElement payload)
    {
        var checkSuite = payload.GetProperty("check_suite");
        string? authorLogin = null;
        long? authorId = null;
        int? prNumber = null;

        if (checkSuite.TryGetProperty("pull_requests", out var prs) && prs.GetArrayLength() > 0)
        {
            var pr = prs[0];
            prNumber = pr.TryGetProperty("number", out var pn) ? pn.GetInt32() : null;

            if (pr.TryGetProperty("head", out var head) &&
                head.TryGetProperty("user", out var headUser))
            {
                authorId = headUser.TryGetProperty("id", out var hid) ? hid.GetInt64() : null;
                authorLogin = headUser.GetProperty("login").GetString();
            }

            if (authorLogin == null && pr.TryGetProperty("base", out var basePr) &&
                basePr.TryGetProperty("user", out var baseUser))
            {
                authorId = baseUser.TryGetProperty("id", out var bid) ? bid.GetInt64() : null;
                authorLogin = baseUser.GetProperty("login").GetString();
            }
        }

        if (authorLogin == null &&
            checkSuite.TryGetProperty("head_commit", out var commit) &&
            commit.ValueKind != JsonValueKind.Null &&
            commit.TryGetProperty("author", out var author))
        {
            authorLogin = author.TryGetProperty("username", out var uname)
                ? uname.GetString()
                : author.GetProperty("name").GetString();
        }

        return (authorLogin, authorId, prNumber);
    }

    private static long[] DeserializeTargetIds(string? raw) =>
        raw is { Length: > 0 } && System.Text.Json.JsonSerializer.Deserialize<long[]>(raw) is { } arr ? arr : [];

    private async Task<Models.GitHubUser?> FindConnectedUser(string login, long? gitHubId)
    {
        return gitHubId.HasValue
            ? await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId.Value && u.SignalRConnectionId != null)
            : await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == login && u.SignalRConnectionId != null);
    }

    private async Task<Models.GitHubUser?> FindUserByLogin(string login)
    {
        return await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == login);
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

public record WebhookLogEntry
{
    public string EventType { get; init; } = "";
    public string? Action { get; init; }
    public string? Repo { get; init; }
    public string? WorkflowName { get; init; }
    public string Outcome { get; init; } = "";
    public string? Message { get; init; }
    public DateTime OccurredAt { get; init; }
}

internal record CulpritInfo(string Login, long? Id);
