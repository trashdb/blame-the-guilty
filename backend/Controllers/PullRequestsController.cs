using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Hubs;
using BlameTheGuilty.Api.Models;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/pullrequests")]
public class PullRequestsController : ControllerBase
{
    private static readonly HttpClient _githubClient = new();
    private readonly AppDbContext _db;
    private readonly IConfiguration _configuration;
    private readonly IHubContext<PunishmentHub> _hubContext;

    public PullRequestsController(AppDbContext db, IConfiguration configuration, IHubContext<PunishmentHub> hubContext)
    {
        _db = db;
        _configuration = configuration;
        _hubContext = hubContext;
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive([FromQuery] long gitHubId)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken;
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No token" });

        var prs = await _db.PullRequestEvents
            .Where(e => ((e.Status == "open" || e.Status == "in_progress") || (e.Status == "merged" && e.OccurredAt >= DateTime.UtcNow.AddHours(-24))) && e.AuthorGitHubId == gitHubId)
            .OrderByDescending(e => e.OccurredAt)
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
                e.LastReviewLine
            })
            .ToListAsync();

        var repos = prs.Select(p => p.RepoFullName).Distinct().ToList();

        // Fetch head SHA, draft, mergeable for every PR from GitHub API
        var prData = new Dictionary<long, (bool? Draft, string? Mergeable, string? HeadSha)>();
        foreach (var pr in prs)
        {
            var (draft, mergeable, headSha) = await FetchPullRequestData(pr.PrNumber, pr.RepoFullName, token);
            prData[pr.PrNumber] = (draft, mergeable, headSha);
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

            string ciStatus = "review";
            if (headSha != null)
            {
                var prRuns = allRuns
                    .Where(r => r.Repo == pr.RepoFullName && r.HeadSha == headSha
                        && r.Status != "superseded" && r.Status != "cancelled")
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

            if (ciStatus == "review" && pr.ReviewApproved)
                ciStatus = "ready";

            results.Add(new
            {
                pr.PrNumber,
                pr.Title,
                Repo = pr.RepoFullName,
                pr.HeadBranch,
                pr.BaseBranch,
                HtmlUrl = pr.PrUrl,
                pr.Status,
                pr.Conclusion,
                Draft = pr.Draft,
                MergeableState = mergeable,
                CiStatus = ciStatus,
                ReviewApproved = pr.ReviewApproved,
                LastCommentBy = pr.LastCommentBy,
                LastCommentBody = pr.LastCommentBody,
                LastCommentAt = pr.LastCommentAt,
                LastCommentUrl = pr.LastCommentUrl,
                LastReviewFilePath = pr.LastReviewFilePath,
                LastReviewLine = pr.LastReviewLine
            });
        }

        return Ok(results);
    }

    [HttpGet("{prNumber}/detail")]
    public async Task<IActionResult> GetDetail(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];

        var prEvent = await _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo)
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

        int? behindBy = null, aheadBy = null;
        string? mergeableState = null;

        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get,
                $"https://api.github.com/repos/{repo}/pulls/{prNumber}");
            request.Headers.UserAgent.ParseAdd("BlameTheGuilty");
            if (!string.IsNullOrEmpty(token))
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

            var response = await _githubClient.SendAsync(request);
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                var data = JsonSerializer.Deserialize<JsonElement>(content);

                if (data.TryGetProperty("mergeable_state", out var ms))
                    mergeableState = ms.GetString();

                var headSha = data.GetProperty("head").GetProperty("sha").GetString();
                var baseRef = data.GetProperty("base").GetProperty("ref").GetString();

                if (headSha != null && baseRef != null)
                {
                    var compareReq = new HttpRequestMessage(HttpMethod.Get,
                        $"https://api.github.com/repos/{repo}/compare/{baseRef}...{headSha}");
                    compareReq.Headers.UserAgent.ParseAdd("BlameTheGuilty");
                    if (!string.IsNullOrEmpty(token))
                        compareReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

                    var compareResp = await _githubClient.SendAsync(compareReq);
                    if (compareResp.IsSuccessStatusCode)
                    {
                        var compareContent = await compareResp.Content.ReadAsStringAsync();
                        var compareData = JsonSerializer.Deserialize<JsonElement>(compareContent);
                        if (compareData.TryGetProperty("behind_by", out var bb)) behindBy = bb.GetInt32();
                        if (compareData.TryGetProperty("ahead_by", out var ab)) aheadBy = ab.GetInt32();
                    }
                }
            }
        }
        catch { }

        return Ok(new
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

    [HttpPost("{prNumber}/merge")]
    public async Task<IActionResult> Merge(long prNumber,
        [FromQuery] string repo,
        [FromQuery] long gitHubId,
        [FromQuery] string method = "squash")
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No access token found" });

        // Fetch PR to get head SHA for the merge request
        var prRequest = new HttpRequestMessage(HttpMethod.Get,
            $"https://api.github.com/repos/{repo}/pulls/{prNumber}");
        prRequest.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        prRequest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        HttpResponseMessage prResponse;
        try { prResponse = await _githubClient.SendAsync(prRequest); }
        catch (Exception ex) { return StatusCode(502, new { error = $"GitHub API error: {ex.Message}" }); }

        if (!prResponse.IsSuccessStatusCode)
            return StatusCode((int)prResponse.StatusCode, new { error = "Failed to fetch PR details from GitHub" });

        var prJson = await prResponse.Content.ReadAsStringAsync();
        var prData = JsonSerializer.Deserialize<JsonElement>(prJson);
        var headSha = prData.GetProperty("head").GetProperty("sha").GetString();

        var mergeRequest = new HttpRequestMessage(HttpMethod.Put,
            $"https://api.github.com/repos/{repo}/pulls/{prNumber}/merge");
        mergeRequest.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        mergeRequest.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        var mergeBody = new
        {
            merge_method = method,
            sha = headSha,
            commit_title = $"Merge PR #{prNumber} — {prData.GetProperty("title").GetString()}"
        };
        mergeRequest.Content = new StringContent(
            JsonSerializer.Serialize(mergeBody),
            System.Text.Encoding.UTF8,
            "application/json");

        HttpResponseMessage mergeResponse;
        try { mergeResponse = await _githubClient.SendAsync(mergeRequest); }
        catch (Exception ex) { return StatusCode(502, new { error = $"GitHub merge API error: {ex.Message}" }); }

        var mergeJson = await mergeResponse.Content.ReadAsStringAsync();
        var mergeData = JsonSerializer.Deserialize<JsonElement>(mergeJson);

        if (!mergeResponse.IsSuccessStatusCode)
        {
            var msg = mergeData.TryGetProperty("message", out var m) ? m.GetString() : "Unknown error";
            return StatusCode((int)mergeResponse.StatusCode, new { error = msg, details = mergeData });
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

        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");

        return Ok(new
        {
            merged = mergeData.TryGetProperty("merged", out var merged) && merged.GetBoolean(),
            sha = mergeData.TryGetProperty("sha", out var sha) ? sha.GetString() : null,
            message = mergeData.TryGetProperty("message", out var msg2) ? msg2.GetString() : null
        });
    }

    [HttpPost("{prNumber}/draft")]
    public async Task<IActionResult> SetDraft(long prNumber,
        [FromQuery] string repo,
        [FromQuery] long gitHubId,
        [FromQuery] bool draft)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No access token found" });

        Console.WriteLine($"[SetDraft] PR #{prNumber} in {repo} set draft={draft}, tokenSource={(user?.UserPatToken != null ? "UserPatToken" : user?.AccessToken != null ? "AccessToken" : "SharedPat")}");

        // Step 1: Get PR node_id via REST API
        string nodeId;
        {
            var getReq = new HttpRequestMessage(HttpMethod.Get,
                $"https://api.github.com/repos/{repo}/pulls/{prNumber}");
            getReq.Headers.UserAgent.ParseAdd("BlameTheGuilty");
            getReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
            HttpResponseMessage getResp;
            try { getResp = await _githubClient.SendAsync(getReq); }
            catch (Exception ex) { return StatusCode(502, new { error = $"GitHub API error: {ex.Message}" }); }
            var getJson = await getResp.Content.ReadAsStringAsync();
            if (!getResp.IsSuccessStatusCode)
                return StatusCode((int)getResp.StatusCode, new { error = "Failed to fetch PR", detail = getJson });
            using var getDoc = JsonDocument.Parse(getJson);
            nodeId = getDoc.RootElement.GetProperty("node_id").GetString() ?? "";
            Console.WriteLine($"[SetDraft] Got node_id={nodeId}");
        }

        // Step 2: Use GraphQL mutation to change draft status
        // REST API silently ignores the "draft" field — only GraphQL mutations work.
        var mutationName = draft ? "convertPullRequestToDraft" : "markPullRequestReadyForReview";
        var gql = $@"mutation {{ {mutationName}(input: {{ pullRequestId: ""{nodeId}"" }}) {{ pullRequest {{ id isDraft }} }} }}";
        Console.WriteLine($"[SetDraft] GraphQL mutation: {mutationName}");

        var gqlReq = new HttpRequestMessage(HttpMethod.Post, "https://api.github.com/graphql");
        gqlReq.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        gqlReq.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        gqlReq.Content = new StringContent(
            JsonSerializer.Serialize(new { query = gql }),
            System.Text.Encoding.UTF8,
            "application/json");

        HttpResponseMessage gqlResp;
        try { gqlResp = await _githubClient.SendAsync(gqlReq); }
        catch (Exception ex) { return StatusCode(502, new { error = $"GitHub GraphQL error: {ex.Message}" }); }

        var gqlJson = await gqlResp.Content.ReadAsStringAsync();
        Console.WriteLine($"[SetDraft] GraphQL replied {(int)gqlResp.StatusCode}: {gqlJson[..Math.Min(gqlJson.Length, 500)]}");

        if (!gqlResp.IsSuccessStatusCode)
        {
            var msg = "";
            try { using var d = JsonDocument.Parse(gqlJson); msg = d.RootElement.TryGetProperty("message", out var m) ? m.GetString() ?? "" : ""; } catch { }
            return StatusCode((int)gqlResp.StatusCode, new { error = msg, detail = gqlJson });
        }

        // Check for GraphQL-level errors
        using var gqlDoc = JsonDocument.Parse(gqlJson);
        if (gqlDoc.RootElement.TryGetProperty("errors", out var errors) && errors.GetArrayLength() > 0)
        {
            var firstErr = errors[0].TryGetProperty("message", out var em) ? em.GetString() ?? "" : "Unknown GraphQL error";
            Console.WriteLine($"[SetDraft] GraphQL errors: {gqlJson}");
            return StatusCode(422, new { error = firstErr, detail = gqlJson });
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

        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");

        return Ok(new { success = true, draft });
    }

    [HttpPost("{prNumber}/update-branch")]
    public async Task<IActionResult> UpdateBranch(long prNumber,
        [FromQuery] string repo,
        [FromQuery] long gitHubId)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No access token found" });

        Console.WriteLine($"[UpdateBranch] Token: {(user?.UserPatToken != null ? "UserPatToken" : user?.AccessToken != null ? "AccessToken" : "SharedPat")}");

        var request = new HttpRequestMessage(HttpMethod.Put,
            $"https://api.github.com/repos/{repo}/pulls/{prNumber}/update-branch");
        request.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        request.Content = new StringContent("{}", System.Text.Encoding.UTF8, "application/json");

        HttpResponseMessage response;
        try { response = await _githubClient.SendAsync(request); }
        catch (Exception ex) { return StatusCode(502, new { error = $"GitHub API error: {ex.Message}" }); }

        var json = await response.Content.ReadAsStringAsync();
        var data = JsonSerializer.Deserialize<JsonElement>(json);

        Console.WriteLine($"[UpdateBranch] GitHub replied {response.StatusCode} for {repo} PR #{prNumber}: {json}");

        if (!response.IsSuccessStatusCode)
        {
            var msg = data.TryGetProperty("message", out var m) ? m.GetString() : "Unknown error";
            return StatusCode((int)response.StatusCode, new { error = msg });
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
        await _hubContext.Clients.All.SendAsync("PullRequestsUpdated");

        return Ok(new
        {
            message = data.TryGetProperty("message", out var msg2) ? msg2.GetString() : "Branch updated"
        });
    }

    private async Task<(bool? draft, string? mergeableState, string? headSha)> FetchPullRequestData(long prNumber, string repoFullName, string? token)
    {
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{repoFullName}/pulls/{prNumber}");
            request.Headers.UserAgent.ParseAdd("BlameTheGuilty");
            if (!string.IsNullOrEmpty(token))
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

            var response = await _githubClient.SendAsync(request);
            if (!response.IsSuccessStatusCode) return (null, null, null);

            var content = await response.Content.ReadAsStringAsync();
            var data = JsonSerializer.Deserialize<JsonElement>(content);

            bool? draft = null;
            if (data.TryGetProperty("draft", out var draftProp))
                draft = draftProp.GetBoolean();

            string? mergeableState = null;
            if (data.TryGetProperty("mergeable_state", out var state))
                mergeableState = state.GetString();

            string? headSha = null;
            if (data.TryGetProperty("head", out var head) && head.TryGetProperty("sha", out var sha))
                headSha = sha.GetString();

            return (draft, mergeableState, headSha);
        }
        catch
        {
            return (null, null, null);
        }
    }

    private async Task SyncCheckRunsForCommit(string repo, string sha, string? token)
    {
        if (string.IsNullOrEmpty(token)) return;
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get,
                $"https://api.github.com/repos/{repo}/commits/{sha}/check-runs?per_page=100");
            request.Headers.UserAgent.ParseAdd("BlameTheGuilty");
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

            var response = await _githubClient.SendAsync(request);
            if (!response.IsSuccessStatusCode) return;

            var content = await response.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(content);
            var checkRuns = doc.RootElement.GetProperty("check_runs").EnumerateArray();

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
                        ? slug.GetString() : "unknown";
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
}
