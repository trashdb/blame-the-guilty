using System.Text.Json;
using Statefalse.Api.Contracts;

namespace Statefalse.Api.Services;

/// <summary>
/// Handles a single GitHub webhook event type. Registered in DI and dispatched
/// by <see cref="WebhookService"/> based on the X-GitHub-Event header.
/// </summary>
public interface IWebhookHandler
{
    string EventType { get; }
    Task<ApiResult> HandleAsync(JsonElement payload);
}
