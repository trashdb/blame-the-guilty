using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;
using Statefalse.Api.Hubs;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// Domain logic for pull requests: GitHub sync, active list computation
/// (ciStatus + self-healing), detail, merge, draft toggle, update-branch,
/// commits/files/checks and subscriber management.
/// </summary>
public class PullRequestService
{
    private readonly AppDbContext _db;
    private readonly GitHubClient _github;
    private readonly GitHubTokenResolver _tokens;
    private readonly IHubContext<PunishmentHub> _hub;
    private readonly ILogger<PullRequestService> _logger;

    public PullRequestService(
        AppDbContext db,
        GitHubClient github,
        GitHubTokenResolver tokens,
        IHubContext<PunishmentHub> hub,
        ILogger<PullRequestService> logger)
    {
        _db = db;
        _github = github;
        _tokens = tokens;
        _hub = hub;
        _logger = logger;
    }

    // ─────────────────────────── Sync from GitHub ───────────────────────────

    public async Task<ApiResult> SyncFromGitHubAsync(long gitHubId)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        Console.WriteLine($"[SyncFromGitHub] user={user?.GitHubUsername} hasPat={user?.UserPatToken != null} hasOauth={user?.AccessToken != null} tokenPrefix={token?[..Math.Min(10, token?.Length ?? 0)]}");
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
                Console.WriteLine($"[SyncFromGitHub] Search returned {searchResp.StatusCode}");
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
                var createdAt = item.TryGetProperty("created_at", out var ca) && DateTime.TryParse(ca.GetString(), null, System.Globalization.DateTimeStyles.AdjustToUniversal, out var cd) ? cd : DateTime.UtcNow;

                searchResults.Add((prNumber, repoParts, title, htmlUrl ?? "", draft, createdAt));
            }

            if (itemList.Count < 100) break;
            searchPage++;
        }

        // Step 2: For each unique repo, fetch full PR details via REST API
        var repos = searchResults.Select(r => r.RepoFullName).Distinct().ToList();
        Console.WriteLine($"[SyncFromGitHub] Found {searchResults.Count} PRs across {repos.Count} repos for user {username}");
        foreach (var repo in repos)
        {
            var repoPrs = searchResults.Where(r => r.RepoFullName == repo).ToList();
            Console.WriteLine($"[SyncFromGitHub] Fetching PRs from {repo} ({repoPrs.Count} from search)");
            var repoResp = await _github.GetAsync($"/repos/{repo}/pulls?state=open&per_page=100", token);

            if (repoResp.StatusCode == 0 || repoResp.StatusCode is < 200 or >= 300)
            {
                Console.WriteLine($"[SyncFromGitHub] {repo} returned {repoResp.StatusCode}");
                continue;
            }

            var repoDoc = repoResp.Body;
            if (repoDoc!.Value.ValueKind != JsonValueKind.Array)
            {
                Console.WriteLine($"[SyncFromGitHub] {repo} response is not array: {repoDoc.Value.ValueKind}");
                continue;
            }
            Console.WriteLine($"[SyncFromGitHub] {repo} returned {repoDoc.Value.GetArrayLength()} PRs");

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
        return ApiResult.Ok(new { synced });
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
            await SyncCheckRunsForCommit(repo, sha, token);
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

        var results = new List<object>();
        foreach (var pr in prs)
        {
            var (_, mergeable, headSha) = prData.GetValueOrDefault(pr.PrNumber);
            var effectiveStatus = statusOverrides.GetValueOrDefault(pr.PrNumber, pr.Status);

            string ciStatus = "review";
            if (headSha != null)
            {
                var prRuns = allRuns
                    .Where(r => r.Repo == pr.RepoFullName && r.HeadSha == headSha
                        && r.Status != "superseded" && r.Status != "cancelled" && r.Status != "skipped")
                    .ToList();
                var latestByWorkflow = prRuns
                    .GroupBy(r => r.WorkflowName)
                    .Select(g => g.OrderByDescending(r => r.Id).First())
                    .ToList();

                if (latestByWorkflow.Count == 0)
                    ciStatus = "waiting";
                else if (latestByWorkflow.Any(r => r.Status == "in_progress"))
                    ciStatus = "waiting";
                else if (latestByWorkflow.Any(r => r.Status == "failure"))
                    ciStatus = "failed";
                else
                    ciStatus = "review";
            }

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

            // Only compute "ready" for PRs that are still open. A merged/closed PR
            // must never show as ready to merge.
            if (effectiveStatus == "open" && ciStatus == "review"
                && reviewOverrides.GetValueOrDefault(pr.PrNumber, pr.ReviewApproved))
                ciStatus = "ready";

            var finalReviewApproved = reviewOverrides.GetValueOrDefault(pr.PrNumber, pr.ReviewApproved);
            var subscriberIds = IdListSerializer.Deserialize(pr.SubscriberIds);

            results.Add(new
            {
                pr.PrNumber,
                pr.Title,
                Repo = pr.RepoFullName,
                pr.HeadBranch,
                pr.BaseBranch,
                HtmlUrl = pr.PrUrl,
                Status = effectiveStatus,
                Conclusion = conclusion,
                Draft = pr.Draft,
                MergeableState = mergeable,
                CiStatus = ciStatus,
                ReviewApproved = finalReviewApproved,
                LastCommentBy = pr.LastCommentBy,
                LastCommentBody = pr.LastCommentBody,
                LastCommentAt = pr.LastCommentAt,
                LastCommentUrl = pr.LastCommentUrl,
                LastReviewFilePath = pr.LastReviewFilePath,
                LastReviewLine = pr.LastReviewLine,
                IsSubscribed = subscriberIds.Contains(gitHubId),
                SubscriberIds = subscriberIds,
                AuthorGitHubId = pr.AuthorGitHubId
            });
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
        catch { }

        return ApiResult.Ok(new
        {
            prNumber,
            repo,
            mergeableState,
            behindBy,
            aheadBy,
            title = prEvent?.Title,
            headBranch = prEvent?.HeadBranch,
            baseBranch = prEvent?.BaseBranch,
            status = prEvent?.Status,
            draft = prEvent?.Draft ?? false,
            lastCommentBy = prEvent?.LastCommentBy,
            lastCommentBody = prEvent?.LastCommentBody,
            lastCommentAt = prEvent?.LastCommentAt,
            lastCommentUrl = prEvent?.LastCommentUrl,
            lastReviewFilePath = prEvent?.LastReviewFilePath,
            lastReviewLine = prEvent?.LastReviewLine
        });
    }

    // ─────────────────────────── Merge ───────────────────────────

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
        var prEvent = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();
        if (prEvent != null)
        {
            prEvent.Status = "merged";
            await _db.SaveChangesAsync();
        }

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");

        return ApiResult.Ok(new
        {
            merged = mergeData is { } m2 && m2.TryGetProperty("merged", out var merged) && merged.GetBoolean(),
            sha = mergeData is { } m3 && m3.TryGetProperty("sha", out var sha) ? sha.GetString() : null,
            message = mergeData is { } m4 && m4.TryGetProperty("message", out var msg2) ? msg2.GetString() : null
        });
    }

    // ─────────────────────────── Draft toggle ───────────────────────────

    public async Task<ApiResult> SetDraftAsync(long prNumber, string repo, long gitHubId, bool draft)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token found" });

        Console.WriteLine($"[SetDraft] PR #{prNumber} in {repo} set draft={draft}, tokenSource={(user?.UserPatToken != null ? "UserPatToken" : user?.AccessToken != null ? "AccessToken" : "SharedPat")}");

        // Step 1: Get PR node_id via REST API
        string nodeId;
        {
            var getResp = await _github.GetAsync($"/repos/{repo}/pulls/{prNumber}", token);
            if (getResp.StatusCode == 0)
                return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
            if (getResp.StatusCode is < 200 or >= 300 || getResp.Body is not { } getDoc)
                return ApiResult.FromGitHubStatus(getResp.StatusCode, new { error = "Failed to fetch PR", detail = getResp.Body });
            nodeId = getDoc.GetProperty("node_id").GetString() ?? "";
            Console.WriteLine($"[SetDraft] Got node_id={nodeId}");
        }

        // Step 2: Use GraphQL mutation to change draft status
        // REST API silently ignores the "draft" field — only GraphQL mutations work.
        var mutationName = draft ? "convertPullRequestToDraft" : "markPullRequestReadyForReview";
        var gql = $@"mutation {{ {mutationName}(input: {{ pullRequestId: ""{nodeId}"" }}) {{ pullRequest {{ id isDraft }} }} }}";
        Console.WriteLine($"[SetDraft] GraphQL mutation: {mutationName}");

        var gqlResp = await _github.GraphQlAsync(gql, token);
        var gqlJson = gqlResp.Body;
        Console.WriteLine($"[SetDraft] GraphQL replied {gqlResp.StatusCode}: {(gqlJson?.GetRawText()?.Length > 500 ? gqlJson?.GetRawText()[..500] : gqlJson?.GetRawText())}");

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
            Console.WriteLine($"[SetDraft] GraphQL errors: {gqlDoc.GetRawText()}");
            return ApiResult.Error(StatusCodes.Status422UnprocessableEntity, new { error = firstErr, detail = gqlDoc.GetRawText() });
        }

        // Update DB
        var prEvent = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo)
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();
        if (prEvent != null)
        {
            prEvent.Draft = draft;
            await _db.SaveChangesAsync();
            Console.WriteLine($"[SetDraft] DB updated: PR #{prNumber} draft={draft}");
        }

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");

        return ApiResult.Ok(new { success = true, draft });
    }

    // ─────────────────────────── Update branch ───────────────────────────

    public async Task<ApiResult> UpdateBranchAsync(long prNumber, string repo, long gitHubId)
    {
        var user = await _tokens.GetUserAsync(gitHubId);
        var token = _tokens.ResolveForUser(user);
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token found" });

        Console.WriteLine($"[UpdateBranch] Token: {(user?.UserPatToken != null ? "UserPatToken" : user?.AccessToken != null ? "AccessToken" : "SharedPat")}");

        var response = await _github.PutAsync($"/repos/{repo}/pulls/{prNumber}/update-branch", token, new { });
        var data = response.Body;
        Console.WriteLine($"[UpdateBranch] GitHub replied {response.StatusCode} for {repo} PR #{prNumber}: {data?.GetRawText()}");

        if (response.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (response.StatusCode is < 200 or >= 300)
        {
            var msg = data is { } d && d.TryGetProperty("message", out var m) ? m.GetString() : "Unknown error";
            return ApiResult.FromGitHubStatus(response.StatusCode, new { error = msg });
        }

        // Mark old workflow runs for this PR's branch as superseded so ciStatus
        // does not stay "failed" while waiting for new workflow webhooks
        var prEvent = await _db.PullRequestEvents
            .Where(p => p.PrNumber == prNumber && p.RepoFullName == repo && p.Status == "open")
            .OrderByDescending(p => p.OccurredAt)
            .FirstOrDefaultAsync();
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
                Console.WriteLine($"[UpdateBranch] Superseded {stale.Count} old runs for {repo} #{prNumber} branch={prEvent.HeadBranch}");
            }
        }

        // Resync PRs after update
        await _hub.Clients.All.SendAsync("PullRequestsUpdated");

        return ApiResult.Ok(new
        {
            message = data is { } d2 && d2.TryGetProperty("message", out var msg2) ? msg2.GetString() : "Branch updated"
        });
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

        var commits = body.EnumerateArray().Select(c => new
        {
            sha = c.GetProperty("sha").GetString(),
            message = c.GetProperty("commit").GetProperty("message").GetString(),
            authorName = c.GetProperty("commit").GetProperty("author").GetProperty("name").GetString(),
            authorLogin = c.TryGetProperty("author", out var a) && a.ValueKind == JsonValueKind.Object
                ? (a.TryGetProperty("login", out var l) ? l.GetString() : null) : null,
            date = c.GetProperty("commit").GetProperty("author").GetProperty("date").GetString(),
            url = c.TryGetProperty("html_url", out var hu) ? hu.GetString() : null
        }).ToList();

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

        var files = body.EnumerateArray().Select(f => new
        {
            filename = f.GetProperty("filename").GetString(),
            status = f.GetProperty("status").GetString(),
            additions = f.GetProperty("additions").GetInt32(),
            deletions = f.GetProperty("deletions").GetInt32()
        }).ToList();

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
            return ApiResult.Ok(Array.Empty<object>());

        // Now fetch check runs for that SHA
        var crResp = await _github.GetAsync($"/repos/{repo}/commits/{headSha}/check-runs?per_page=100", token);
        if (crResp.StatusCode == 0)
            return ApiResult.FromGitHubStatus(0, new { error = "GitHub API unreachable" });
        if (crResp.StatusCode is < 200 or >= 300 || crResp.Body is not { } crDoc)
            return ApiResult.FromGitHubStatus(crResp.StatusCode, new { error = "Failed to fetch check runs", detail = crResp.Body });

        if (!crDoc.TryGetProperty("check_runs", out var checkRunsProp))
            return ApiResult.Ok(Array.Empty<object>());

        var checks = checkRunsProp.EnumerateArray().Select(cr => new
        {
            name = cr.GetProperty("name").GetString(),
            status = cr.GetProperty("status").GetString(),
            conclusion = cr.TryGetProperty("conclusion", out var conc) ? conc.GetString() : null,
            startedAt = cr.TryGetProperty("started_at", out var sa) ? sa.GetString() : null,
            completedAt = cr.TryGetProperty("completed_at", out var ca) ? ca.GetString() : null,
            url = cr.TryGetProperty("html_url", out var hu) ? hu.GetString() : null
        }).ToList();

        return ApiResult.Ok(checks);
    }

    // ─────────────────────────── Subscribers ───────────────────────────

    public async Task<ApiResult> SubscribeAsync(long prNumber, string repo, long gitHubId)
    {
        var pr = await FindOpenPrAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (!current.Contains(gitHubId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Append(gitHubId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { subscribed = true, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }

    public async Task<ApiResult> UnsubscribeAsync(long prNumber, string repo, long gitHubId)
    {
        var pr = await FindOpenPrAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (current.Contains(gitHubId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Where(id => id != gitHubId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { subscribed = false, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }

    public async Task<ApiResult> GetSubscribersAsync(long prNumber, string repo)
    {
        var pr = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo)
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        var ids = IdListSerializer.Deserialize(pr.SubscriberIds);

        var users = await _db.GitHubUsers
            .Where(u => ids.Contains(u.GitHubId))
            .Select(u => new { u.GitHubId, u.GitHubUsername, u.AvatarUrl })
            .ToListAsync();

        return ApiResult.Ok(new { subscribers = users, subscriberIds = ids });
    }

    public async Task<ApiResult> AddSubscriberAsync(long prNumber, string repo, long gitHubId, string? username, long? subscriberId)
    {
        var pr = await FindOpenPrAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        // Only PR author can add subscribers (or self-subscribe)
        if (pr.AuthorGitHubId != gitHubId)
            return ApiResult.Forbid();

        long targetId;
        if (subscriberId.HasValue)
        {
            targetId = subscriberId.Value;
            var userExists = await _db.GitHubUsers.AnyAsync(u => u.GitHubId == targetId);
            if (!userExists) return ApiResult.NotFound(new { error = "User not found in database" });
        }
        else if (!string.IsNullOrEmpty(username))
        {
            var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == username);
            if (user == null) return ApiResult.NotFound(new { error = "User not found in database" });
            targetId = user.GitHubId;
        }
        else
        {
            return ApiResult.BadRequest(new { error = "Must provide username or subscriberId" });
        }

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (!current.Contains(targetId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Append(targetId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { added = true, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }

    public async Task<ApiResult> RemoveSubscriberAsync(long prNumber, string repo, long gitHubId, long subscriberId)
    {
        var pr = await FindOpenPrAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        // Only PR author can remove subscribers (or self-unsubscribe)
        if (pr.AuthorGitHubId != gitHubId && subscriberId != gitHubId)
            return ApiResult.Forbid();

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (current.Contains(subscriberId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Where(id => id != subscriberId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _hub.Clients.All.SendAsync("PullRequestsUpdated");
        return ApiResult.Ok(new { removed = true, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }

    // ─────────────────────────── Private helpers ───────────────────────────

    private Task<PullRequestEvent?> FindOpenPrAsync(long prNumber, string repo)
        => _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

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
                && DateTime.TryParse(ma.GetString(), null, System.Globalization.DateTimeStyles.AdjustToUniversal, out var parsed))
                mergedAt = parsed;

            return (draft, mergeableState, headSha, prState, merged, mergedAt);
        }
        catch
        {
            return (null, null, null, null, false, null);
        }
    }

    private async Task SyncCheckRunsForCommit(string repo, string sha, string? token)
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

                var mappedStatus = status == "completed"
                    ? conclusion == "success" ? "success"
                    : conclusion == "failure" || conclusion == "timed_out" ? "failure"
                    : "cancelled"
                    : "in_progress";

                // Find existing run for this (repo, sha, workflowName)
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
            Console.WriteLine($"[SyncCheckRuns] Error for {repo} @ {sha}: {ex.Message}");
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
                if (state == "APPROVED" || state == "CHANGES_REQUESTED" || state == "DISMISSED")
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
