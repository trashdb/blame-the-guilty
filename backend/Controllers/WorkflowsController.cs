using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;
using Statefalse.Api.Services;

namespace Statefalse.Api.Controllers;

[ApiController]
[Route("api/workflows")]
public class WorkflowsController : ControllerBase
{
    private readonly WorkflowService _service;

    public WorkflowsController(WorkflowService service)
    {
        _service = service;
    }

    [HttpGet("runs")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> GetRuns([FromQuery] long gitHubId, [FromQuery] int limit = 20)
        => MapAsync(_service.GetRunsAsync(gitHubId, limit));

    [HttpPut("runs/{id}/target")]
    public Task<IActionResult> SetTarget(int id, [FromBody] SetTargetRequest request)
        => MapAsync(_service.SetTargetAsync(id, request));

    [HttpPost("runs/{runId}/rerun")]
    public Task<IActionResult> RerunRun(long runId, [FromQuery] long gitHubId)
        => MapAsync(_service.RerunAsync(runId, gitHubId));

    [HttpPost("sync-active")]
    public Task<IActionResult> SyncActiveWorkflows([FromQuery] long gitHubId)
        => MapAsync(_service.SyncActiveAsync(gitHubId));

    private async Task<IActionResult> MapAsync(Task<ApiResult> task)
    {
        var result = await task;
        return new ObjectResult(result.Value) { StatusCode = result.StatusCode };
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
                Login = u.GitHubUsername,
                u.AvatarUrl
            })
            .ToListAsync();

        return Ok(users);
    }
}
