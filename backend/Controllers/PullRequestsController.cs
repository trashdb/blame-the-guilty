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
        var token = user?.AccessToken;

        var prs = await _db.PullRequestEvents
            .Where(e => (e.Status == "open" || e.Status == "in_progress") && e.AuthorGitHubId == gitHubId)
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
                e.LastCommentAt
            })
            .ToListAsync();

        // Fetch all workflow runs for these PRs' repos in one query
        var repos = prs.Select(p => p.RepoFullName).Distinct().ToList();
        var workflowRuns = new List<(string repo, string? branch, string status)>();
        if (repos.Count != 0)
        {
            var raw = await _db.WorkflowRuns
                .Where(w => w.HeadBranch != null && repos.Contains(w.Repo))
                .Select(w => new { w.Repo, w.HeadBranch, w.Status })
                .ToListAsync();
            workflowRuns = raw.Select(r => (r.Repo, r.HeadBranch, r.Status)).ToList();
        }

        var workflowStatuses = new Dictionary<(string repo, string branch), string>();
        var branchKeys = prs
            .Where(p => !string.IsNullOrEmpty(p.HeadBranch))
            .Select(p => (p.RepoFullName, p.HeadBranch!))
            .Distinct();

        foreach (var (repo, branch) in branchKeys)
        {
            var runs = workflowRuns.Where(w => w.repo == repo && w.branch == branch).ToList();
            string ciStatus;
            if (runs.Any(r => r.status == "in_progress"))
                ciStatus = "waiting";
            else if (runs.Any(r => r.status is "failure" or "cancelled" or "superseded"))
                ciStatus = "failed";
            else
                ciStatus = "review";
            workflowStatuses[(repo, branch)] = ciStatus;
        }

        var results = new List<object>();
        foreach (var pr in prs)
        {
            var (draft, mergeableState) = await FetchPullRequestData(pr.PrNumber, pr.RepoFullName, token);
            var ciStatus = pr.HeadBranch != null
                && workflowStatuses.TryGetValue((pr.RepoFullName, pr.HeadBranch), out var st)
                ? st : "review";
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
                Draft = draft ?? pr.Draft,
                MergeableState = mergeableState,
                CiStatus = ciStatus,
                ReviewApproved = pr.ReviewApproved,
                LastCommentBy = pr.LastCommentBy,
                LastCommentBody = pr.LastCommentBody,
                LastCommentAt = pr.LastCommentAt
            });
        }

        return Ok(results);
    }

    [HttpGet("{prNumber}/detail")]
    public async Task<IActionResult> GetDetail(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.AccessToken ?? _configuration["GitHub:PatToken"];

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

                var head = data.GetProperty("head").GetProperty("sha").GetString();
                var baseSha = data.GetProperty("base").GetProperty("sha").GetString();

                if (head != null && baseSha != null)
                {
                    var compareReq = new HttpRequestMessage(HttpMethod.Get,
                        $"https://api.github.com/repos/{repo}/compare/{baseSha}...{head}");
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
            lastCommentAt = prEvent?.LastCommentAt
        });
    }

    [HttpPost("{prNumber}/merge")]
    public async Task<IActionResult> Merge(long prNumber,
        [FromQuery] string repo,
        [FromQuery] long gitHubId,
        [FromQuery] string method = "squash")
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.AccessToken ?? _configuration["GitHub:PatToken"];
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

    private async Task<(bool? draft, string? mergeableState)> FetchPullRequestData(long prNumber, string repoFullName, string? token)
    {
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{repoFullName}/pulls/{prNumber}");
            request.Headers.UserAgent.ParseAdd("BlameTheGuilty");
            if (!string.IsNullOrEmpty(token))
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

            var response = await _githubClient.SendAsync(request);
            if (!response.IsSuccessStatusCode) return (null, null);

            var content = await response.Content.ReadAsStringAsync();
            var data = JsonSerializer.Deserialize<JsonElement>(content);

            bool? draft = null;
            if (data.TryGetProperty("draft", out var draftProp))
                draft = draftProp.GetBoolean();

            string? mergeableState = null;
            if (data.TryGetProperty("mergeable_state", out var state))
                mergeableState = state.GetString();

            return (draft, mergeableState);
        }
        catch
        {
            return (null, null);
        }
    }
}
