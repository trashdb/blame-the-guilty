using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Models;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/workflows")]
public class WorkflowsController : ControllerBase
{
    private readonly AppDbContext _db;

    public WorkflowsController(AppDbContext db)
    {
        _db = db;
    }

    [HttpGet("runs")]
    public async Task<IActionResult> GetRuns(
        [FromQuery] long gitHubId,
        [FromQuery] int limit = 20)
    {
        var runs = await _db.WorkflowRuns
            .Where(w => w.GitHubId == gitHubId)
            .OrderByDescending(w => w.Id)
            .Take(limit)
            .Select(w => new
            {
                w.RunId,
                w.WorkflowName,
                w.Repo,
                w.Actor,
                w.Status,
                w.HtmlUrl,
                w.StartedAt,
                TargetGitHubId = w.TargetGitHubId
            })
            .ToListAsync();

        return Ok(runs);
    }

    [HttpPut("runs/{runId}/target")]
    public async Task<IActionResult> SetTarget(long runId, [FromBody] SetTargetRequest request)
    {
        var run = await _db.WorkflowRuns
            .Where(w => w.RunId == runId && w.Status == "in_progress")
            .FirstOrDefaultAsync();

        if (run == null)
            return NotFound("No in-progress workflow run found with that runId.");

        run.TargetGitHubId = request.TargetGitHubId;
        await _db.SaveChangesAsync();

        return Ok(new { runId, targetGitHubId = run.TargetGitHubId });
    }

    public class SetTargetRequest
    {
        public long? TargetGitHubId { get; set; }
    }
}

[ApiController]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly AppDbContext _db;

    public UsersController(AppDbContext db)
    {
        _db = db;
    }

    [HttpGet]
    public async Task<IActionResult> GetUsers()
    {
        var users = await _db.GitHubUsers
            .Select(u => new
            {
                u.GitHubId,
                Login = u.GitHubUsername
            })
            .ToListAsync();

        return Ok(users);
    }
}
