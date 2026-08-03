using System.Globalization;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Domain.Contracts;
using Statefalse.Application;
using Statefalse.Domain.Models;

namespace Statefalse.Application;

/// <summary>
/// Pull requests sync from GitHub: open PRs authored by the user + check-run
/// reconciliation so the DB reflects reality even when webhooks are missed.
/// </summary>
public class PullRequestSyncService
{
    private readonly IAppDbContext _db;
    private readonly IGitHubClient _github;
    private readonly IGitHubTokenResolver _tokens;
    private readonly ILogger<PullRequestSyncService> _logger;

    public PullRequestSyncService(
        IAppDbContext db,
        IGitHubClient github,
        IGitHubTokenResolver tokens,
        ILogger<PullRequestSyncService> logger)
    {
        _db = db;
        _github = github;
        _tokens = tokens;
        _logger = logger;
    }

    public async Task<ApiResult> SyncFromGitHubAsync(long gitHubId)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        _logger.LogInformation("SyncFromGitHub start user={User} hasPat={HasPat} hasOauth={HasOauth}",
            user?.GitHubUsername, user?.UserPatToken != null, user?.AccessToken != null);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No token" });

        var username = user?.GitHubUsername ?? "";
        var synced = 0;

        // Step 1: Find all open PRs authored by the user via search API
        var searchPage = 1;
        var searchResults = new List<(long PrNumber, string RepoFullName, string Title, string HtmlUrl, bool Draft, DateTime CreatedAt)>();

        while (true)
        {
            var searchResp = await _github.GetAsync(
                $"/search/issues?q=type:pr+state:open+author:{username}&per_page=100&page={searchPage}", token);
            if (searchResp.StatusCode == 0 || searchResp.StatusCode is < 200 or >= 300)
            {
                _logger.LogWarning("SyncFromGitHub search returned {Status}", searchResp.StatusCode);
                break;
            }

            var searchDoc = searchResp.Body;
            if (!searchDoc!.Value.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array)
                break;

            var itemList = items.EnumerateArray().ToList();
            if (itemList.Count == 0) break;

            foreach (var item in itemList)
            {
                var repoUrl = item.TryGetProperty("repository_url", out var ru) ? ru.GetString() ?? "" : "";
                // Extract "owner/repo" from "https://api.github.com/repos/owner/repo"
                var repoParts = repoUrl.Replace("https://api.github.com/repos/", "").Trim('/');
                if (string.IsNullOrEmpty(repoParts)) continue;

                var prNumber = item.GetProperty("number").GetInt64();
                var title = item.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
                var htmlUrl = item.TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
                var draft = item.TryGetProperty("draft", out var d) && d.ValueKind == JsonValueKind.True;
                var createdAt = item.TryGetProperty("created_at", out var ca) && DateTime.TryParse(ca.GetString(), null, DateTimeStyles.AdjustToUniversal, out var cd) ? cd : DateTime.UtcNow;

                searchResults.Add((prNumber, repoParts, title, htmlUrl ?? "", draft, createdAt));
            }

            if (itemList.Count < 100) break;
            searchPage++;
        }

        // Step 2: For each unique repo, fetch full PR details via REST API
        var repos = searchResults.Select(r => r.RepoFullName).Distinct().ToList();
        _logger.LogInformation("SyncFromGitHub found {Count} PRs across {Repos} repos for user {User}", searchResults.Count, repos.Count, username);
        foreach (var repo in repos)
        {
            var repoPrs = searchResults.Where(r => r.RepoFullName == repo).ToList();
            var repoResp = await _github.GetAsync($"/repos/{repo}/pulls?state=open&per_page=100", token);

            if (repoResp.StatusCode == 0 || repoResp.StatusCode is < 200 or >= 300)
            {
                _logger.LogWarning("SyncFromGitHub {Repo} returned {Status}", repo, repoResp.StatusCode);
                continue;
            }

            var repoDoc = repoResp.Body;
            if (repoDoc!.Value.ValueKind != JsonValueKind.Array)
            {
                _logger.LogWarning("SyncFromGitHub {Repo} response is not array", repo);
                continue;
            }

            foreach (var prDetail in repoDoc.Value.EnumerateArray())
            {
                var prNumber = prDetail.GetProperty("number").GetInt64();
                var matched = searchResults.FirstOrDefault(r => r.PrNumber == prNumber && r.RepoFullName == repo);
                if (matched.PrNumber == 0) continue;

                var title = matched.Title;
                var authorLogin = prDetail.TryGetProperty("user", out var u) && u.TryGetProperty("login", out var l) ? l.GetString() ?? "" : "";
                var authorId = prDetail.TryGetProperty("user", out var u2) && u2.TryGetProperty("id", out var id) ? id.GetInt64() : (long?)null;
                var headBranch = prDetail.TryGetProperty("head", out var h) && h.TryGetProperty("ref", out var r) ? r.GetString() : null;
                var baseBranch = prDetail.TryGetProperty("base", out var b) && b.TryGetProperty("ref", out var br) ? br.GetString() : null;
                var htmlUrl = matched.HtmlUrl;
                var draft = matched.Draft;
                var createdAt = matched.CreatedAt;

                var existing = await _db.PullRequestEvents
                    .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo)
                    .OrderByDescending(e => e.Id)
                    .FirstOrDefaultAsync();

                if (existing != null)
                {
                    existing.Title = title;
                    existing.AuthorLogin = authorLogin;
                    existing.AuthorGitHubId = authorId;
                    existing.HeadBranch = headBranch;
                    existing.BaseBranch = baseBranch;
                    existing.PrUrl = htmlUrl;
                    existing.Draft = draft;
                    existing.Status = "open";
                }
                else
                {
                    _db.PullRequestEvents.Add(new PullRequestEvent
                    {
                        PrNumber = prNumber,
                        Title = title,
                        AuthorLogin = authorLogin,
                        AuthorGitHubId = authorId,
                        RepoFullName = repo,
                        HeadBranch = headBranch,
                        BaseBranch = baseBranch,
                        PrUrl = htmlUrl,
                        Status = "open",
                        Draft = draft,
                        OccurredAt = createdAt
                    });
                }
                synced++;
            }
        }

        await _db.SaveChangesAsync();
        return ApiResult.Ok(new SyncResult(synced));
    }

    /// <summary>
    /// Reconciles WorkflowRun rows from the check-runs API for a (repo, sha),
    /// creating missing runs and updating statuses when a webhook was missed.
    /// </summary>
    public async Task SyncCheckRunsForCommit(string repo, string sha, string? token)
    {
        if (string.IsNullOrEmpty(token)) return;
        try
        {
            var response = await _github.GetAsync($"/repos/{repo}/commits/{sha}/check-runs?per_page=100", token);
            if (response.StatusCode is < 200 or >= 300 || response.Body is not { } doc)
                return;

            var checkRuns = doc.GetProperty("check_runs").EnumerateArray();

            foreach (var cr in checkRuns)
            {
                var name = cr.GetProperty("name").GetString();
                var status = cr.GetProperty("status").GetString();
                var conclusion = cr.TryGetProperty("conclusion", out var c) ? c.GetString() : null;
                var runId = cr.GetProperty("id").GetInt64();

                if (string.IsNullOrEmpty(name)) continue;

                var mappedStatus = CheckRunStatusMapper.Map(status, conclusion);

                var existing = await _db.WorkflowRuns
                    .Where(w => w.RunId == runId && w.Repo == repo)
                    .FirstOrDefaultAsync();

                if (existing != null)
                {
                    // Update status if changed
                    if (existing.Status != mappedStatus || existing.HeadSha != sha)
                    {
                        existing.HeadSha ??= sha;
                        existing.Status = mappedStatus;
                    }
                }
                else
                {
                    // Run not in DB — create it (webhook was missed)
                    var actor = cr.TryGetProperty("app", out var app)
                        && app.TryGetProperty("slug", out var slug)
                        ? slug.GetString() ?? "unknown" : "unknown";
                    var workflowName = cr.TryGetProperty("name", out var wn) ? wn.GetString() : name;

                    _db.WorkflowRuns.Add(new WorkflowRun
                    {
                        RunId = runId,
                        WorkflowName = workflowName,
                        Repo = repo,
                        Actor = actor,
                        HeadBranch = null,
                        HeadSha = sha,
                        Status = mappedStatus,
                        StartedAt = DateTime.UtcNow,
                        HtmlUrl = null
                    });
                }
            }

            await _db.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SyncCheckRuns failed for {Repo} @ {Sha}", repo, sha);
        }
    }
}
