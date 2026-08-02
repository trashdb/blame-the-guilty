using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Contracts;
using Statefalse.Api.Data;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// check_suite webhook handler: notifies PR authors when checks start, records
/// completed check suites and refreshes the active PR list.
/// </summary>
public class CheckSuiteWebhookHandler : IWebhookHandler
{
    private readonly AppDbContext _db;
    private readonly GitHubTokenResolver _tokens;
    private readonly SignalRNotifier _notifier;
    private readonly ILogger<CheckSuiteWebhookHandler> _logger;

    public CheckSuiteWebhookHandler(
        AppDbContext db,
        GitHubTokenResolver tokens,
        SignalRNotifier notifier,
        ILogger<CheckSuiteWebhookHandler> logger)
    {
        _db = db;
        _tokens = tokens;
        _notifier = notifier;
        _logger = logger;
    }

    public string EventType => "check_suite";

    public async Task<ApiResult> HandleAsync(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var repo = TryGetRepo(payload);

        if (action is "requested" or "rerequested") return await HandleRequested(payload);
        if (action == "completed") return await HandleCompleted(payload);

        WebhookLog.Log("check_suite", action, repo, null, "ignored", $"Unsupported action '{action}'");
        return ApiResult.Ok($"Ignored: check_suite action '{action}'.");
    }

    private async Task<ApiResult> HandleRequested(JsonElement payload)
    {
        var checkSuite = payload.GetProperty("check_suite");
        var (authorLogin, authorId, prNumber) = ResolveAuthor(payload);

        if (authorLogin == null)
        {
            _logger.LogWarning("Could not determine PR author for check_suite requested.");
            return ApiResult.Ok("Could not resolve author.");
        }

        var user = await _tokens.FindConnectedUserAsync(authorLogin, authorId);
        if (user == null) return ApiResult.Ok($"User '{authorLogin}' not connected.");

        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var branch = checkSuite.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var appName = checkSuite.TryGetProperty("app", out var app) &&
                      app.TryGetProperty("name", out var an)
            ? an.GetString() : "Checks";

        await _notifier.NotifyUserAsync(user.GitHubId, "CheckSuiteStarted", new CheckSuiteStartedPayload(
            CheckSuiteId: checkSuite.GetProperty("id").GetInt64(),
            AppName: appName,
            Repo: repo,
            Branch: branch,
            PrNumber: prNumber,
            Author: authorLogin));

        _logger.LogInformation("Check suite started notified to {Login}", authorLogin);
        return ApiResult.Ok(new { notified = authorLogin });
    }

    private async Task<ApiResult> HandleCompleted(JsonElement payload)
    {
        var checkSuite = payload.GetProperty("check_suite");
        var conclusion = checkSuite.GetProperty("conclusion").GetString();

        if (conclusion != "success" && conclusion != "failure")
            return ApiResult.Ok($"Ignored: conclusion is '{conclusion}'.");

        var repoFullName = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var checkSuiteId = checkSuite.GetProperty("id").GetInt64();
        var headBranch = checkSuite.TryGetProperty("head_branch", out var hb) ? hb.GetString() : null;
        var headSha = checkSuite.TryGetProperty("head_sha", out var hs) ? hs.GetString() : null;

        var (authorLogin, authorId, prNumber) = ResolveAuthor(payload);

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

        var user = await _tokens.FindConnectedUserAsync(authorLogin, authorId);
        checkEvent.WasNotified = user != null;
        _db.CheckSuiteEvents.Add(checkEvent);
        await _db.SaveChangesAsync();

        // Always notify all clients so Active PRs refresh ciStatus, even if the
        // PR author isn't currently connected (other team members may be watching).
        await _notifier.NotifyPullRequestsUpdatedAsync();

        if (user == null)
        {
            _logger.LogInformation("User '{Login}' not connected.", authorLogin);
            return ApiResult.Ok($"User '{authorLogin}' is not currently connected.");
        }

        var succeeded = conclusion == "success";
        await _notifier.NotifyUserAsync(user.GitHubId, "CheckSuiteCompleted", new CheckSuiteCompletedPayload(
            CheckSuiteId: checkSuiteId,
            Conclusion: conclusion,
            Succeeded: succeeded,
            PrNumber: prNumber,
            Repo: repoFullName,
            HeadBranch: headBranch,
            PrAuthor: authorLogin));

        _logger.LogInformation("Check suite notification sent to {Login} ({Conclusion})", authorLogin, conclusion);
        return ApiResult.Ok(new { notified = authorLogin, conclusion });
    }

    private (string? login, long? id, int? prNumber) ResolveAuthor(JsonElement payload)
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

    private static string? TryGetRepo(JsonElement payload)
    {
        if (payload.TryGetProperty("repository", out var repo) &&
            repo.TryGetProperty("full_name", out var name))
            return name.GetString();
        return null;
    }
}
