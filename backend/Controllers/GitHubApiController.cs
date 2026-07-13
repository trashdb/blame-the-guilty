using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BlameTheGuilty.Api.Data;

namespace BlameTheGuilty.Api.Controllers;

[ApiController]
[Route("api/github")]
public class GitHubApiController : ControllerBase
{
    private static readonly HttpClient _client = new();
    private readonly AppDbContext _db;
    private readonly IConfiguration _configuration;

    public GitHubApiController(AppDbContext db, IConfiguration configuration)
    {
        _db = db;
        _configuration = configuration;
    }

    [HttpGet("my-branches")]
    public async Task<IActionResult> GetMyBranches([FromQuery] long gitHubId, [FromQuery] string repo)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No token" });

        var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{repo}/branches?per_page=100");
        request.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var response = await _client.SendAsync(request);
        if (!response.IsSuccessStatusCode)
            return StatusCode((int)response.StatusCode, new { error = "GitHub API error" });

        var content = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(content);
        var branches = doc.RootElement.EnumerateArray();

        var myBranches = new List<object>();
        foreach (var branch in branches)
        {
            var branchName = branch.GetProperty("name").GetString() ?? "";
            var authorLogin = branch.GetProperty("commit").GetProperty("author").GetProperty("login").GetString();

            if (!string.Equals(authorLogin, user?.GitHubUsername, StringComparison.OrdinalIgnoreCase))
                continue;

            myBranches.Add(new { name = branchName });
        }

        return Ok(myBranches);
    }
}
