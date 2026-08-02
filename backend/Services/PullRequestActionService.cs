using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;

namespace Statefalse.Api.Services;

/// <summary>
/// Pull request write actions: merge, draft toggle and update-branch (all proxy
/// to the GitHub API, then keep the local DB + SignalR in sync).
/// </summary>
public class PullRequestActionService
{
    private readonly AppDbContext _db;
    private readonly IGitHubClient _github;
    private readonly IGitHubTokenResolver _tokens;
    private readonly PullRequestQueries _prs;
    private readonly SignalRNotifier _notifier;
    private readonly ILogger<PullRequestActionService> _logger;

    public PullRequestActionService(
        AppDbContext db,
        IGitHubClient github,
        IGitHubTokenResolver tokens,
        PullRequestQueries prs,
        SignalRNotifier notifier,
        ILogger<PullRequestActionService> logger)
    {
        _db = db;
        _github = github;
        _tokens = tokens;
        _prs = prs;
        _notifier = notifier;
        _logger = logger;
    }

    public async Task<ApiResult> MergeAsync(long prNumber, string repo, long gitHubId, string method)
    {
        var token = await _tokens.ResolveAsync(gitHubId);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token found" });

        // Fetch PR to get head SHA for the merge request
        var prResponse = await _github.GetAsync($"/repos/{repo}/pulls/{prNumber}", token);
        if (prResponse.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (prResponse.StatusCode is < 200 or >= 300)
            return ApiResult.FromGitHubStatus(prResponse.StatusCode, new { error = "Failed to fetch PR details from GitHub" });

        var prData = prResponse.Body!.Value;
        var headSha = prData.GetProperty("head").GetProperty("sha").GetString();

        var mergeBody = new
        {
            merge_method = method,
            sha = headSha,
            commit_title = $"Merge PR #{prNumber} — {prData.GetProperty("title").GetString()}"
        };

        var mergeResponse = await _github.PutAsync($"/repos/{repo}/pulls/{prNumber}/merge", token, mergeBody);
        if (mergeResponse.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub merge API unreachable" });

        var mergeData = mergeResponse.Body;
        if (mergeResponse.StatusCode is < 200 or >= 300)
        {
            var msg = mergeData is { } md && md.TryGetProperty("message", out var m) ? m.GetString() : "Unknown error";
            return ApiResult.FromGitHubStatus(mergeResponse.StatusCode, new { error = msg, details = mergeData });
        }

        // Mark PR as merged in DB
        var prEvent = await _prs.FindLatestOpenAsync(prNumber, repo);
        if (prEvent != null)
        {
            prEvent.Status = "merged";
            await _db.SaveChangesAsync();
        }

        await _notifier.NotifyPullRequestsUpdatedAsync();

        return ApiResult.Ok(new
        {
            merged = mergeData is { } m2 && m2.TryGetProperty("merged", out var merged) && merged.GetBoolean(),
            sha = mergeData is { } m3 && m3.TryGetProperty("sha", out var sha) ? sha.GetString() : null,
            message = mergeData is { } m4 && m4.TryGetProperty("message", out var msg2) ? msg2.GetString() : null
        });
    }

    public async Task<ApiResult> SetDraftAsync(long prNumber, string repo, long gitHubId, bool draft)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token found" });

        // Step 1: Get PR node_id via REST API
        string nodeId;
        {
            var getResp = await _github.GetAsync($"/repos/{repo}/pulls/{prNumber}", token);
            if (getResp.StatusCode == 0)
                return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
            if (getResp.StatusCode is < 200 or >= 300 || getResp.Body is not { } getDoc)
                return ApiResult.FromGitHubStatus(getResp.StatusCode, new { error = "Failed to fetch PR", detail = getResp.Body });
            nodeId = getDoc.GetProperty("node_id").GetString() ?? "";
        }

        // Step 2: Use GraphQL mutation to change draft status
        // REST API silently ignores the "draft" field — only GraphQL mutations work.
        var mutationName = draft ? "convertPullRequestToDraft" : "markPullRequestReadyForReview";
        var gql = $@"mutation {{ {mutationName}(input: {{ pullRequestId: ""{nodeId}"" }}) {{ pullRequest {{ id isDraft }} }} }}";

        var gqlResp = await _github.GraphQlAsync(gql, token);
        var gqlJson = gqlResp.Body;

        if (gqlResp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub GraphQL unreachable" });

        if (gqlResp.StatusCode is < 200 or >= 300 || gqlJson is not { } gqlDoc)
        {
            var msg = "";
            try { msg = gqlJson is { } d && d.TryGetProperty("message", out var m) ? m.GetString() ?? "" : ""; } catch { }
            return ApiResult.FromGitHubStatus(gqlResp.StatusCode, new { error = msg, detail = gqlJson });
        }

        // Check for GraphQL-level errors
        if (gqlDoc.TryGetProperty("errors", out var errors) && errors.GetArrayLength() > 0)
        {
            var firstErr = errors[0].TryGetProperty("message", out var em) ? em.GetString() ?? "" : "Unknown GraphQL error";
            return ApiResult.Error(StatusCodes.Status422UnprocessableEntity, new { error = firstErr, detail = gqlDoc.GetRawText() });
        }

        // Update DB
        var prEvent = await _prs.FindLatestAsync(prNumber, repo);
        if (prEvent != null)
        {
            prEvent.Draft = draft;
            await _db.SaveChangesAsync();
        }

        await _notifier.NotifyPullRequestsUpdatedAsync();

        return ApiResult.Ok(new { success = true, draft });
    }

    public async Task<ApiResult> UpdateBranchAsync(long prNumber, string repo, long gitHubId)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token found" });

        var response = await _github.PutAsync($"/repos/{repo}/pulls/{prNumber}/update-branch", token, new { });
        var data = response.Body;

        if (response.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (response.StatusCode is < 200 or >= 300)
        {
            var msg = data is { } d && d.TryGetProperty("message", out var m) ? m.GetString() : "Unknown error";
            return ApiResult.FromGitHubStatus(response.StatusCode, new { error = msg });
        }

        // Mark old workflow runs for this PR's branch as superseded so ciStatus
        // does not stay "failed" while waiting for new workflow webhooks
        var prEvent = await _prs.FindLatestOpenAsync(prNumber, repo);
        if (prEvent?.HeadBranch != null)
        {
            var stale = await _db.WorkflowRuns
                .Where(w => w.Repo == repo && w.HeadBranch == prEvent.HeadBranch
                    && (w.Status == "failure" || w.Status == "in_progress"))
                .ToListAsync();
            if (stale.Count > 0)
            {
                foreach (var s in stale) s.Status = "superseded";
                await _db.SaveChangesAsync();
            }
        }

        // Resync PRs after update
        await _notifier.NotifyPullRequestsUpdatedAsync();

        return ApiResult.Ok(new
        {
            message = data is { } d2 && d2.TryGetProperty("message", out var msg2) ? msg2.GetString() : "Branch updated"
        });
    }
}
