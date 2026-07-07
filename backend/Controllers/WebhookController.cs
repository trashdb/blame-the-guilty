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

    [HttpPost("github")]
    public async Task<IActionResult> HandleGitHubWebhook([FromBody] JsonElement payload)
    {
        var eventType = Request.Headers["X-GitHub-Event"].FirstOrDefault() ?? "";

        return eventType switch
        {
            "workflow_run" => await HandleWorkflowRun(payload),
            "check_suite" => await HandleCheckSuite(payload),
            "pull_request" => await HandlePullRequest(payload),
            _ => Ok($"Ignored: unsupported event '{eventType}'.")
        };
    }

    // ─── workflow_run: dispatch by action ──────────────────────────────────

    private async Task<IActionResult> HandleWorkflowRun(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();

        return action switch
        {
            "in_progress" => await HandleWorkflowRunInProgress(payload),
            "completed" => await HandleWorkflowRunCompleted(payload),
            _ => Ok($"Ignored: workflow_run action '{action}'.")
        };
    }

    private async Task<IActionResult> HandleWorkflowRunInProgress(JsonElement payload)
    {
        var run = payload.GetProperty("workflow_run");
        var culprit = ResolveWorkflowCulprit(payload);
        if (culprit == null) return Ok("Could not resolve actor.");

        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var name = run.TryGetProperty("name", out var wn) ? wn.GetString() : "Workflow";
        if (IgnoredWorkflows.Contains(name)) return Ok($"Ignored workflow '{name}'.");
        var branch = run.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var url = run.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
        var runId = run.GetProperty("id").GetInt64();
        var startedAt = run.TryGetProperty("run_started_at", out var rsa) ? rsa.GetDateTime() : DateTime.UtcNow;

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
        _db.WorkflowRuns.Add(new WorkflowRun
        {
            RunId = runId,
            GitHubId = gitHubId ?? 0,
            WorkflowName = name,
            Repo = repo,
            Actor = culprit.Login,
            HtmlUrl = url,
            Status = "in_progress",
            StartedAt = startedAt
        });
        await _db.SaveChangesAsync();

        // Notify via SignalR only if user is connected
        var user = await FindConnectedUser(culprit.Login, culprit.Id);
        if (user != null)
        {
            await _hubContext.Clients.Group(user.GitHubId.ToString()).SendAsync("WorkflowRunStarted", new
            {
                runId, workflowName = name, repo, branch, actor = culprit.Login, htmlUrl = url
            });
            _logger.LogInformation("Running workflow {RunId} notified to {Login}", runId, culprit.Login);
        }

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
        if (workflowName != null && IgnoredWorkflows.Contains(workflowName))
            return Ok($"Ignored workflow '{workflowName}'.");
        var workflowUrl = workflowRun.TryGetProperty("html_url", out var wu) ? wu.GetString() : null;

        // Update the latest in_progress row for this runId
        var dbRun = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && w.Status == "in_progress")
            .OrderByDescending(w => w.Id)
            .FirstOrDefaultAsync();
        if (dbRun != null)
        {
            dbRun.Status = conclusion switch
            {
                "success" => "success",
                "failure" => "failure",
                _ => dbRun.Status
            };
        }
        else if (conclusion == "success" || conclusion == "failure")
        {
            var gitHubId = culprit.Id ?? (await FindUserByLogin(culprit.Login))?.GitHubId;
            _db.WorkflowRuns.Add(new WorkflowRun
            {
                RunId = runId,
                GitHubId = gitHubId ?? 0,
                WorkflowName = workflowName,
                Repo = repoFullName,
                Actor = culprit.Login,
                HtmlUrl = workflowUrl,
                Status = conclusion switch { "success" => "success", _ => "failure" },
                StartedAt = DateTime.UtcNow
            });
        }
        await _db.SaveChangesAsync();

        // Notify both the culprit and the target user (if set) via SignalR
        async Task NotifyCompleted(long gitHubId, bool succeeded)
        {
            await _hubContext.Clients.Group(gitHubId.ToString()).SendAsync("WorkflowRunCompleted", new
            {
                runId, succeeded, conclusion,
                workflowName, repo = repoFullName, actor = culprit.Login,
                htmlUrl = workflowUrl
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

            if (dbRun?.TargetGitHubId != null && dbRun.TargetGitHubId != user?.GitHubId)
            {
                await NotifyCompleted(dbRun.TargetGitHubId.Value, true);
                _logger.LogInformation("Workflow success also notified to target user {TargetId}", dbRun.TargetGitHubId);
            }

            return Ok(new { runId, conclusion });
        }

        if (conclusion != "failure")
            return Ok("Ignored: conclusion is not 'failure'.");

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

        if (dbRun?.TargetGitHubId != null && dbRun.TargetGitHubId != user2?.GitHubId)
        {
            await NotifyCompleted(dbRun.TargetGitHubId.Value, false);
            _logger.LogInformation("Punishment also notified to target user {TargetId}", dbRun.TargetGitHubId);
        }

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

        return action switch
        {
            "requested" or "rerequested" => await HandleCheckSuiteRequested(payload),
            "completed" => await HandleCheckSuiteCompleted(payload),
            _ => Ok($"Ignored: check_suite action '{action}'.")
        };
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

        return action switch
        {
            "opened" => await HandlePullRequestOpened(prNumber, title, htmlUrl, repo, baseBranch, headBranch, authorLogin, authorId, draft),
            "ready_for_review" => await HandlePullRequestReadyForReview(prNumber, repo),
            "closed" => await HandlePullRequestClosed(prNumber, title, htmlUrl, repo, baseBranch, headBranch, authorLogin, authorId, pr),
            _ => Ok($"Ignored: pull_request action '{action}'.")
        };
    }

    private async Task<IActionResult> HandlePullRequestOpened(
        int prNumber, string title, string htmlUrl, string repo,
        string baseBranch, string headBranch, string authorLogin, long? authorId,
        bool draft)
    {
        _db.PullRequestEvents.Add(new PullRequestEvent
        {
            PrNumber = prNumber, Title = title, AuthorLogin = authorLogin,
            AuthorGitHubId = authorId, RepoFullName = repo,
            HeadBranch = headBranch, BaseBranch = baseBranch, PrUrl = htmlUrl,
            Status = "open", Draft = draft, OccurredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        _logger.LogInformation("PR #{PrNumber} opened by {Author} (draft={Draft})", prNumber, authorLogin, draft);
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, status = "tracking" });
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
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");
        return Ok(new { prNumber, status });
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
}

internal record CulpritInfo(string Login, long? Id);
