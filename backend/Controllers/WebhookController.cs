using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Hubs;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/webhook")]
public class WebhookController : ControllerBase
{
    private readonly IHubContext<PunishmentHub> _hubContext;
    private readonly AppDbContext _db;
    private readonly ILogger<WebhookController> _logger;

    public WebhookController(
        IHubContext<PunishmentHub> hubContext,
        AppDbContext db,
        ILogger<WebhookController> logger)
    {
        _hubContext = hubContext;
        _db = db;
        _logger = logger;
    }

    [HttpPost("github")]
    public async Task<IActionResult> HandleGitHubWebhook([FromBody] JsonElement payload)
    {
        var action = payload.TryGetProperty("action", out var actionProp)
            ? actionProp.GetString()
            : null;

        if (action != "completed")
            return Ok("Ignored: action is not 'completed'.");

        var workflowRun = payload.GetProperty("workflow_run");
        var conclusion = workflowRun.GetProperty("conclusion").GetString();

        if (conclusion != "failure")
            return Ok("Ignored: conclusion is not 'failure'.");

        var culprit = ResolveCulprit(payload);

        if (culprit == null)
        {
            _logger.LogWarning("Could not determine culprit for failed workflow run.");
            return Ok("Could not resolve culprit.");
        }

        _logger.LogInformation(
            "Culprit resolved: login={Login}, id={Id}", culprit.Login, culprit.Id);

        // Look up user by GitHubId (immutable) first, then by username
        var user = culprit.Id.HasValue
            ? await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == culprit.Id.Value && u.SignalRConnectionId != null)
            : await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == culprit.Login && u.SignalRConnectionId != null);

        if (user == null)
        {
            _logger.LogInformation("User '{Login}' not connected.", culprit.Login);
            return Ok($"User '{culprit.Login}' is not currently connected.");
        }

        var groupName = user.GitHubId.ToString();

        await _hubContext.Clients.Group(groupName).SendAsync("TriggerPunishment", new
        {
            message = $"Workflow failed! Punishment for {culprit.Login}.",
            culprit = culprit.Login,
            runId = workflowRun.GetProperty("id").GetInt64(),
            repo = payload.GetProperty("repository").GetProperty("full_name").GetString()
        });

        _logger.LogInformation("Punishment sent to {Login} (groupId={Group})", culprit.Login, groupName);
        return Ok(new { punished = culprit.Login, gitHubId = user.GitHubId });
    }

    private CulpritInfo? ResolveCulprit(JsonElement payload)
    {
        try
        {
            var run = payload.GetProperty("workflow_run");

            // 1. From pull_requests[0].merged_by (the merger)
            if (run.TryGetProperty("pull_requests", out var prs) && prs.GetArrayLength() > 0)
            {
                var pr = prs[0];

                if (pr.TryGetProperty("merged_by", out var mergedBy))
                {
                    var id = mergedBy.TryGetProperty("id", out var mid) ? mid.GetInt64() : (long?)null;
                    var login = mergedBy.GetProperty("login").GetString()!;
                    return new CulpritInfo(login, id);
                }

                if (pr.TryGetProperty("user", out var prUser))
                {
                    var id = prUser.TryGetProperty("id", out var pid) ? pid.GetInt64() : (long?)null;
                    var login = prUser.GetProperty("login").GetString()!;
                    return new CulpritInfo(login, id);
                }
            }

            // 2. From head_commit.author (pusher)
            if (run.TryGetProperty("head_commit", out var commit) &&
                commit.ValueKind != JsonValueKind.Null &&
                commit.TryGetProperty("author", out var author))
            {
                var username = author.TryGetProperty("username", out var uname)
                    ? uname.GetString()
                    : author.GetProperty("name").GetString();

                if (!string.IsNullOrEmpty(username))
                    return new CulpritInfo(username, null);
            }

            // 3. Fallback: sender of the webhook event
            if (payload.TryGetProperty("sender", out var sender))
            {
                var id = sender.TryGetProperty("id", out var sid) ? sid.GetInt64() : (long?)null;
                var login = sender.GetProperty("login").GetString()!;
                return new CulpritInfo(login, id);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resolving culprit from webhook payload.");
        }

        return null;
    }
}

internal record CulpritInfo(string Login, long? Id);
