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

        var user = await FindConnectedUser(culprit.Login, culprit.Id);
        if (user == null) return Ok($"User '{culprit.Login}' not connected.");

        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var name = run.TryGetProperty("name", out var wn) ? wn.GetString() : "Workflow";
        var branch = run.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var url = run.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
        var runId = run.GetProperty("id").GetInt64();

        await _hubContext.Clients.Group(user.GitHubId.ToString()).SendAsync("WorkflowRunStarted", new
        {
            runId, workflowName = name, repo, branch, actor = culprit.Login, htmlUrl = url
        });

        _logger.LogInformation("Running workflow {RunId} notified to {Login}", runId, culprit.Login);
        return Ok(new { notified = culprit.Login, runId });
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
        var workflowUrl = workflowRun.TryGetProperty("html_url", out var wu) ? wu.GetString() : null;

        // If it was a success → notify completed, else → trigger punishment
        if (conclusion == "success")
        {
            var user = await FindConnectedUser(culprit.Login, culprit.Id);
            if (user == null) return Ok($"User '{culprit.Login}' not connected.");

            await _hubContext.Clients.Group(user.GitHubId.ToString()).SendAsync("WorkflowRunCompleted", new
            {
                runId, succeeded = true, conclusion = "success",
                workflowName, repo = repoFullName, actor = culprit.Login,
                htmlUrl = workflowUrl
            });

            _logger.LogInformation("Workflow success notified to {Login}", culprit.Login);
            return Ok(new { notified = culprit.Login, conclusion });
        }

        if (conclusion != "failure")
            return Ok("Ignored: conclusion is not 'failure'.");

        // Save punishment
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

        if (user2 == null)
        {
            _logger.LogInformation("User '{Login}' not connected.", culprit.Login);
            return Ok($"User '{culprit.Login}' is not currently connected.");
        }

        await _hubContext.Clients.Group(user2.GitHubId.ToString()).SendAsync("WorkflowRunCompleted", new
        {
            runId, succeeded = false, conclusion = "failure",
            workflowName, repo = repoFullName, actor = culprit.Login,
            htmlUrl = workflowUrl
        });

        _logger.LogInformation("Punishment sent to {Login}", culprit.Login);
        return Ok(new { punished = culprit.Login, gitHubId = user2.GitHubId });
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

            if (payload.TryGetProperty("sender", out var sender))
            {
                var id = sender.TryGetProperty("id", out var sid) ? sid.GetInt64() : (long?)null;
                var login = sender.GetProperty("login").GetString()!;
                return new CulpritInfo(login, id);
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
}

internal record CulpritInfo(string Login, long? Id);
