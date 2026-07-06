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

    public PullRequestsController(AppDbContext db)
    {
        _db = db;
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive([FromQuery] string? login = null, [FromQuery] long? gitHubId = null)
    {
        var query = _db.PullRequestEvents
            .Where(e => e.Status == "open")
            .AsQueryable();

        if (gitHubId.HasValue)
            query = query.Where(e => e.AuthorGitHubId == gitHubId.Value);
        else if (!string.IsNullOrEmpty(login))
            query = query.Where(e => e.AuthorLogin == login);
        else
            return Ok(Array.Empty<object>());

        var prs = await query
            .OrderByDescending(e => e.OccurredAt)
            .Select(e => new
            {
                e.PrNumber,
                e.Title,
                e.AuthorLogin,
                e.RepoFullName,
                e.HeadBranch,
                e.BaseBranch,
                e.PrUrl,
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
}
