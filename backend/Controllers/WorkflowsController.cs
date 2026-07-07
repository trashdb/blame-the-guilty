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
                w.StartedAt
            })
            .ToListAsync();

        return Ok(runs);
    }
}
