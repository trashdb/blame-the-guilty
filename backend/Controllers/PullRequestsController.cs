using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Models;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/pullrequests")]
public class PullRequestsController : ControllerBase
{
    private static readonly HttpClient _githubClient = new();
    private readonly AppDbContext _db;

    public PullRequestsController(AppDbContext db)
    {
        _db = db;
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
                e.Draft
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
            else if (runs.Any(r => r.status == "failure"))
                ciStatus = "failed";
            else
                ciStatus = "ready";
            workflowStatuses[(repo, branch)] = ciStatus;
        }

        var results = new List<object>();
        foreach (var pr in prs)
        {
            var (draft, mergeableState) = await FetchPullRequestData(pr.PrNumber, pr.RepoFullName, token);
            var ciStatus = pr.HeadBranch != null
                && workflowStatuses.TryGetValue((pr.RepoFullName, pr.HeadBranch), out var st)
                ? st : "ready";
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
                CiStatus = ciStatus
            });
        }

        return Ok(results);
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
