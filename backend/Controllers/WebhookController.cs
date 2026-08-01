using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Statefalse.Api.Services;

namespace Statefalse.Api.Controllers;

[ApiController]
[Route("api/webhook")]
public class WebhookController : ControllerBase
{
    private readonly WebhookService _service;

    public WebhookController(WebhookService service)
    {
        _service = service;
    }

    [HttpGet("logs")]
    public IActionResult GetLogs([FromQuery] int limit = 30)
        => Ok(_service.GetLogs(limit));

    [HttpPost("github")]
    [EnableRateLimiting("webhook")]
    public async Task<IActionResult> HandleGitHubWebhook()
    {
        var signature = Request.Headers["X-Hub-Signature-256"].FirstOrDefault();
        var eventType = Request.Headers["X-GitHub-Event"].FirstOrDefault() ?? "";

        Request.EnableBuffering();
        var result = await _service.HandleGitHubWebhookAsync(
            signatureHeader: signature,
            readRawBody: async () =>
            {
                var body = await new StreamReader(Request.Body).ReadToEndAsync();
                Request.Body.Position = 0;
                return body;
            },
            readJsonBody: async () =>
            {
                var payload = await JsonSerializer.DeserializeAsync<JsonElement>(Request.Body);
                return payload;
            },
            eventType: eventType);

        return new ObjectResult(result.Value) { StatusCode = result.StatusCode };
    }
}
