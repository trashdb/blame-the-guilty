using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Domain.Contracts;
using Statefalse.Application;
using Statefalse.Domain.Models;

namespace Statefalse.Application;

/// <summary>
/// GitHub API proxy endpoints: user branches, create PR (with DB sync),
/// PR preview and natural-language interpret.
/// </summary>
public class GitHubApiService
{
    private readonly IAppDbContext _db;
    private readonly IGitHubClient _github;
    private readonly IGitHubTokenResolver _tokens;
    private readonly AiService _ai;
    private readonly ILogger<GitHubApiService> _logger;
    private readonly ISignalRNotifier _notifier;

    public GitHubApiService(
        IAppDbContext db,
        IGitHubClient github,
        IGitHubTokenResolver tokens,
        AiService ai,
        ILogger<GitHubApiService> logger,
        ISignalRNotifier notifier)
    {
        _db = db;
        _github = github;
        _tokens = tokens;
        _ai = ai;
        _logger = logger;
        _notifier = notifier;
    }

    public async Task<ApiResult> GetMyBranchesAsync(long gitHubId, string repo)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No token" });

        var listResp = await _github.GetAsync($"/repos/{repo}/branches?per_page=100", token);
        if (listResp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (listResp.StatusCode is < 200 or >= 300 || listResp.Body is not { } doc)
            return ApiResult.FromGitHubStatus(listResp.StatusCode, new { error = "GitHub API error" });

        var branches = doc.EnumerateArray();
        var username = user?.GitHubUsername ?? "";

        var myBranches = new List<object>();
        var semaphore = new SemaphoreSlim(10);

        await Parallel.ForEachAsync(branches, async (branch, ct) =>
        {
            var branchName = branch.GetProperty("name").GetString() ?? "";

            if (branchName.StartsWith("dependabot/"))
                return;

            await semaphore.WaitAsync(ct);
            try
            {
                var detailResp = await _github.GetAsync($"/repos/{repo}/branches/{branchName}", token, ct);
                if (detailResp.StatusCode is < 200 or >= 300 || detailResp.Body is not { } detailDoc)
                    return;

                var authorLogin = detailDoc
                    .GetProperty("commit")
                    .GetProperty("author")
                    .GetProperty("login")
                    .GetString();

                if (string.Equals(authorLogin, username, StringComparison.OrdinalIgnoreCase))
                {
                    lock (myBranches)
                    {
                        myBranches.Add(new BranchDto(branchName));
                    }
                }
            }
            finally
            {
                semaphore.Release();
            }
        });

        return ApiResult.Ok(myBranches);
    }

    public async Task<ApiResult> CreatePrAsync(long gitHubId, string repo, string head, string baseBranch, string title, string? body, string? subscribers)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No token" });

        _logger.LogInformation("CreatePr: repo={Repo} head={Head} baseBranch={Base} title={Title} gitHubId={Id}",
            repo, head, baseBranch, title, gitHubId);

        var payload = new
        {
            title,
            head,
            @base = baseBranch,
            body = body ?? ""
        };

        var resp = await _github.PostAsync($"/repos/{repo}/pulls", token, payload);
        _logger.LogInformation("GitHub API responded: status={Status} body={Body}",
            resp.StatusCode, resp.Body?.GetRawText());

        if (resp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });

        if (resp.StatusCode is < 200 or >= 300 || resp.Body is not { } doc)
        {
            var msg = resp.Body is { } b && b.TryGetProperty("message", out var m) ? m.GetString() : "Unknown error";

            var detail = msg;
            if (resp.Body is { } b2 && b2.TryGetProperty("errors", out var errors) && errors.ValueKind == JsonValueKind.Array)
            {
                foreach (var e in errors.EnumerateArray())
                {
                    if (e.TryGetProperty("message", out var em))
                    {
                        detail = em.GetString() ?? detail;
                        break;
                    }
                }
            }

            _logger.LogWarning("CreatePr failed for repo={Repo} head={Head}: {Status} {Detail}",
                repo, head, resp.StatusCode, detail);

            if (resp.StatusCode == StatusCodes.Status422UnprocessableEntity &&
                detail?.Contains("already exists", StringComparison.OrdinalIgnoreCase) == true)
            {
                var existingResp = await _github.GetAsync($"/repos/{repo}/pulls?state=open&per_page=100", token);
                if (existingResp.StatusCode is >= 200 and < 300 && existingResp.Body is { } existingDoc
                    && existingDoc.ValueKind == JsonValueKind.Array)
                {
                    foreach (var pr in existingDoc.EnumerateArray())
                    {
                        if (pr.TryGetProperty("head", out var h) &&
                            h.TryGetProperty("ref", out var r) &&
                            r.GetString() == head)
                        {
                            var existingUrl = pr.GetProperty("html_url").GetString() ?? "";
                            var existingNumber = pr.GetProperty("number").GetInt64();
                            return ApiResult.Ok(new { prNumber = existingNumber, url = existingUrl, existing = true });
                        }
                    }
                }
            }

            return ApiResult.FromGitHubStatus(resp.StatusCode, new { error = detail ?? "Unknown error" });
        }

        var prUrl = doc.GetProperty("html_url").GetString() ?? "";
        var prNumber = doc.GetProperty("number").GetInt64();
        var prTitle = doc.TryGetProperty("title", out var t) ? t.GetString() ?? title : title;

        _logger.LogInformation("CreatePr success: pr={PrNumber} url={Url}", prNumber, prUrl);

        // Sync to DB so the PR appears immediately in the active PRs list
        try
        {
            var existing = await _db.PullRequestEvents
                .FirstOrDefaultAsync(e => e.RepoFullName == repo && e.PrNumber == prNumber);
            if (existing == null)
            {
                // Resolve subscriber usernames to GitHubIds
                long[] subscriberIds = [];
                if (!string.IsNullOrWhiteSpace(subscribers))
                {
                    var usernames = subscribers.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    var resolved = await _db.GitHubUsers
                        .Where(u => usernames.Contains(u.GitHubUsername))
                        .Select(u => u.GitHubId)
                        .ToListAsync();
                    if (resolved.Count > 0)
                        subscriberIds = resolved.ToArray();
                }

                var ev = new PullRequestEvent
                {
                    PrNumber = prNumber,
                    Title = prTitle,
                    AuthorLogin = user?.GitHubUsername ?? "",
                    AuthorGitHubId = user?.GitHubId ?? gitHubId,
                    RepoFullName = repo,
                    HeadBranch = head,
                    BaseBranch = baseBranch,
                    PrUrl = prUrl,
                    Status = "open",
                    Draft = false,
                    OccurredAt = DateTime.UtcNow,
                    SubscriberIds = IdListSerializer.Serialize(subscriberIds)
                };
                _db.PullRequestEvents.Add(ev);
                await _db.SaveChangesAsync();
                _logger.LogInformation("CreatePr: inserted PullRequestEvent for pr={PrNumber} subscribers={Subscribers}", prNumber, subscriberIds.Length);
            }
            await _notifier.NotifyPullRequestsUpdatedAsync();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "CreatePr: failed to sync PR event to DB");
        }

        return ApiResult.Ok(new { prNumber, url = prUrl });
    }

    public async Task<ApiResult> PrPreviewAsync(long gitHubId, string repo, string head, string baseBranch, string title, bool useAI)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No token" });

        var preview = await _ai.BuildPreviewAsync(repo, baseBranch, head, title, useAI, token, user?.AccessToken);

        return ApiResult.Ok(new PrPreviewDto(
            preview.Template,
            preview.Commits,
            preview.Summary,
            preview.SuggestedBody,
            preview.SummaryError));
    }

    public async Task<ApiResult> InterpretAsync(InterpretRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Query))
            return ApiResult.BadRequest(new { error = "Query is required" });

        var user = await _tokens.GetUserAsync(request.GitHubId);
        var oauthToken = user?.AccessToken;
        if (string.IsNullOrEmpty(request.ApiKey) && string.IsNullOrEmpty(oauthToken))
            return ApiResult.BadRequest(new { error = "No API key configured and no OAuth token available. Set an API key in Settings or login with GitHub." });

        var result = await _ai.InterpretQueryAsync(request, oauthToken);
        return ApiResult.Ok(result);
    }
}
