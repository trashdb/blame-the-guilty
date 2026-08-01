using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Statefalse.Api.Services;

namespace Statefalse.Api.Controllers;

[ApiController]
[Route("api/pullrequests")]
public class PullRequestsController : ControllerBase
{
    private readonly PullRequestService _service;

    public PullRequestsController(PullRequestService service)
    {
        _service = service;
    }

    [HttpPost("sync")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> SyncFromGitHub([FromQuery] long gitHubId)
        => MapAsync(_service.SyncFromGitHubAsync(gitHubId));

    [HttpGet("active")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> GetActive([FromQuery] long gitHubId, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
        => MapAsync(_service.GetActiveAsync(gitHubId, page, pageSize));

    [HttpGet("{prNumber}/detail")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> GetDetail(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
        => MapAsync(_service.GetDetailAsync(prNumber, repo, gitHubId));

    [HttpPost("{prNumber}/merge")]
    public Task<IActionResult> Merge(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId, [FromQuery] string method = "squash")
        => MapAsync(_service.MergeAsync(prNumber, repo, gitHubId, method));

    [HttpPost("{prNumber}/draft")]
    public Task<IActionResult> SetDraft(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId, [FromQuery] bool draft)
        => MapAsync(_service.SetDraftAsync(prNumber, repo, gitHubId, draft));

    [HttpPost("{prNumber}/update-branch")]
    public Task<IActionResult> UpdateBranch(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
        => MapAsync(_service.UpdateBranchAsync(prNumber, repo, gitHubId));

    [HttpGet("{prNumber}/commits")]
    public Task<IActionResult> GetCommits(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
        => MapAsync(_service.GetCommitsAsync(prNumber, repo, gitHubId));

    [HttpGet("{prNumber}/files")]
    public Task<IActionResult> GetFiles(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
        => MapAsync(_service.GetFilesAsync(prNumber, repo, gitHubId));

    [HttpGet("{prNumber}/checks")]
    public Task<IActionResult> GetChecks(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
        => MapAsync(_service.GetChecksAsync(prNumber, repo, gitHubId));

    [HttpPost("{prNumber}/subscribe")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> Subscribe(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
        => MapAsync(_service.SubscribeAsync(prNumber, repo, gitHubId));

    [HttpPost("{prNumber}/unsubscribe")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> Unsubscribe(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId)
        => MapAsync(_service.UnsubscribeAsync(prNumber, repo, gitHubId));

    [HttpGet("{prNumber}/subscribers")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> GetSubscribers(long prNumber, [FromQuery] string repo)
        => MapAsync(_service.GetSubscribersAsync(prNumber, repo));

    [HttpPost("{prNumber}/add-subscriber")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> AddSubscriber(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId, [FromQuery] string? username = null, [FromQuery] long? subscriberId = null)
        => MapAsync(_service.AddSubscriberAsync(prNumber, repo, gitHubId, username, subscriberId));

    [HttpPost("{prNumber}/remove-subscriber")]
    [EnableRateLimiting("api")]
    public Task<IActionResult> RemoveSubscriber(long prNumber, [FromQuery] string repo, [FromQuery] long gitHubId, [FromQuery] long subscriberId)
        => MapAsync(_service.RemoveSubscriberAsync(prNumber, repo, gitHubId, subscriberId));

    private async Task<IActionResult> MapAsync(Task<ApiResult> task)
    {
        var result = await task;
        return new ObjectResult(result.Value) { StatusCode = result.StatusCode };
    }
}
