using System.Text;
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
    private readonly AppDbContext _db;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;

    public PullRequestsController(AppDbContext db, IHttpClientFactory httpClientFactory, IConfiguration configuration)
    {
        _db = db;
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive([FromQuery] string? login = null, [FromQuery] long? gitHubId = null)
    {
        var query = _db.PullRequestEvents
            .Where(e => e.Status != "closed")
            .AsQueryable();

        if (gitHubId.HasValue)
            query = query.Where(e => e.AuthorGitHubId == gitHubId.Value);
        else if (!string.IsNullOrEmpty(login))
            query = query.Where(e => e.AuthorLogin == login);
        else
            return Ok(Array.Empty<object>());

        var prs = await query
            .OrderByDescending(e => e.OccurredAt)
            .Take(10)
            .Select(e => new
            {
                e.PrNumber,
                e.Title,
                e.AuthorLogin,
                e.RepoFullName,
                e.HeadBranch,
                e.BaseBranch,
                e.PrUrl,
                e.Status,
                e.Conclusion,
                e.OccurredAt
            })
            .ToListAsync();

        return Ok(prs);
    }

    [HttpGet("recent")]
    public async Task<IActionResult> GetRecent([FromQuery] string? login = null, [FromQuery] long? gitHubId = null, [FromQuery] int limit = 20)
    {
        var query = _db.PullRequestEvents.AsQueryable();

        if (gitHubId.HasValue)
            query = query.Where(e => e.AuthorGitHubId == gitHubId.Value);
        else if (!string.IsNullOrEmpty(login))
            query = query.Where(e => e.AuthorLogin == login);
        else
            return Ok(Array.Empty<object>());

        var prs = await query
            .OrderByDescending(e => e.OccurredAt)
            .Take(limit)
            .Select(e => new
            {
                e.PrNumber,
                e.Title,
                e.AuthorLogin,
                e.RepoFullName,
                e.HeadBranch,
                e.BaseBranch,
                e.PrUrl,
                e.Status,
                e.Conclusion,
                e.OccurredAt
            })
            .ToListAsync();

        return Ok(prs);
    }

    [HttpPost("merge")]
    public async Task<IActionResult> MergePullRequest([FromBody] MergeRequest request)
    {
        // Try to use the user's own access token first
        string? token = null;
        if (request.GitHubId.HasValue)
        {
            var user = await _db.GitHubUsers
                .FirstOrDefaultAsync(u => u.GitHubId == request.GitHubId.Value);
            token = user?.AccessToken;
        }

        // Fall back to shared token if no user token
        token ??= _configuration["GitHub:Token"];

        if (string.IsNullOrEmpty(token))
            return BadRequest(new { error = "No GitHub token available. Log in again or configure GitHub:Token." });

        var client = _httpClientFactory.CreateClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("BlameTheGuilty/1.0");
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");

        var body = JsonSerializer.Serialize(new { });
        var content = new StringContent(body, Encoding.UTF8, "application/json");

        var url = $"https://api.github.com/repos/{request.RepoFullName}/pulls/{request.PrNumber}/merge";
        var response = await client.PutAsync(url, content);
        var responseBody = await response.Content.ReadAsStringAsync();

        if (response.IsSuccessStatusCode)
        {
            return Ok(new { merged = true, details = responseBody });
        }

        return BadRequest(new { merged = false, error = responseBody });
    }
}

public class MergeRequest
{
    public string RepoFullName { get; set; } = string.Empty;
    public int PrNumber { get; set; }
    public long? GitHubId { get; set; }
}
