using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Statefalse.Application;

/// <summary>
/// GitHub webhook entry point: HMAC signature verification, payload parsing and
/// dispatch to the matching <see cref="IWebhookHandler"/> by X-GitHub-Event.
/// </summary>
public class WebhookService
{
    private readonly Dictionary<string, IWebhookHandler> _handlers;
    private readonly IConfiguration _configuration;
    private readonly ILogger<WebhookService> _logger;

    public WebhookService(
        IEnumerable<IWebhookHandler> handlers,
        IConfiguration configuration,
        ILogger<WebhookService> logger)
    {
        _handlers = handlers.ToDictionary(h => h.EventType, h => h, StringComparer.OrdinalIgnoreCase);
        _configuration = configuration;
        _logger = logger;
    }

    public List<WebhookLogEntry> GetLogs(int limit)
        => WebhookLog.GetRecent(limit);

    public async Task<ApiResult> HandleGitHubWebhookAsync(
        string? signatureHeader,
        Func<Task<string>> readRawBody,
        Func<Task<JsonElement?>> readJsonBody,
        string? eventType)
    {
        // Verify HMAC signature if WebhookSecret is configured
        var webhookSecret = _configuration["WebhookSecret"];
        if (!string.IsNullOrEmpty(webhookSecret) && webhookSecret != "set-me-in-env-vars" && webhookSecret != "set-your-github-webhook-secret-here")
        {
            if (string.IsNullOrEmpty(signatureHeader))
            {
                WebhookLog.Log("unknown", null, null, null, "rejected", "Missing X-Hub-Signature-256");
                return ApiResult.Unauthorized("Missing X-Hub-Signature-256");
            }

            var rawBody = await readRawBody();
            var key = Encoding.UTF8.GetBytes(webhookSecret);
            var hash = HMACSHA256.HashData(key, Encoding.UTF8.GetBytes(rawBody));
            var expected = "sha256=" + Convert.ToHexString(hash).ToLowerInvariant();

            if (!CryptographicOperations.FixedTimeEquals(
                    Encoding.UTF8.GetBytes(signatureHeader),
                    Encoding.UTF8.GetBytes(expected)))
            {
                WebhookLog.Log("unknown", null, null, null, "rejected", "Invalid webhook signature");
                return ApiResult.Unauthorized("Invalid signature");
            }
        }

        var payload = await readJsonBody();
        if (payload is not { } body)
            return ApiResult.BadRequest("Invalid JSON payload");

        if (_handlers.TryGetValue(eventType ?? "", out var handler))
            return await handler.HandleAsync(body);

        WebhookLog.Log(eventType ?? "unknown", null, TryGetRepo(body), null, "ignored", "Unsupported event type");
        return ApiResult.Ok($"Ignored: unsupported event '{eventType}'.");
    }

    private static string? TryGetRepo(JsonElement payload)
    {
        if (payload.TryGetProperty("repository", out var repo) &&
            repo.TryGetProperty("full_name", out var name))
            return name.GetString();
        return null;
    }
}
