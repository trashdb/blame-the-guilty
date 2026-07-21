using System.Web;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;
using BlameTheGuilty.Api.Models;
using BlameTheGuilty.Api.Services;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly GitHubOAuthService _oauth;
    private readonly AppDbContext _db;
    private readonly IConfiguration _configuration;

    public AuthController(GitHubOAuthService oauth, AppDbContext db, IConfiguration configuration)
    {
        _oauth = oauth;
        _db = db;
        _configuration = configuration;
    }

    [HttpGet("login")]
    public IActionResult Login([FromQuery] string? redirect_uri = null)
    {
        var url = _oauth.GetAuthorizationUrl(redirect_uri);
        return Redirect(url);
    }

    [HttpGet("callback")]
    public async Task<IActionResult> Callback(
        [FromQuery] string code,
        [FromQuery] string? state = null)
    {
        if (string.IsNullOrEmpty(code))
            return BadRequest("No authorization code provided.");

        var userInfo = await _oauth.ExchangeCodeForUserInfoAsync(code);

        if (userInfo == null)
            return BadRequest("Failed to authenticate with GitHub.");

        // Upsert by immutable GitHubId, update username in case it changed
        var existing = await _db.GitHubUsers
            .FirstOrDefaultAsync(u => u.GitHubId == userInfo.Id);

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

        // If a redirect_uri was passed via state, redirect there with user info
        if (!string.IsNullOrEmpty(state))
        {
            var avatar = userInfo.AvatarUrl is not null ? $"&avatar={HttpUtility.UrlEncode(userInfo.AvatarUrl)}" : "";
            var redirectUri = $"{state}?id={userInfo.Id}&username={HttpUtility.UrlEncode(userInfo.Login)}{avatar}";
            return Redirect(redirectUri);
        }

        return Ok(new { id = userInfo.Id, username = userInfo.Login, avatarUrl = userInfo.AvatarUrl });
    }

    [HttpGet("me")]
    public async Task<IActionResult> GetMe([FromQuery] long gitHubId)
    {
        var user = await _db.GitHubUsers
            .Where(u => u.GitHubId == gitHubId)
            .Select(u => new { u.GitHubId, u.GitHubUsername, u.AvatarUrl, u.UserPatToken })
            .FirstOrDefaultAsync();

        if (user == null) return NotFound();

        return Ok(new { id = user.GitHubId, username = user.GitHubUsername, avatarUrl = user.AvatarUrl, hasPat = user.UserPatToken != null });
    }

    [HttpPost("pat")]
    public async Task<IActionResult> SavePat([FromQuery] long gitHubId, [FromBody] PatRequest body)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        if (user == null) return NotFound();

        user.UserPatToken = string.IsNullOrWhiteSpace(body.PatToken) ? null : body.PatToken;
        await _db.SaveChangesAsync();
        return Ok(new { saved = true });
    }

    [HttpGet("token")]
    public async Task<IActionResult> GetToken([FromQuery] long gitHubId)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        // Mirror the fallback chain used by create-pr / merge so the client can obtain
        // the same token that already works server-side (incl. the shared global PAT).
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No access token found" });
        return Ok(new { token });
    }
}

public class PatRequest
{
    public string? PatToken { get; set; }
}
