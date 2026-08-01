using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;
using Statefalse.Api.Hubs;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// GitHub webhook processing: HMAC verification + per-event handlers that
/// persist state and fan out SignalR notifications.
/// </summary>
public class WebhookService
{
    private static readonly ConcurrentQueue<WebhookLogEntry> _recentLogs = new();

    private readonly IHubContext<PunishmentHub> _hub;
    private readonly AppDbContext _db;
    private readonly ILogger<WebhookService> _logger;
    private readonly IConfiguration _configuration;

    public WebhookService(
        IHubContext<PunishmentHub> hub,
        AppDbContext db,
        ILogger<WebhookService> logger,
        IConfiguration configuration)
    {
        _hub = hub;
        _db = db;
        _logger = logger;
        _configuration = configuration;
    }

    public List<WebhookLogEntry> GetLogs(int limit)
        => _recentLogs.Reverse().Take(limit).ToList();

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

    public async Task<ApiResult> HandleGitHubWebhookAsync(
        string? signatureHeader,
        Func<Task<string>> readRawBody,
        Func<Task<JsonElement?>> readJsonBody,
        string? eventType)
    {
        // Verify HMAC signature if WebhookSecret is configured
        var webhookSecret = _configuration["WebhookSecret"];
        if (!string.IsNullOrEmpty(webhookSecret) && webhookSecret != "set-me-in-env-vars" && webhookSecret != "set-your-github-webhook-secret-here")
        {
            if (string.IsNullOrEmpty(signatureHeader))
            {
                LogWebhook("unknown", null, null, null, "rejected", "Missing X-Hub-Signature-256");
                return ApiResult.Unauthorized("Missing X-Hub-Signature-256");
            }

            var rawBody = await readRawBody();
            var key = Encoding.UTF8.GetBytes(webhookSecret);
            var hash = HMACSHA256.HashData(key, Encoding.UTF8.GetBytes(rawBody));
            var expected = "sha256=" + Convert.ToHexString(hash).ToLowerInvariant();

            if (!CryptographicOperations.FixedTimeEquals(
                    Encoding.UTF8.GetBytes(signatureHeader),
                    Encoding.UTF8.GetBytes(expected)))
            {
                LogWebhook("unknown", null, null, null, "rejected", "Invalid webhook signature");
                return ApiResult.Unauthorized("Invalid signature");
            }
        }

        var payload = await readJsonBody();
        if (payload is not { } body)
            return ApiResult.BadRequest("Invalid JSON payload");

        return eventType switch
        {
            "workflow_run" => await HandleWorkflowRun(body),
            "check_suite" => await HandleCheckSuite(body),
            "pull_request" => await HandlePullRequest(body),
            "pull_request_review" => await HandlePullRequestReview(body),
            "issue_comment" => await HandleIssueComment(body),
            "pull_request_review_comment" => await HandleReviewComment(body),
            _ => LogAndIgnore(eventType ?? "unknown", null, TryGetRepo(body), null, "Unsupported event type")
        };
    }

    // ─── workflow_run: dispatch by action ──────────────────────────────────

    private async Task<ApiResult> HandleWorkflowRun(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var repo = TryGetRepo(payload);
        var name = TryGetWorkflowName(payload);

        if (action == "in_progress" || action == "requested") return await HandleWorkflowRunInProgress(payload);
        if (action == "completed") return await HandleWorkflowRunCompleted(payload);
        LogWebhook("workflow_run", action, repo, name, "ignored", $"Unsupported action '{action}'");
        return ApiResult.Ok($"Ignored: workflow_run action '{action}'.");
    }

    private async Task<ApiResult> HandleWorkflowRunInProgress(JsonElement payload)
    {
        var run = payload.GetProperty("workflow_run");
        var culprit = ResolveWorkflowCulprit(payload);
        if (culprit == null)
        {
            LogWebhook("workflow_run", "in_progress", TryGetRepo(payload), TryGetWorkflowName(payload), "ignored", "Could not resolve actor");
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

        // Update existing in_progress row, or create new one for reruns
        var existingInProgress = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && w.Status == "in_progress")
            .FirstOrDefaultAsync();
        if (existingInProgress != null)
        {
            // Already tracking this run — likely a duplicate webhook event
            await _db.SaveChangesAsync();
            return ApiResult.Ok(new { runId });
        }

        var existingFinal = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && (w.Status == "success" || w.Status == "failure"))
            .FirstOrDefaultAsync();
        _ = existingFinal; // rerun → a new entry is created below

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
                await _hub.Clients.Group(user.GitHubId.ToString()).SendAsync("WorkflowRunStarted", new
                {
                    id = newRun.Id, runId, workflowName = name, repo, branch, trigger, actor = culprit.Login, htmlUrl = url
                });
                _logger.LogInformation("Running workflow {RunId} notified to {Login}", runId, culprit.Login);
            }
        }

        // Always notify PR update so ciStatus refreshes even for ignored workflows
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");

        var actor = culprit?.Login ?? "unknown";
        LogWebhook("workflow_run", "in_progress", repo, name, isIgnored ? "ignored" : "processed", $"actor={actor}, runId={runId}");
        return ApiResult.Ok(new { runId });
    }

    private async Task<ApiResult> HandleWorkflowRunCompleted(JsonElement payload)
    {
        var workflowRun = payload.GetProperty("workflow_run");
        var conclusion = workflowRun.GetProperty("conclusion").GetString();

        var culprit = ResolveWorkflowCulprit(payload);
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
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");

        // Skip SignalR completion notifications for ignored workflows
        if (isIgnored) return ApiResult.Ok(new { runId });

        // Notify both the culprit and the target user (if set) via SignalR
        async Task NotifyCompleted(long gitHubId, bool succeeded)
        {
            await _hub.Clients.Group(gitHubId.ToString()).SendAsync("WorkflowRunCompleted", new
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

            var targetIds = IdListSerializer.Deserialize(dbRun?.TargetGitHubIds);
            foreach (var tid in targetIds)
            {
                if (tid != user?.GitHubId)
                {
                    await NotifyCompleted(tid, true);
                    _logger.LogInformation("Workflow success also notified to target {TargetId}", tid);
                }
            }

            LogWebhook("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, notified");
            return ApiResult.Ok(new { runId, conclusion });
        }

        if (conclusion is "cancelled" or "timed_out" or "stale" or "action_required" or "skipped" or "neutral" or "startup_failure")
        {
            LogWebhook("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, no notification (non-failure)");
            return ApiResult.Ok(new { runId, conclusion });
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

        var failTargetIds = IdListSerializer.Deserialize(dbRun?.TargetGitHubIds);
        foreach (var tid in failTargetIds)
        {
            if (tid != user2?.GitHubId)
            {
                await NotifyCompleted(tid, false);
                _logger.LogInformation("Punishment also notified to target {TargetId}", tid);
            }
        }

        LogWebhook("workflow_run", "completed", repoFullName, workflowName, "processed", $"conclusion={conclusion}, failure handled");
        return ApiResult.Ok(new { runId, conclusion });
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

    private async Task<ApiResult> HandleCheckSuite(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var repo = TryGetRepo(payload);

        if (action == "requested" || action == "rerequested") return await HandleCheckSuiteRequested(payload);
        if (action == "completed") return await HandleCheckSuiteCompleted(payload);
        LogWebhook("check_suite", action, repo, null, "ignored", $"Unsupported action '{action}'");
        return ApiResult.Ok($"Ignored: check_suite action '{action}'.");
    }

    private async Task<ApiResult> HandleCheckSuiteRequested(JsonElement payload)
    {
        var checkSuite = payload.GetProperty("check_suite");
        var (authorLogin, authorId, prNumber) = ResolveCheckSuiteAuthor(payload);

        if (authorLogin == null)
        {
            _logger.LogWarning("Could not determine PR author for check_suite requested.");
            return ApiResult.Ok("Could not resolve author.");
        }

        var user = await FindConnectedUser(authorLogin, authorId);
        if (user == null) return ApiResult.Ok($"User '{authorLogin}' not connected.");

        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var branch = checkSuite.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var appName = checkSuite.TryGetProperty("app", out var app) &&
                      app.TryGetProperty("name", out var an)
            ? an.GetString() : "Checks";

        await _hub.Clients.Group(user.GitHubId.ToString()).SendAsync("CheckSuiteStarted", new
        {
            checkSuiteId = checkSuite.GetProperty("id").GetInt64(),
            appName, repo, branch, prNumber, author = authorLogin
        });

        _logger.LogInformation("Check suite started notified to {Login}", authorLogin);
        return ApiResult.Ok(new { notified = authorLogin });
    }

    private async Task<ApiResult> HandleCheckSuiteCompleted(JsonElement payload)
    {
        var checkSuite = payload.GetProperty("check_suite");
        var conclusion = checkSuite.GetProperty("conclusion").GetString();

        if (conclusion != "success" && conclusion != "failure")
            return ApiResult.Ok($"Ignored: conclusion is '{conclusion}'.");

        var repoFullName = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var checkSuiteId = checkSuite.GetProperty("id").GetInt64();
        var headBranch = checkSuite.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var headSha = checkSuite.TryGetProperty("head_sha", out var hs) ? hs.GetString() : null;

        var (authorLogin, authorId, prNumber) = ResolveCheckSuiteAuthor(payload);

        if (authorLogin == null)
        {
            _logger.LogWarning("Could not determine PR author for check_suite {Id}.", checkSuiteId);
            return ApiResult.Ok("Could not resolve author.");
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

        // Always notify all clients so Active PRs refresh ciStatus, even if the
        // PR author isn't currently connected (other team members may be watching).
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");

        if (user == null)
        {
            _logger.LogInformation("User '{Login}' not connected.", authorLogin);
            return ApiResult.Ok($"User '{authorLogin}' is not currently connected.");
        }

        var succeeded = conclusion == "success";
        await _hub.Clients.Group(user.GitHubId.ToString()).SendAsync("CheckSuiteCompleted", new
        {
            checkSuiteId, conclusion, succeeded, prNumber,
            repo = repoFullName, headBranch, prAuthor = authorLogin
        });

        _logger.LogInformation("Check suite notification sent to {Login} ({Conclusion})", authorLogin, conclusion);
        return ApiResult.Ok(new { notified = authorLogin, conclusion });
    }

    // ─── pull_request: dispatch by action ──────────────────────────────────

    private async Task<ApiResult> HandlePullRequest(JsonElement payload)
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
        return ApiResult.Ok($"Ignored: pull_request action '{action}'.");
    }

    private async Task<ApiResult> HandlePullRequestOpened(
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
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, status = "tracking" });
    }

    private async Task<ApiResult> HandlePullRequestSynchronize(int prNumber, string repo, string? headSha)
    {
        var existing = await FindOpenPrAsync(prNumber, repo);

        if (existing != null)
        {
            existing.ReviewApproved = false;
            existing.ApprovedBy = null;
            existing.HeadSha = headSha;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} synchronized — approval reset, headSha={headSha}", prNumber, headSha);
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, status = "synchronized" });
    }

    private async Task<ApiResult> HandlePullRequestReadyForReview(int prNumber, string repo)
    {
        var existing = await FindOpenPrAsync(prNumber, repo);

        if (existing != null)
        {
            existing.Draft = false;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} marked as ready for review", prNumber);
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, status = "ready_for_review" });
    }

    private async Task<ApiResult> HandlePullRequestConvertedToDraft(int prNumber, string repo)
    {
        var existing = await FindOpenPrAsync(prNumber, repo);

        if (existing != null)
        {
            existing.Draft = true;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} converted to draft", prNumber);
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, status = "converted_to_draft" });
    }

    private async Task<ApiResult> HandlePullRequestClosed(
        int prNumber, string title, string htmlUrl, string repo,
        string baseBranch, string headBranch, string authorLogin, long? authorId,
        JsonElement pr)
    {
        var merged = pr.TryGetProperty("merged", out var m) && m.GetBoolean();
        var status = merged ? "merged" : "closed";

        var existing = await FindOpenPrAsync(prNumber, repo);

        if (existing != null)
        {
            existing.Status = status;
            if (merged) existing.OccurredAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} {Status} by {Author}", prNumber, status, authorLogin);

        if (merged)
        {
            var mergedByLogin = pr.TryGetProperty("merged_by", out var mb)
                ? mb.TryGetProperty("login", out var ml) ? ml.GetString() : null
                : null;
            var headSha = pr.TryGetProperty("merge_commit_sha", out var mcs) ? mcs.GetString() : null;

            await _hub.Clients.All.SendAsync("MainBranchUpdated", new
            {
                repo,
                prNumber,
                mergedBy = mergedByLogin ?? "unknown",
                headSha
            });
            _logger.LogInformation("MainBranchUpdate sent for {Repo} PR #{PrNumber} by {MergedBy}", repo, prNumber, mergedByLogin);
        }

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, status });
    }

    // ─── reviews & comments ────────────────────────────────────────────────

    private async Task<ApiResult> HandlePullRequestReview(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        if (action != "submitted")
        {
            LogWebhook("pull_request_review", action, TryGetRepo(payload), null, "ignored", $"Unsupported action '{action}'");
            return ApiResult.Ok($"Ignored: pull_request_review action '{action}'.");
        }

        var review = payload.GetProperty("review");
        var reviewState = review.GetProperty("state").GetString();
        var pr = payload.GetProperty("pull_request");
        var prNumber = pr.GetProperty("number").GetInt32();
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var reviewerLogin = review.GetProperty("user").GetProperty("login").GetString() ?? "unknown";

        var existing = await FindOpenPrAsync(prNumber, repo);

        if (existing == null)
        {
            LogWebhook("pull_request_review", action, repo, null, "ignored", "PR not tracked");
            return ApiResult.Ok("PR not tracked, ignoring.");
        }

        // Only update ReviewApproved on explicit approval or dismissal.
        // "commented" reviews must NOT reset an existing approval — that's the
        // most common cause of PRs staying stuck on "review" instead of "ready".
        var approved = reviewState == "approved";
        if (approved)
        {
            existing.ReviewApproved = true;
            existing.ApprovedBy = reviewerLogin;
        }
        else if (reviewState == "dismissed" || reviewState == "changes_requested")
        {
            existing.ReviewApproved = false;
            existing.ApprovedBy = null;
        }
        // "commented" → don't touch ReviewApproved at all
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
                await _hub.Clients.Client(approverToken)
                    .SendAsync("PrApproved", new { prNumber, repo, reviewerLogin, title = existing.Title });
            }
        }

        // Notify subscribers (excluding the reviewer themselves)
        var reviewerUser = await _db.GitHubUsers.Where(u => u.GitHubUsername == reviewerLogin).Select(u => u.GitHubId).FirstOrDefaultAsync();
        await NotifySubscribers(existing, "PrApproved", new { prNumber, repo, reviewerLogin, title = existing.Title }, reviewerUser);

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, approved });
    }

    private async Task<ApiResult> HandleIssueComment(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        if (action != "created")
        {
            LogWebhook("issue_comment", action, TryGetRepo(payload), null, "ignored", $"Unsupported action '{action}'");
            return ApiResult.Ok($"Ignored: issue_comment action '{action}'.");
        }

        var issue = payload.GetProperty("issue");
        if (!issue.TryGetProperty("pull_request", out _))
        {
            LogWebhook("issue_comment", action, TryGetRepo(payload), null, "ignored", "Not a PR comment");
            return ApiResult.Ok("Not a PR comment, ignoring.");
        }

        var comment = payload.GetProperty("comment");
        var commenterType = comment.GetProperty("user").GetProperty("type").GetString();
        if (commenterType != "User")
        {
            LogWebhook("issue_comment", action, TryGetRepo(payload), null, "ignored", $"Commenter type={commenterType}, skipping");
            return ApiResult.Ok($"Ignored: commenter type '{commenterType}'.");
        }

        var prNumber = issue.GetProperty("number").GetInt32();
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var commenterLogin = comment.GetProperty("user").GetProperty("login").GetString() ?? "unknown";
        var commentBody = comment.TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";
        var commentUrl = comment.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;

        var existing = await FindOpenPrAsync(prNumber, repo);

        if (existing == null)
        {
            LogWebhook("issue_comment", action, repo, null, "ignored", "PR not tracked");
            return ApiResult.Ok("PR not tracked, ignoring.");
        }

        existing.LastCommentBy = commenterLogin;
        existing.LastCommentBody = commentBody.Length > 500 ? commentBody[..500] : commentBody;
        existing.LastCommentAt = DateTime.UtcNow;
        existing.LastCommentUrl = commentUrl;
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
                await _hub.Clients.Client(authorConn)
                    .SendAsync("PrCommented", new
                    {
                        prNumber, repo, commenterLogin,
                        title = existing.Title,
                        commentBody = existing.LastCommentBody,
                        commentUrl
                    });
            }
        }

        // Notify subscribers (excluding the commenter)
        var commenterUser = await _db.GitHubUsers.Where(u => u.GitHubUsername == commenterLogin).Select(u => u.GitHubId).FirstOrDefaultAsync();
        await NotifySubscribers(existing, "PrCommented", new
        {
            prNumber, repo, commenterLogin,
            title = existing.Title,
            commentBody = existing.LastCommentBody,
            commentUrl
        }, commenterUser);

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, commenterLogin });
    }

    private async Task<ApiResult> HandleReviewComment(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        if (action != "created")
        {
            LogWebhook("pull_request_review_comment", action, TryGetRepo(payload), null, "ignored", $"Unsupported action '{action}'");
            return ApiResult.Ok($"Ignored: pull_request_review_comment action '{action}'.");
        }

        var comment = payload.GetProperty("comment");
        var commenterType = comment.GetProperty("user").GetProperty("type").GetString();
        if (commenterType != "User")
        {
            LogWebhook("pull_request_review_comment", action, TryGetRepo(payload), null, "ignored", $"Commenter type={commenterType}, skipping");
            return ApiResult.Ok($"Ignored: commenter type '{commenterType}'.");
        }

        var pr = payload.GetProperty("pull_request");
        var prNumber = pr.GetProperty("number").GetInt32();
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var commenterLogin = comment.GetProperty("user").GetProperty("login").GetString() ?? "unknown";
        var commentBody = comment.TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";
        var commentUrl = comment.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
        var filePath = comment.TryGetProperty("path", out var p) ? p.GetString() : null;
        int? line = comment.TryGetProperty("line", out var l) ? l.GetInt32() : null;

        var existing = await FindOpenPrAsync(prNumber, repo);

        if (existing == null)
        {
            LogWebhook("pull_request_review_comment", action, repo, null, "ignored", "PR not tracked");
            return ApiResult.Ok("PR not tracked, ignoring.");
        }

        existing.LastCommentBy = commenterLogin;
        existing.LastCommentBody = commentBody.Length > 500 ? commentBody[..500] : commentBody;
        existing.LastCommentAt = DateTime.UtcNow;
        existing.LastCommentUrl = commentUrl;
        existing.LastReviewFilePath = filePath;
        existing.LastReviewLine = line;
        await _db.SaveChangesAsync();

        LogWebhook("pull_request_review_comment", action, repo, null, "processed",
            $"PR #{prNumber} review comment by {commenterLogin} on {filePath}:{line}");

        // Notify PR author
        if (existing.AuthorGitHubId.HasValue)
        {
            var authorConn = await _db.GitHubUsers
                .Where(u => u.GitHubId == existing.AuthorGitHubId.Value)
                .Select(u => u.SignalRConnectionId)
                .FirstOrDefaultAsync();

            if (!string.IsNullOrEmpty(authorConn))
            {
                await _hub.Clients.Client(authorConn)
                    .SendAsync("PrCommented", new
                    {
                        prNumber, repo, commenterLogin,
                        title = existing.Title,
                        commentBody = existing.LastCommentBody,
                        commentUrl,
                        filePath,
                        line
                    });
            }
        }

        // Notify subscribers (excluding the commenter)
        var rcUser = await _db.GitHubUsers.Where(u => u.GitHubUsername == commenterLogin).Select(u => u.GitHubId).FirstOrDefaultAsync();
        await NotifySubscribers(existing, "PrCommented", new
        {
            prNumber, repo, commenterLogin,
            title = existing.Title,
            commentBody = existing.LastCommentBody,
            commentUrl, filePath, line
        }, rcUser);

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { prNumber, commenterLogin, filePath, line });
    }

    // ─── shared helpers ────────────────────────────────────────────────────

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

    private Task<PullRequestEvent?> FindOpenPrAsync(long prNumber, string repo)
        => _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

    private async Task NotifySubscribers(PullRequestEvent pr, string eventName, object data, long? excludeGitHubId = null)
    {
        var subscriberIds = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (subscriberIds.Length == 0) return;

        var connections = await _db.GitHubUsers
            .Where(u => subscriberIds.Contains(u.GitHubId) && u.SignalRConnectionId != null
                && (excludeGitHubId == null || u.GitHubId != excludeGitHubId.Value))
            .Select(u => u.SignalRConnectionId!)
            .ToListAsync();

        foreach (var conn in connections)
        {
            await _hub.Clients.Client(conn).SendAsync(eventName, data);
        }
    }

    private Task<GitHubUser?> FindConnectedUser(string login, long? gitHubId)
        => gitHubId.HasValue
            ? _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId.Value && u.SignalRConnectionId != null)
            : _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == login && u.SignalRConnectionId != null);

    private Task<GitHubUser?> FindUserByLogin(string login)
        => _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == login);

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

    private static ApiResult LogAndIgnore(string eventType, string? action, string? repo, string? workflowName, string message)
    {
        LogWebhook(eventType, action, repo, workflowName, "ignored", message);
        return ApiResult.Ok($"Ignored: unsupported event '{eventType}'.");
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
