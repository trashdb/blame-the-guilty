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

    public AuthController(GitHubOAuthService oauth, AppDbContext db)
    {
        _oauth = oauth;
        _db = db;
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

        // Upsert by immutable GitHubId, update username + access token
        var existing = await _db.GitHubUsers
            .FirstOrDefaultAsync(u => u.GitHubId == userInfo.Id);

        if (existing == null)
        {
            _db.GitHubUsers.Add(new GitHubUser
            {
                GitHubId = userInfo.Id,
                GitHubUsername = userInfo.Login,
                AccessToken = userInfo.AccessToken,
                CreatedAt = DateTime.UtcNow,
                LastLoginAt = DateTime.UtcNow
            });
        }
        else
        {
            existing.GitHubUsername = userInfo.Login;
            existing.AccessToken = userInfo.AccessToken;
            existing.LastLoginAt = DateTime.UtcNow;
        }

        await _db.SaveChangesAsync();

        // If a redirect_uri was passed via state, redirect there with user info
        if (!string.IsNullOrEmpty(state))
        {
            var redirectUri = $"{state}?id={userInfo.Id}&username={HttpUtility.UrlEncode(userInfo.Login)}";
            return Redirect(redirectUri);
        }

        return Ok(new { id = userInfo.Id, username = userInfo.Login });
    }
}
