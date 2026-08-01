using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Statefalse.Api.Services;

public sealed record GitHubResponse(int StatusCode, JsonElement? Body);

/// <summary>
/// Thin typed client over the GitHub REST/GraphQL APIs. Always attaches the
/// Statefalse User-Agent and Bearer token when provided. A <see cref="StatusCode"/>
/// of 0 means the request threw (network/timeout) — callers map to 502.
/// </summary>
public sealed class GitHubClient
{
    private const string ApiBase = "https://api.github.com";
    private const string UserAgent = "Statefalse";

    private readonly HttpClient _http;

    public GitHubClient(HttpClient http)
    {
        _http = http;
        _http.Timeout = TimeSpan.FromSeconds(30);
    }

    public Task<GitHubResponse> GetAsync(string path, string? token = null, CancellationToken ct = default)
        => SendAsync(HttpMethod.Get, $"{ApiBase}{path}", token, null, ct);

    public Task<GitHubResponse> PostAsync(string path, string? token, object? body = null, CancellationToken ct = default)
        => SendAsync(HttpMethod.Post, $"{ApiBase}{path}", token, body, ct);

    public Task<GitHubResponse> PutAsync(string path, string? token, object? body = null, CancellationToken ct = default)
        => SendAsync(HttpMethod.Put, $"{ApiBase}{path}", token, body, ct);

    public Task<GitHubResponse> GraphQlAsync(string query, string? token, CancellationToken ct = default)
        => SendAsync(HttpMethod.Post, $"{ApiBase}/graphql", token, new { query }, ct);

    private async Task<GitHubResponse> SendAsync(HttpMethod method, string url, string? token, object? body, CancellationToken ct)
    {
        HttpContent? content = body switch
        {
            null => null,
            string s => new StringContent(s, Encoding.UTF8, "application/json"),
            _ => new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
        };

        var req = new HttpRequestMessage(method, url);
        req.Headers.UserAgent.ParseAdd(UserAgent);
        if (!string.IsNullOrEmpty(token))
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (content != null)
            req.Content = content;

        try
        {
            var resp = await _http.SendAsync(req, ct);
            var text = await resp.Content.ReadAsStringAsync(ct);
            JsonElement? json = null;
            if (!string.IsNullOrWhiteSpace(text))
            {
                try { json = JsonSerializer.Deserialize<JsonElement>(text); }
                catch (JsonException) { /* non-JSON body */ }
            }
            return new GitHubResponse((int)resp.StatusCode, json);
        }
        catch
        {
            return new GitHubResponse(0, null);
        }
    }
}
