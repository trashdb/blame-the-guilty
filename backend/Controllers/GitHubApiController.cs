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

    [HttpPost("interpret")]
    public async Task<IActionResult> InterpretQuery([FromBody] InterpretRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Query))
            return BadRequest(new { error = "Query is required" });

        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == request.GitHubId);
        var oauthToken = user?.AccessToken;
        if (string.IsNullOrEmpty(request.ApiKey) && string.IsNullOrEmpty(oauthToken))
            return BadRequest(new { error = "No API key configured and no OAuth token available. Set an API key in Settings or login with GitHub." });

        var userPrompt = $@"The user typed this natural language query in a developer tool command palette: ""{request.Query}""

Interpret their intent and respond with a JSON object containing:
- ""action"": one of ""createPR"", ""openJiraTicket"", ""openJiraBoard"", ""openRepo"", ""checkoutBranch"", ""openPRs"", ""openSettings"", ""resync"", ""workflowHistory"", ""webhookLog"", ""unknown""
- ""message"": a short confirmation message in Spanish like ""Creando PR desde la rama actual…""
- ""params"": any relevant parameters (repo, branch, ticket number, etc.)

If you cannot determine the action, respond with action ""unknown"" and suggest what the user could try instead.
Only respond with the JSON object, no other text.";

        var systemPrompt = "You are a helpful assistant integrated into a developer tool. Interpret natural language queries and return structured JSON actions.";
        var reply = await CallAI(systemPrompt, userPrompt, request.ApiKey, request.AiProvider, request.Model, oauthToken, maxTokens: 500, temperature: 0.3);

        if (string.IsNullOrEmpty(reply))
            return Ok(new { action = "unknown", message = "Could not interpret query. AI service unavailable." });

        try
        {
            var parsed = JsonSerializer.Deserialize<InterpretResponse>(reply);
            return Ok(parsed ?? new InterpretResponse { Action = "unknown", Message = reply });
        }
        catch
        {
            return Ok(new InterpretResponse { Action = "unknown", Message = reply });
        }
    }

    public class InterpretRequest
    {
        public string Query { get; set; } = "";
        public long GitHubId { get; set; }
        public string? ApiKey { get; set; }
        public string? AiProvider { get; set; }
        public string? Model { get; set; }
    }

    public class InterpretResponse
    {
        public string Action { get; set; } = "";
        public string? Message { get; set; }
        public Dictionary<string, string>? Params { get; set; }
    }

    public class AnalyzeNotesRequest
    {
        public string Content { get; set; } = "";
        public long GitHubId { get; set; }
        public string? ApiKey { get; set; }
        public string? AiProvider { get; set; }
        public string? Model { get; set; }
    }

    public class AnalyzeNotesResponse
    {
        public List<NoteItem> Items { get; set; } = [];
        public string Summary { get; set; } = "";
    }

    public class NoteItem
    {
        public string Type { get; set; } = "note";
        public string Title { get; set; } = "";
        public string Description { get; set; } = "";
        public string? JiraTicketTitle { get; set; }
        public string? Person { get; set; }
        public bool Actionable { get; set; }
        public string? ActionUrl { get; set; }
        public string? ActionLabel { get; set; }
    }

    private async Task<string?> CallAI(string systemPrompt, string userPrompt, string? apiKey, string? provider, string? model, string? oauthToken, int maxTokens = 500, double temperature = 0.3)
    {
        var prov = (provider ?? "openai").ToLower();
        var chosenModel = model;

        switch (prov)
        {
            case "anthropic":
                return await CallAnthropic(systemPrompt, userPrompt, apiKey, chosenModel ?? "claude-sonnet-4-20250514", maxTokens, temperature);
            case "gemini":
                return await CallGemini(systemPrompt, userPrompt, apiKey, chosenModel ?? "gemini-2.5-flash", maxTokens, temperature);
            default:
                // OpenAI-compatible: openai, copilot, or any other
                return await CallOpenAICompatible(systemPrompt, userPrompt, apiKey, prov, chosenModel ?? "gpt-4o", oauthToken, maxTokens, temperature);
        }
    }

    private async Task<string?> CallOpenAICompatible(string systemPrompt, string userPrompt, string? apiKey, string provider, string model, string? oauthToken, int maxTokens, double temperature)
    {
        var messages = new[]
        {
            new { role = "system", content = systemPrompt },
            new { role = "user", content = userPrompt }
        };

        string? token = null;
        string baseUrl;

        if (!string.IsNullOrEmpty(apiKey))
        {
            token = apiKey;
            baseUrl = provider switch
            {
                "copilot" => "https://api.githubcopilot.com",
                _ => "https://api.openai.com/v1"
            };
        }
        else if (!string.IsNullOrEmpty(oauthToken))
        {
            token = oauthToken;
            baseUrl = "https://api.githubcopilot.com";
        }
        else
        {
            return null;
        }

        var body = new
        {
            messages,
            model,
            max_tokens = maxTokens,
            temperature
        };

        var req = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/chat/completions");
        req.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        req.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        try
        {
            var resp = await _client.SendAsync(req);
            if (!resp.IsSuccessStatusCode) return null;
            var content = await resp.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(content);
            if (doc.RootElement.TryGetProperty("choices", out var choices) && choices.ValueKind == JsonValueKind.Array)
            {
                foreach (var choice in choices.EnumerateArray())
                {
                    if (choice.TryGetProperty("message", out var msg) &&
                        msg.TryGetProperty("content", out var text))
                        return text.GetString();
                }
            }
            return null;
        }
        catch
        {
            return null;
        }
    }

    private async Task<string?> CallAnthropic(string systemPrompt, string userPrompt, string? apiKey, string model, int maxTokens, double temperature)
    {
        if (string.IsNullOrEmpty(apiKey)) return null;

        var body = new
        {
            model,
            max_tokens = maxTokens,
            temperature,
            system = systemPrompt,
            messages = new[]
            {
                new { role = "user", content = userPrompt }
            }
        };

        var req = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
        req.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        req.Headers.Add("x-api-key", apiKey);
        req.Headers.Add("anthropic-version", "2023-06-01");
        req.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        try
        {
            var resp = await _client.SendAsync(req);
            if (!resp.IsSuccessStatusCode) return null;
            var content = await resp.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(content);
            if (doc.RootElement.TryGetProperty("content", out var contentArray) && contentArray.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in contentArray.EnumerateArray())
                {
                    if (item.TryGetProperty("type", out var type) && type.GetString() == "text" &&
                        item.TryGetProperty("text", out var text))
                        return text.GetString();
                }
            }
            return null;
        }
        catch
        {
            return null;
        }
    }

    private async Task<string?> CallGemini(string systemPrompt, string userPrompt, string? apiKey, string model, int maxTokens, double temperature)
    {
        if (string.IsNullOrEmpty(apiKey)) return null;

        var body = new
        {
            contents = new[]
            {
                new
                {
                    role = "user",
                    parts = new[]
                    {
                        new { text = $"{systemPrompt}\n\n{userPrompt}" }
                    }
                }
            },
            generationConfig = new
            {
                maxOutputTokens = maxTokens,
                temperature
            }
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}";
        var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.UserAgent.ParseAdd("BlameTheGuilty");
        req.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        try
        {
            var resp = await _client.SendAsync(req);
            if (!resp.IsSuccessStatusCode) return null;
            var content = await resp.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(content);
            if (doc.RootElement.TryGetProperty("candidates", out var candidates) && candidates.ValueKind == JsonValueKind.Array)
            {
                foreach (var candidate in candidates.EnumerateArray())
                {
                    if (candidate.TryGetProperty("content", out var c) &&
                        c.TryGetProperty("parts", out var parts) && parts.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var part in parts.EnumerateArray())
                        {
                            if (part.TryGetProperty("text", out var text))
                                return text.GetString();
                        }
                    }
                }
            }
            return null;
        }
        catch
        {
            return null;
        }
    }

    [HttpPost("analyze-notes")]
    public async Task<IActionResult> AnalyzeNotes([FromBody] AnalyzeNotesRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Content))
            return BadRequest(new { error = "Content is required" });

        var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == request.GitHubId);
        var oauthToken = user?.AccessToken;
        if (string.IsNullOrEmpty(request.ApiKey) && string.IsNullOrEmpty(oauthToken))
            return BadRequest(new { error = "No API key configured and no OAuth token available. Set an API key in Settings or login with GitHub." });

        var userPrompt = $@"Analyze these developer daily notes and extract structured action items. Notes:

""{request.Content}""

Return ONLY a JSON object with this structure (no other text):
{{
  ""items"": [
    {{
      ""type"": ""createTicket"" | ""followUp"" | ""todo"" | ""note"",
      ""title"": ""Short title of the item"",
      ""description"": ""Detailed description"",
      ""jiraTicketTitle"": ""Only if type is createTicket: the suggested ticket title"",
      ""person"": ""Only if type is followUp: the person to follow up with (name or email)"",
      ""actionable"": true or false,
      ""actionUrl"": ""If applicable, a URL to directly execute this action. For createTicket, suggest a Jira create issue URL. For followUp, suggest a Teams chat deep link (msteams://). For other types, a relevant URL if one exists."",
      ""actionLabel"": ""Short button label like 'Open Jira', 'Chat in Teams', 'Open', 'Mark done'""
    }}
  ],
  ""summary"": ""One-line summary of today's notes in Spanish""
}}

IMPORTANT RULES:
- For createTicket: actionUrl should be a Jira URL to create an issue with the title pre-filled. actionLabel = ""Open Jira"".
- For followUp: actionUrl should be a Teams deep link (msteams://) to start a chat with that person. actionLabel = ""Chat in Teams"".
- For todo: actionUrl should be a link to the relevant repo/tool if applicable. actionLabel = ""Open"".
- For note: no action needed (actionable = false).

If nothing actionable is found, return items as an empty array.
Be specific and practical. Extract ticket creation suggestions, people to talk to, and tasks to do. The more specific the action URLs, the better.";

        var systemPrompt = "You are an AI assistant integrated into a developer productivity tool. Your job is to analyze daily notes and extract structured, actionable items.";
        var reply = await CallAI(systemPrompt, userPrompt, request.ApiKey, request.AiProvider, request.Model, oauthToken, maxTokens: 1000, temperature: 0.3);

        if (string.IsNullOrEmpty(reply))
            return Ok(new AnalyzeNotesResponse { Items = [], Summary = "Could not analyze notes." });

        try
        {
            var parsed = JsonSerializer.Deserialize<AnalyzeNotesResponse>(reply);
            return Ok(parsed ?? new AnalyzeNotesResponse { Items = [], Summary = reply });
        }
        catch
        {
            return Ok(new AnalyzeNotesResponse { Items = [], Summary = reply });
        }
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
