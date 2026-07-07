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

        var results = new List<object>();
        foreach (var pr in prs)
        {
            var (draft, mergeableState) = await FetchPullRequestData(pr.PrNumber, pr.RepoFullName, token);
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
                MergeableState = mergeableState
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
