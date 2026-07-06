using System.Text.Json;
using Microsoft.Extensions.Options;

namespace BlameTheGuilty.Api.Services;

public class GitHubOAuthOptions
{
    public string ClientId { get; set; } = string.Empty;
    public string ClientSecret { get; set; } = string.Empty;
    public string RedirectUri { get; set; } = string.Empty;
}

public class GitHubOAuthService
{
    private readonly HttpClient _httpClient;
    private readonly GitHubOAuthOptions _options;

    public GitHubOAuthService(HttpClient httpClient, IOptions<GitHubOAuthOptions> options)
    {
        _httpClient = httpClient;
        _options = options.Value;
    }

    public string GetAuthorizationUrl(string? redirectUri = null)
    {
        var state = !string.IsNullOrEmpty(redirectUri)
            ? Uri.EscapeDataString(redirectUri)
            : string.Empty;

        return $"https://github.com/login/oauth/authorize?client_id={_options.ClientId}&redirect_uri={_options.RedirectUri}&scope=read:user,repo&state={state}";
    }

    public async Task<GitHubUserInfo?> ExchangeCodeForUserInfoAsync(string code)
    {
        // Exchange code for access token
        var tokenRequest = new Dictionary<string, string>
        {
            ["client_id"] = _options.ClientId,
            ["client_secret"] = _options.ClientSecret,
            ["code"] = code,
            ["redirect_uri"] = _options.RedirectUri
        };

        var tokenResponse = await _httpClient.PostAsync(
            "https://github.com/login/oauth/access_token",
            new FormUrlEncodedContent(tokenRequest));

        tokenResponse.EnsureSuccessStatusCode();

        var tokenContent = await tokenResponse.Content.ReadAsStringAsync();
        var queryParams = System.Web.HttpUtility.ParseQueryString(tokenContent);
        var accessToken = queryParams["access_token"];

        if (string.IsNullOrEmpty(accessToken))
            return null;

        // Get user info with the token (using per-request headers, not shared DefaultRequestHeaders)
        using var userRequest = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/user");
        userRequest.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        userRequest.Headers.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);

        var userResponse = await _httpClient.SendAsync(userRequest);
        userResponse.EnsureSuccessStatusCode();

        var userContent = await userResponse.Content.ReadAsStringAsync();
        var userData = JsonSerializer.Deserialize<JsonElement>(userContent);

        return new GitHubUserInfo(
            Id: userData.GetProperty("id").GetInt64(),
            Login: userData.GetProperty("login").GetString()!,
            AccessToken: accessToken
        );
    }
}

public record GitHubUserInfo(long Id, string Login, string AccessToken);
