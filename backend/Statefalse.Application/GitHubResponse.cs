using System.Text.Json;

namespace Statefalse.Application;

public sealed record GitHubResponse(int StatusCode, JsonElement? Body);
