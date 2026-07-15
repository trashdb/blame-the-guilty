using System.Net.Http.Headers;
using System.Text;
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
    private readonly ILogger<GitHubApiController> _logger;

    public GitHubApiController(AppDbContext db, IConfiguration configuration, ILogger<GitHubApiController> logger)
    {
        _db = db;
        _configuration = configuration;
        _logger = logger;
    }

    [HttpGet("my-branches")]
    public async Task<IActionResult> GetMyBranches([FromQuery] long gitHubId, [FromQuery] string repo)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No token" });

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

        var myBranches = new List<object>();
        var semaphore = new SemaphoreSlim(10);

        await Parallel.ForEachAsync(branches, async (branch, ct) =>
        {
            var branchName = branch.GetProperty("name").GetString() ?? "";

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

    [HttpPost("create-pr")]
    public async Task<IActionResult> CreatePr([FromQuery] long gitHubId, [FromQuery] string repo,
        [FromQuery] string head, [FromQuery] string baseBranch, [FromQuery] string title, [FromQuery] string? body = null)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No token" });

        _logger.LogInformation("CreatePr: repo={Repo} head={Head} baseBranch={Base} title={Title} gitHubId={Id}",
            repo, head, baseBranch, title, gitHubId);

        var payload = new
        {
            title,
            head,
            @base = baseBranch,
            body = body ?? ""
        };

        var req = new HttpRequestMessage(HttpMethod.Post, $"https://api.github.com/repos/{repo}/pulls");
        req.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        var resp = await _client.SendAsync(req);
        var content = await resp.Content.ReadAsStringAsync();

        _logger.LogInformation("GitHub API responded: status={Status} body={Body}",
            (int)resp.StatusCode, content);

        if (!resp.IsSuccessStatusCode)
        {
            using var doc = JsonDocument.Parse(content);
            var msg = doc.RootElement.TryGetProperty("message", out var m) ? m.GetString() : "Unknown error";

            var detail = msg;
            if (doc.RootElement.TryGetProperty("errors", out var errors) && errors.ValueKind == JsonValueKind.Array)
            {
                foreach (var e in errors.EnumerateArray())
                {
                    if (e.TryGetProperty("message", out var em))
                    {
                        detail = em.GetString() ?? detail;
                        break;
                    }
                }
            }

            _logger.LogWarning("CreatePr failed for repo={Repo} head={Head}: {Status} {Detail}",
                repo, head, (int)resp.StatusCode, detail);

            if (resp.StatusCode == System.Net.HttpStatusCode.UnprocessableEntity &&
                detail?.Contains("already exists", StringComparison.OrdinalIgnoreCase) == true)
            {
                var existingReq = new HttpRequestMessage(
                    HttpMethod.Get,
                    $"https://api.github.com/repos/{repo}/pulls?state=open&per_page=100");
                existingReq.Headers.UserAgent.ParseAdd("BlameTheGuilty");
                existingReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

                var existingResp = await _client.SendAsync(existingReq);
                if (existingResp.IsSuccessStatusCode)
                {
                    var existingContent = await existingResp.Content.ReadAsStringAsync();
                    using var existingDoc = JsonDocument.Parse(existingContent);
                    if (existingDoc.RootElement.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var pr in existingDoc.RootElement.EnumerateArray())
                        {
                            if (pr.TryGetProperty("head", out var h) &&
                                h.TryGetProperty("ref", out var r) &&
                                r.GetString() == head)
                            {
                                var existingUrl = pr.GetProperty("html_url").GetString() ?? "";
                                var existingNumber = pr.GetProperty("number").GetInt64();
                                return Ok(new { prNumber = existingNumber, url = existingUrl, existing = true });
                            }
                        }
                    }
                }
            }

            return StatusCode((int)resp.StatusCode, new { error = detail ?? "Unknown error" });
        }

        using var successDoc = JsonDocument.Parse(content);
        var prUrl = successDoc.RootElement.GetProperty("html_url").GetString() ?? "";
        var prNumber = successDoc.RootElement.GetProperty("number").GetInt64();

        _logger.LogInformation("CreatePr success: pr={PrNumber} url={Url}", prNumber, prUrl);
        return Ok(new { prNumber, url = prUrl });
    }

    [HttpPost("pr-preview")]
    public async Task<IActionResult> PrPreview([FromQuery] long gitHubId, [FromQuery] string repo,
        [FromQuery] string head, [FromQuery] string baseBranch, [FromQuery] string title)
    {
        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);
        var token = user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];
        if (string.IsNullOrEmpty(token))
            return Unauthorized(new { error = "No token" });

        string? template = null;
        var templatePaths = new[]
        {
            ".github/PULL_REQUEST_TEMPLATE.md",
            ".github/pull_request_template.md",
            ".github/pull_request_template.txt",
            "PULL_REQUEST_TEMPLATE.md",
            "pull_request_template.md",
            "docs/PULL_REQUEST_TEMPLATE.md",
            "docs/pull_request_template.md",
            ".github/PULL_REQUEST_TEMPLATE/template.md",
            ".github/PULL_REQUEST_TEMPLATE/default.md"
        };
        foreach (var path in templatePaths)
        {
            template = await FetchFileContent(repo, path, token);
            if (template != null)
            {
                _logger.LogInformation("PrPreview: found template at {Path}", path);
                break;
            }
        }
        if (template == null)
        {
            _logger.LogWarning("PrPreview: no PR template found for repo={Repo}", repo);
        }

        var commits = await GetCommitsBetween(repo, baseBranch, head, token);
        _logger.LogInformation("PrPreview: fetched {Count} commits for {Base}...{Head}", commits.Count, baseBranch, head);

        var summary = "";
        if (user?.AccessToken != null && commits.Count > 0)
        {
            _logger.LogInformation("PrPreview: calling Copilot API for summary");
            summary = await GenerateSummary(commits, user.AccessToken);
            if (string.IsNullOrEmpty(summary))
                _logger.LogWarning("PrPreview: Copilot returned empty summary");
            else
                _logger.LogInformation("PrPreview: Copilot summary generated ({Len} chars)", summary.Length);
        }
        else
        {
            _logger.LogWarning("PrPreview: skipping Copilot (AccessToken={HasToken}, commits={Count})",
                user?.AccessToken != null, commits.Count);
        }

        var ticketMatch = System.Text.RegularExpressions.Regex.Match(head, @"[A-Z]+-\d+");
        var ticketNumber = ticketMatch.Success ? ticketMatch.Value : "";
        var suggestedBody = BuildBody(template, ticketNumber, summary, commits);

        return Ok(new
        {
            template = template ?? "",
            commits,
            summary,
            suggestedBody
        });
    }

    private async Task<string?> FetchFileContent(string repo, string path, string token)
    {
        var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://api.github.com/repos/{repo}/contents/{Uri.EscapeDataString(path)}");
        req.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var resp = await _client.SendAsync(req);
        if (!resp.IsSuccessStatusCode) return null;

        var content = await resp.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(content);
        if (doc.RootElement.TryGetProperty("content", out var contentProp))
        {
            var base64 = contentProp.GetString() ?? "";
            var bytes = Convert.FromBase64String(base64.Trim());
            return Encoding.UTF8.GetString(bytes);
        }
        return null;
    }

    private async Task<List<string>> GetCommitsBetween(string repo, string baseRef, string headRef, string token)
    {
        var encodedBase = Uri.EscapeDataString(baseRef);
        var encodedHead = Uri.EscapeDataString(headRef);
        var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://api.github.com/repos/{repo}/compare/{encodedBase}...{encodedHead}");
        req.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var resp = await _client.SendAsync(req);
        if (!resp.IsSuccessStatusCode) return new List<string>();

        var content = await resp.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(content);
        var result = new List<string>();
        if (doc.RootElement.TryGetProperty("commits", out var commitsProp))
        {
            foreach (var c in commitsProp.EnumerateArray())
            {
                var msg = c.GetProperty("commit").GetProperty("message").GetString() ?? "";
                result.Add(msg.Split('\n')[0]);
            }
        }
        return result;
    }

    private async Task<string> GenerateSummary(List<string> commits, string oauthToken)
    {
        var commitText = string.Join("\n", commits.Select(c => $"- {c}"));
        var prompt = $"Write a detailed PR description summary in English based on these commit messages. Include what was changed and why:\n\n{commitText}\n\nDetailed description:";

        var body = new
        {
            messages = new[]
            {
                new { role = "system", content = "You are a senior developer writing clear, concise PR descriptions for a team codebase. Write in complete paragraphs, explain the context and reasoning behind changes." },
                new { role = "user", content = prompt }
            },
            model = "gpt-4o",
            max_tokens = 1000,
            temperature = 0.7
        };

        var req = new HttpRequestMessage(HttpMethod.Post, "https://api.githubcopilot.com/chat/completions");
        req.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", oauthToken);
        req.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        var resp = await _client.SendAsync(req);
        if (!resp.IsSuccessStatusCode)
        {
            var errBody = await resp.Content.ReadAsStringAsync();
            _logger.LogWarning("Copilot API error: status={Status} body={Body}",
                (int)resp.StatusCode, errBody);
            return "";
        }

        var content = await resp.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(content);
        if (doc.RootElement.TryGetProperty("choices", out var choices) && choices.ValueKind == JsonValueKind.Array)
        {
            foreach (var choice in choices.EnumerateArray())
            {
                if (choice.TryGetProperty("message", out var msg) &&
                    msg.TryGetProperty("content", out var text))
                {
                    return text.GetString() ?? "";
                }
            }
        }
        return "";
    }

    private static string BuildBody(string? template, string ticketNumber, string summary, List<string> commits)
    {
        var body = template ?? "";

        // Strip boilerplate before "## 📝 Description"
        var descIdx = body.IndexOf("## 📝 Description", StringComparison.Ordinal);
        if (descIdx >= 0)
            body = body[descIdx..];
        else
        {
            // Fallback: remove common boilerplate lines
            var lines = body.Split('\n').Where(l =>
                !l.TrimStart().StartsWith("### **PR Title:**") &&
                !l.TrimStart().StartsWith("**Description:**")).ToList();
            body = string.Join("\n", lines);
        }

        if (!string.IsNullOrEmpty(ticketNumber))
        {
            body = body.Replace("[LOY-XXX]", $"[{ticketNumber}]")
                       .Replace("[LOY-000]", $"[{ticketNumber}]")
                       .Replace("[TICKET]", ticketNumber)
                       .Replace("{ticket}", ticketNumber)
                       .Replace("TICKET_NUMBER", ticketNumber);
        }

        if (!string.IsNullOrEmpty(summary))
        {
            body = body.Replace("What change does this PR introduce?", summary);
        }

        return body.Trim();
    }
}
