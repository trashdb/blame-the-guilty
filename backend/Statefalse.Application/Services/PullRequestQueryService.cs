using System.Globalization;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Domain.Contracts;
using Statefalse.Application;

namespace Statefalse.Application;

/// <summary>
/// Pull request read paths: active list (with self-healing + ciStatus), detail
/// and commits/files/checks proxies.
/// </summary>
public class PullRequestQueryService
{
    private readonly IAppDbContext _db;
    private readonly IGitHubClient _github;
    private readonly IGitHubTokenResolver _tokens;
    private readonly PullRequestSyncService _sync;
    private readonly ILogger<PullRequestQueryService> _logger;

    public PullRequestQueryService(
        IAppDbContext db,
        IGitHubClient github,
        IGitHubTokenResolver tokens,
        PullRequestSyncService sync,
        ILogger<PullRequestQueryService> logger)
    {
        _db = db;
        _github = github;
        _tokens = tokens;
        _sync = sync;
        _logger = logger;
    }

    // ─────────────────────────── Active PR list ───────────────────────────

    public async Task<ApiResult> GetActiveAsync(long gitHubId, int page, int pageSize)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No token" });

        var prs = await _db.PullRequestEvents
            .Where(e => ((e.Status == "open" || e.Status == "in_progress") || (e.Status == "merged" && e.OccurredAt >= DateTime.UtcNow.AddHours(-24)))
                && (e.AuthorGitHubId == gitHubId || (e.SubscriberIds != null && e.SubscriberIds.Contains(gitHubId.ToString()))))
            .OrderByDescending(e => e.OccurredAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(e => new
            {
                e.PrNumber,
                e.Title,
                e.RepoFullName,
                e.HeadBranch,
                e.BaseBranch,
                e.PrUrl,
                e.Status,
                e.Conclusion,
                e.Draft,
                e.ReviewApproved,
                e.LastCommentBy,
                e.LastCommentBody,
                e.LastCommentAt,
                e.LastCommentUrl,
                e.LastReviewFilePath,
                e.LastReviewLine,
                e.SubscriberIds,
                e.AuthorGitHubId
            })
            .ToListAsync();

        var repos = prs.Select(p => p.RepoFullName).Distinct().ToList();

        // Fetch head SHA, draft, mergeable, and real open/closed state for every PR from GitHub API
        var prData = new Dictionary<long, (bool? Draft, string? Mergeable, string? HeadSha)>();
        var statusOverrides = new Dictionary<long, string>();
        foreach (var pr in prs)
        {
            var (draft, mergeable, headSha, prState, merged, mergedAt) = await FetchPullRequestData(pr.PrNumber, pr.RepoFullName, token);
            prData[pr.PrNumber] = (draft, mergeable, headSha);

            // Self-heal: if GitHub says the PR is closed/merged but our DB still
            // has it "open" (missed webhook), correct the status so it never shows
            // as "ready" after being merged.
            if (prState == "closed" && pr.Status == "open")
            {
                var healed = merged ? "merged" : "closed";
                statusOverrides[pr.PrNumber] = healed;
                var entity = await _db.PullRequestEvents
                    .Where(e => e.PrNumber == pr.PrNumber && e.RepoFullName == pr.RepoFullName && e.Status == "open")
                    .OrderByDescending(e => e.Id)
                    .FirstOrDefaultAsync();
                if (entity != null)
                {
                    entity.Status = healed;
                    // Use the real merge time so the 24h "recently merged" window is
                    // accurate — NOT now (which would resurface old merged PRs).
                    if (merged && mergedAt.HasValue) entity.OccurredAt = mergedAt.Value;
                    await _db.SaveChangesAsync();
                }
            }
            // Correct OccurredAt for already-merged PRs whose timestamp is wrong
            // (e.g. previously self-healed with now() instead of the real merge time).
            // Update ALL merged rows for this PR to avoid stale duplicates lingering.
            else if (pr.Status == "merged" && merged && mergedAt.HasValue)
            {
                var mergedRows = await _db.PullRequestEvents
                    .Where(e => e.PrNumber == pr.PrNumber && e.RepoFullName == pr.RepoFullName && e.Status == "merged")
                    .ToListAsync();
                bool changed = false;
                foreach (var row in mergedRows)
                {
                    if (Math.Abs((row.OccurredAt - mergedAt.Value).TotalMinutes) > 2)
                    {
                        row.OccurredAt = mergedAt.Value;
                        changed = true;
                    }
                }
                if (changed) await _db.SaveChangesAsync();
            }
        }

        // Sync workflow run states from GitHub check-runs for each unique (repo, headSha)
        var shaRepoSet = new HashSet<(string Repo, string Sha)>();
        foreach (var pr in prs)
        {
            if (prData.TryGetValue(pr.PrNumber, out var data) && data.HeadSha != null)
                shaRepoSet.Add((pr.RepoFullName, data.HeadSha));
        }

        foreach (var (repo, sha) in shaRepoSet)
        {
            await _sync.SyncCheckRunsForCommit(repo, sha, token);
        }

        // Sync review approval state from GitHub API. The webhook may miss
        // approvals (e.g. if a "commented" review was submitted after an approval
        // and the old code reset the flag). This ensures the DB stays in sync.
        var reviewOverrides = new Dictionary<long, bool>();
        foreach (var pr in prs.Where(p => p.Status == "open" && !statusOverrides.ContainsKey(p.PrNumber)))
        {
            var approved = await FetchReviewApproval(pr.PrNumber, pr.RepoFullName, token);
            if (approved != null)
            {
                reviewOverrides[pr.PrNumber] = approved.Value;
                var entity = await _db.PullRequestEvents
                    .Where(e => e.PrNumber == pr.PrNumber && e.RepoFullName == pr.RepoFullName && e.Status == "open")
                    .OrderByDescending(e => e.Id)
                    .FirstOrDefaultAsync();
                if (entity != null && entity.ReviewApproved != approved.Value)
                {
                    entity.ReviewApproved = approved.Value;
                    await _db.SaveChangesAsync();
                }
            }
        }

        // Re-fetch all workflow runs after sync
        var allRuns = new List<(string Repo, string? HeadSha, string? WorkflowName, int Id, string Status)>();
        if (repos.Count != 0)
        {
            var raw = await _db.WorkflowRuns
                .Where(w => w.HeadSha != null && repos.Contains(w.Repo))
                .Select(w => new { w.Repo, w.HeadSha, w.WorkflowName, w.Id, w.Status })
                .ToListAsync();
            allRuns = raw.Select(r => (r.Repo, r.HeadSha, r.WorkflowName, r.Id, r.Status)).ToList();
        }

        var results = new List<PullRequestDto>();
        foreach (var pr in prs)
        {
            var (_, mergeable, headSha) = prData.GetValueOrDefault(pr.PrNumber);
            var effectiveStatus = statusOverrides.GetValueOrDefault(pr.PrNumber, pr.Status);

            var prRuns = headSha != null
                ? allRuns
                    .Where(r => r.Repo == pr.RepoFullName && r.HeadSha == headSha)
                    .Select(r => (r.Id, r.WorkflowName, r.Status))
                    .ToList()
                : [];
            var ciStatus = CiStatusCalculator.Calculate(
                headSha,
                isOpen: effectiveStatus == "open",
                reviewApproved: reviewOverrides.GetValueOrDefault(pr.PrNumber, pr.ReviewApproved),
                prRuns);

            // Determine conclusion: prefer workflow run status over stale CheckSuiteEvent
            string? conclusion = pr.Conclusion;
            if (headSha != null)
            {
                // First try: latest CheckSuiteEvent
                var latestCheck = await _db.CheckSuiteEvents
                    .Where(c => c.HeadSha == headSha && c.RepoFullName == pr.RepoFullName)
                    .OrderByDescending(c => c.Id)
                    .FirstOrDefaultAsync();
                if (latestCheck != null)
                    conclusion = latestCheck.Conclusion;

                // Override with latest workflow run status if more recent
                var latestRun = allRuns
                    .Where(r => r.Repo == pr.RepoFullName && r.HeadSha == headSha
                        && r.Status != "superseded" && r.Status != "in_progress")
                    .OrderByDescending(r => r.Id)
                    .FirstOrDefault();
                if (latestRun.Status == "success")
                    conclusion = "success";
                else if (latestRun.Status == "failure")
                    conclusion = "failure";
                else if (latestRun.Status == "cancelled")
                    conclusion = "cancelled";
            }

            var finalReviewApproved = reviewOverrides.GetValueOrDefault(pr.PrNumber, pr.ReviewApproved);
            var subscriberIds = IdListSerializer.Deserialize(pr.SubscriberIds);

            results.Add(new PullRequestDto(
                pr.PrNumber,
                pr.Title,
                pr.RepoFullName,
                pr.HeadBranch,
                pr.BaseBranch,
                pr.PrUrl,
                effectiveStatus,
                conclusion,
                pr.Draft,
                mergeable,
                ciStatus,
                finalReviewApproved,
                pr.LastCommentBy,
                pr.LastCommentBody,
                pr.LastCommentAt,
                pr.LastCommentUrl,
                pr.LastReviewFilePath,
                pr.LastReviewLine,
                subscriberIds.Contains(gitHubId),
                subscriberIds,
                pr.AuthorGitHubId));
        }

        return ApiResult.Ok(results);
    }

    // ─────────────────────────── PR detail ───────────────────────────

    public async Task<ApiResult> GetDetailAsync(long prNumber, string repo, long gitHubId)
    {
        var token = await _tokens.ResolveAsync(gitHubId);

        var prEvent = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo)
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        int? behindBy = null, aheadBy = null;
        string? mergeableState = null;

        try
        {
            var response = await _github.GetAsync($"/repos/{repo}/pulls/{prNumber}", token);
            if (response.StatusCode is >= 200 and < 300 && response.Body is { } body)
            {
                if (body.TryGetProperty("mergeable_state", out var ms))
                    mergeableState = ms.GetString();

                var headSha = body.GetProperty("head").GetProperty("sha").GetString();
                var baseRef = body.GetProperty("base").GetProperty("ref").GetString();

                if (headSha != null && baseRef != null)
                {
                    var compareResp = await _github.GetAsync($"/repos/{repo}/compare/{baseRef}...{headSha}", token);
                    if (compareResp.StatusCode is >= 200 and < 300 && compareResp.Body is { } compareData)
                    {
                        if (compareData.TryGetProperty("behind_by", out var bb)) behindBy = bb.GetInt32();
                        if (compareData.TryGetProperty("ahead_by", out var ab)) aheadBy = ab.GetInt32();
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "GetDetail failed for PR {PrNumber} in {Repo}", prNumber, repo);
        }

        return ApiResult.Ok(new PullRequestDetailDto(
            prNumber,
            repo,
            mergeableState,
            behindBy,
            aheadBy,
            prEvent?.Title,
            prEvent?.HeadBranch,
            prEvent?.BaseBranch,
            prEvent?.Status,
            prEvent?.Draft ?? false,
            prEvent?.LastCommentBy,
            prEvent?.LastCommentBody,
            prEvent?.LastCommentAt,
            prEvent?.LastCommentUrl,
            prEvent?.LastReviewFilePath,
            prEvent?.LastReviewLine));
    }

    // ─────────────────────────── Commits / Files / Checks ───────────────────────────

    public async Task<ApiResult> GetCommitsAsync(long prNumber, string repo, long gitHubId)
    {
        var token = await _tokens.ResolveAsync(gitHubId);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token" });

        var resp = await _github.GetAsync($"/repos/{repo}/pulls/{prNumber}/commits?per_page=30", token);
        if (resp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (resp.StatusCode is < 200 or >= 300 || resp.Body is not { } body)
            return ApiResult.FromGitHubStatus(resp.StatusCode, new { error = "Failed to fetch commits", detail = resp.Body });

        var commits = body.EnumerateArray().Select(c => new CommitDto(
            c.GetProperty("sha").GetString(),
            c.GetProperty("commit").GetProperty("message").GetString(),
            c.GetProperty("commit").GetProperty("author").GetProperty("name").GetString(),
            c.TryGetProperty("author", out var a) && a.ValueKind == JsonValueKind.Object
                ? (a.TryGetProperty("login", out var l) ? l.GetString() : null) : null,
            c.GetProperty("commit").GetProperty("author").GetProperty("date").GetString(),
            c.TryGetProperty("html_url", out var hu) ? hu.GetString() : null)).ToList();

        return ApiResult.Ok(commits);
    }

    public async Task<ApiResult> GetFilesAsync(long prNumber, string repo, long gitHubId)
    {
        var token = await _tokens.ResolveAsync(gitHubId);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token" });

        var resp = await _github.GetAsync($"/repos/{repo}/pulls/{prNumber}/files?per_page=30", token);
        if (resp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (resp.StatusCode is < 200 or >= 300 || resp.Body is not { } body)
            return ApiResult.FromGitHubStatus(resp.StatusCode, new { error = "Failed to fetch files", detail = resp.Body });

        var files = body.EnumerateArray().Select(f => new PrFileDto(
            f.GetProperty("filename").GetString(),
            f.GetProperty("status").GetString(),
            f.GetProperty("additions").GetInt32(),
            f.GetProperty("deletions").GetInt32())).ToList();

        return ApiResult.Ok(files);
    }

    public async Task<ApiResult> GetChecksAsync(long prNumber, string repo, long gitHubId)
    {
        var token = await _tokens.ResolveAsync(gitHubId);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token" });

        // First get PR to get head SHA
        var prResp = await _github.GetAsync($"/repos/{repo}/pulls/{prNumber}", token);
        if (prResp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (prResp.StatusCode is < 200 or >= 300 || prResp.Body is not { } prDoc)
            return ApiResult.FromGitHubStatus(prResp.StatusCode, new { error = "Failed to fetch PR", detail = prResp.Body });

        var headSha = prDoc.GetProperty("head").GetProperty("sha").GetString();
        if (string.IsNullOrEmpty(headSha))
            return ApiResult.Ok(Array.Empty<CheckRunDto>());

        // Now fetch check runs for that SHA
        var crResp = await _github.GetAsync($"/repos/{repo}/commits/{headSha}/check-runs?per_page=100", token);
        if (crResp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (crResp.StatusCode is < 200 or >= 300 || crResp.Body is not { } crDoc)
            return ApiResult.FromGitHubStatus(crResp.StatusCode, new { error = "Failed to fetch check runs", detail = crResp.Body });

        if (!crDoc.TryGetProperty("check_runs", out var checkRunsProp))
            return ApiResult.Ok(Array.Empty<CheckRunDto>());

        var checks = checkRunsProp.EnumerateArray().Select(cr => new CheckRunDto(
            cr.GetProperty("name").GetString(),
            cr.GetProperty("status").GetString(),
            cr.TryGetProperty("conclusion", out var conc) ? conc.GetString() : null,
            cr.TryGetProperty("started_at", out var sa) ? sa.GetString() : null,
            cr.TryGetProperty("completed_at", out var ca) ? ca.GetString() : null,
            cr.TryGetProperty("html_url", out var hu) ? hu.GetString() : null)).ToList();

        return ApiResult.Ok(checks);
    }

    // ─────────────────────────── Private helpers ───────────────────────────

    private async Task<(bool? draft, string? mergeableState, string? headSha, string? state, bool merged, DateTime? mergedAt)> FetchPullRequestData(long prNumber, string repoFullName, string? token)
    {
        try
        {
            var response = await _github.GetAsync($"/repos/{repoFullName}/pulls/{prNumber}", token);
            if (response.StatusCode is < 200 or >= 300 || response.Body is not { } data)
                return (null, null, null, null, false, null);

            bool? draft = null;
            if (data.TryGetProperty("draft", out var draftProp))
                draft = draftProp.GetBoolean();

            string? mergeableState = null;
            if (data.TryGetProperty("mergeable_state", out var state))
                mergeableState = state.GetString();

            string? headSha = null;
            if (data.TryGetProperty("head", out var head) && head.TryGetProperty("sha", out var sha))
                headSha = sha.GetString();

            // Real open/closed state + whether it was merged — used to self-heal
            // the DB when a close/merge webhook was missed (e.g. tunnel was down).
            string? prState = data.TryGetProperty("state", out var st) ? st.GetString() : null;
            bool merged = data.TryGetProperty("merged", out var mg) && mg.ValueKind == JsonValueKind.True;

            // Real merge timestamp so the "recently merged" 24h window is accurate
            // even when we self-heal a PR that was merged days ago.
            DateTime? mergedAt = null;
            if (data.TryGetProperty("merged_at", out var ma) && ma.ValueKind == JsonValueKind.String
                && DateTime.TryParse(ma.GetString(), null, DateTimeStyles.AdjustToUniversal, out var parsed))
                mergedAt = parsed;

            return (draft, mergeableState, headSha, prState, merged, mergedAt);
        }
        catch
        {
            return (null, null, null, null, false, null);
        }
    }

    /// <summary>
    /// Check the GitHub reviews API to see if any review is "APPROVED".
    /// Returns true if at least one approved review exists, false if all are
    /// non-approved, or null if the API call failed.
    /// </summary>
    private async Task<bool?> FetchReviewApproval(long prNumber, string repoFullName, string? token)
    {
        if (string.IsNullOrEmpty(token)) return null;
        try
        {
            var response = await _github.GetAsync($"/repos/{repoFullName}/pulls/{prNumber}/reviews?per_page=100", token);
            if (response.StatusCode is < 200 or >= 300 || response.Body is not { } doc)
                return null;

            // A PR is approved if any review has state "APPROVED" and
            // no later review has "CHANGES_REQUESTED" (GitHub uses latest per reviewer).
            var reviews = doc.EnumerateArray().ToList();
            // Build per-reviewer latest state (GitHub already returns chronologically)
            var latestByReviewer = new Dictionary<string, string>();
            foreach (var review in reviews)
            {
                var state = review.GetProperty("state").GetString() ?? "";
                var reviewer = review.GetProperty("user").GetProperty("login").GetString() ?? "";
                if (state is "APPROVED" or "CHANGES_REQUESTED" or "DISMISSED")
                    latestByReviewer[reviewer] = state;
            }
            return latestByReviewer.Values.Any(v => v == "APPROVED")
                && !latestByReviewer.Values.Any(v => v == "CHANGES_REQUESTED");
        }
        catch
        {
            return null;
        }
    }
}
