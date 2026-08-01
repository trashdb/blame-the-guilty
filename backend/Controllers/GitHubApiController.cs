using Microsoft.AspNetCore.Mvc;
using Statefalse.Api.Services;

namespace Statefalse.Api.Controllers;

[ApiController]
[Route("api/github")]
public class GitHubApiController : ControllerBase
{
    private readonly GitHubApiService _service;

    public GitHubApiController(GitHubApiService service)
    {
        _service = service;
    }

    [HttpGet("my-branches")]
    public Task<IActionResult> GetMyBranches([FromQuery] long gitHubId, [FromQuery] string repo)
        => MapAsync(_service.GetMyBranchesAsync(gitHubId, repo));

    [HttpPost("create-pr")]
    public Task<IActionResult> CreatePr([FromQuery] long gitHubId, [FromQuery] string repo,
        [FromQuery] string head, [FromQuery] string baseBranch, [FromQuery] string title,
        [FromQuery] string? body = null, [FromQuery] string? subscribers = null)
        => MapAsync(_service.CreatePrAsync(gitHubId, repo, head, baseBranch, title, body, subscribers));

    [HttpPost("pr-preview")]
    public Task<IActionResult> PrPreview([FromQuery] long gitHubId, [FromQuery] string repo,
        [FromQuery] string head, [FromQuery] string baseBranch, [FromQuery] string title, [FromQuery] bool useAI = true)
        => MapAsync(_service.PrPreviewAsync(gitHubId, repo, head, baseBranch, title, useAI));

    [HttpPost("interpret")]
    public Task<IActionResult> InterpretQuery([FromBody] InterpretRequest request)
        => MapAsync(_service.InterpretAsync(request));

    private async Task<IActionResult> MapAsync(Task<ApiResult> task)
    {
        var result = await task;
        return new ObjectResult(result.Value) { StatusCode = result.StatusCode };
    }
}
