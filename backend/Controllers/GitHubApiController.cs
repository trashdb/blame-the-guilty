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
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No token" });

        // 1. List all branches
        var listReq = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{repo}/branches?per_page=100");
        listReq.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        listReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var listResp = await _client.SendAsync(listReq);
        if (!listResp.IsSuccessStatusCode)
            return StatusCode((int)listResp.StatusCode, new { error = "GitHub API error" });

        var content = await listResp.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(content);
        var branches = doc.RootElement.EnumerateArray();
        var username = user?.GitHubUsername ?? "";

        // 2. For each branch, fetch details to get the author login
        var myBranches = new List<object>();
        var semaphore = new SemaphoreSlim(10);

        await Parallel.ForEachAsync(branches, async (branch, ct) =>
        {
            var branchName = branch.GetProperty("name").GetString() ?? "";

            // Skip dependabot branches
            if (branchName.StartsWith("dependabot/"))
                return;

            await semaphore.WaitAsync(ct);
            try
            {
                var detailReq = new HttpRequestMessage(
                    HttpMethod.Get,
                    $"https://api.github.com/repos/{repo}/branches/{branchName}");
                detailReq.Headers.UserAgent.ParseAdd("BlameTheGuilty");
                detailReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

                var detailResp = await _client.SendAsync(detailReq, ct);
                if (!detailResp.IsSuccessStatusCode) return;

                var detailContent = await detailResp.Content.ReadAsStringAsync(ct);
                using var detailDoc = JsonDocument.Parse(detailContent);

                var authorLogin = detailDoc.RootElement
                    .GetProperty("commit")
                    .GetProperty("author")
                    .GetProperty("login")
                    .GetString();

                if (string.Equals(authorLogin, username, StringComparison.OrdinalIgnoreCase))
                {
                    lock (myBranches)
                    {
                        myBranches.Add(new { name = branchName });
                    }
                }
            }
            finally
            {
                semaphore.Release();
            }
        });

        return Ok(myBranches);
    }
}
