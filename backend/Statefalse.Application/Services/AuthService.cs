using System.Web;
using Microsoft.EntityFrameworkCore;
using Statefalse.Domain.Contracts;
using Statefalse.Application;
using Statefalse.Domain.Models;

namespace Statefalse.Application;

public sealed record AuthCallbackResponse(ApiResult? Error, string? RedirectUrl, object? OkBody);

/// <summary>
/// GitHub OAuth login flow + session endpoints (me, PAT, token resolution).
/// </summary>
public class AuthService
{
    private readonly GitHubOAuthService _oauth;
    private readonly IAppDbContext _db;
    private readonly IConfiguration _configuration;
    private readonly JwtTokenService _jwt;

    public AuthService(GitHubOAuthService oauth, IAppDbContext db, IConfiguration configuration, JwtTokenService jwt)
    {
        _oauth = oauth;
        _db = db;
        _configuration = configuration;
        _jwt = jwt;
    }

    public string LoginUrl(string? redirectUri) => _oauth.GetAuthorizationUrl(redirectUri);

    public async Task<AuthCallbackResponse> HandleCallbackAsync(string code, string? state)
    {
        if (string.IsNullOrEmpty(code))
            return new AuthCallbackResponse(ApiResult.BadRequest("No authorization code provided."), null, null);

        var userInfo = await _oauth.ExchangeCodeForUserInfoAsync(code);
        if (userInfo == null)
            return new AuthCallbackResponse(ApiResult.BadRequest("Failed to authenticate with GitHub."), null, null);

        // Upsert by immutable GitHubId, update username in case it changed
        var existing = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == userInfo.Id);

        if (existing == null)
        {
            _db.GitHubUsers.Add(new GitHubUser
            {
                GitHubId = userInfo.Id,
                GitHubUsername = userInfo.Login,
                AccessToken = userInfo.AccessToken,
                AvatarUrl = userInfo.AvatarUrl,
                CreatedAt = DateTime.UtcNow,
                LastLoginAt = DateTime.UtcNow
            });
        }
        else
        {
            existing.GitHubUsername = userInfo.Login;
            existing.AccessToken = userInfo.AccessToken;
            existing.AvatarUrl = userInfo.AvatarUrl;
            existing.LastLoginAt = DateTime.UtcNow;
        }

        await _db.SaveChangesAsync();

        var token = _jwt.GenerateToken(userInfo.Id, userInfo.Login, userInfo.AvatarUrl);

        // If a redirect_uri was passed via state, redirect there with user info + session token
        if (!string.IsNullOrEmpty(state))
        {
            var avatar = userInfo.AvatarUrl is not null ? $"&avatar={HttpUtility.UrlEncode(userInfo.AvatarUrl)}" : "";
            var redirectUri = $"{state}?id={userInfo.Id}&username={HttpUtility.UrlEncode(userInfo.Login)}{avatar}&token={HttpUtility.UrlEncode(token)}";
            return new AuthCallbackResponse(null, redirectUri, null);
        }

        return new AuthCallbackResponse(null, null, new { id = userInfo.Id, username = userInfo.Login, avatarUrl = userInfo.AvatarUrl, token });
    }

    public async Task<ApiResult> GetUsersAsync()
    {
        var users = await _db.GitHubUsers
            .OrderBy(u => u.GitHubUsername)
            .Select(u => new UserDto(u.GitHubId, u.GitHubUsername, u.AvatarUrl))
            .ToListAsync();
        return ApiResult.Ok(users);
    }

    public async Task<ApiResult> GetMeAsync(long gitHubId)
    {
        var user = await _db.GitHubUsers
            .Where(u => u.GitHubId == gitHubId)
            .Select(u => new { u.GitHubId, u.GitHubUsername, u.AvatarUrl, u.UserPatToken })
            .FirstOrDefaultAsync();

        if (user == null) return ApiResult.NotFound();

        return ApiResult.Ok(new UserProfileDto(user.GitHubId, user.GitHubUsername, user.AvatarUrl, user.UserPatToken != null));
    }

    public async Task<ApiResult> SavePatAsync(long gitHubId, string? patToken)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        if (user == null) return ApiResult.NotFound();

        user.UserPatToken = string.IsNullOrWhiteSpace(patToken) ? null : patToken;
        await _db.SaveChangesAsync();
        return ApiResult.Ok(new { saved = true });
    }

    public async Task<ApiResult> GetTokenAsync(long gitHubId)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        // Mirror the fallback chain used by create-pr / merge so the client can obtain
        // the same token that already works server-side (incl. the shared global PAT).
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return ApiResult.Unauthorized(new { error = "No access token found" });
        return ApiResult.Ok(new TokenDto(token));
    }
}
