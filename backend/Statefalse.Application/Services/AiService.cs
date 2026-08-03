using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Statefalse.Domain.Contracts;

namespace Statefalse.Application;

/// <summary>
/// AI provider orchestration (OpenAI-compatible / Copilot / Anthropic / Gemini)
/// plus the helpers used to build PR previews (template fetch, commit listing,
/// Copilot summary, body assembly).
/// </summary>
public class AiService
{
    private static readonly HttpClient _client = new() { Timeout = TimeSpan.FromSeconds(30) };
    private readonly IGitHubClient _github;
    private readonly ILogger<AiService> _logger;

    public AiService(IGitHubClient github, ILogger<AiService> logger)
    {
        _github = github;
        _logger = logger;
    }

    // ─────────────────────────── Interpret ───────────────────────────

    public async Task<object> InterpretQueryAsync(InterpretRequest request, string? oauthToken)
    {
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
            return new { action = "unknown", message = "Could not interpret query. AI service unavailable." };

        try
        {
            var parsed = JsonSerializer.Deserialize<InterpretResponse>(reply);
            return parsed ?? new InterpretResponse { Action = "unknown", Message = reply };
        }
        catch
        {
            return new InterpretResponse { Action = "unknown", Message = reply };
        }
    }

    // ─────────────────────────── PR preview ───────────────────────────

    public async Task<PrPreviewResult> BuildPreviewAsync(string repo, string baseBranch, string head, string title, bool useAI, string? oauthToken)
    {
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
            template = await FetchFileContent(repo, path, oauthToken);
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

        var commits = await GetCommitsBetween(repo, baseBranch, head, oauthToken);
        _logger.LogInformation("PrPreview: fetched {Count} commits for {Base}...{Head}", commits.Count, baseBranch, head);

        var summary = "";
        string? summaryError = null;
        if (useAI && commits.Count > 0)
        {
            if (!string.IsNullOrEmpty(oauthToken))
            {
                _logger.LogInformation("PrPreview: calling Copilot API for summary (oauthToken present)");
                summary = await GenerateSummary(commits, oauthToken);
                if (string.IsNullOrEmpty(summary))
                {
                    summaryError = "Copilot API returned empty response. Token may be expired — re-login to GitHub.";
                    _logger.LogWarning("PrPreview: Copilot returned empty summary (token prefix={Prefix})", oauthToken[..Math.Min(8, oauthToken.Length)]);
                }
                else
                    _logger.LogInformation("PrPreview: Copilot summary generated ({Len} chars)", summary.Length);
            }
            else
            {
                summaryError = "No OAuth token available. Login to GitHub to enable Copilot summaries.";
                _logger.LogWarning("PrPreview: no OAuth token for Copilot");
            }
        }

        var ticketMatch = System.Text.RegularExpressions.Regex.Match(head, @"[A-Z]+-\d+");
        var ticketNumber = ticketMatch.Success ? ticketMatch.Value : "";
        var suggestedBody = BuildBody(template, ticketNumber, summary, commits);

        return new PrPreviewResult(template ?? "", commits, summary, suggestedBody, summaryError);
    }

    // ─────────────────────────── AI providers ───────────────────────────

    public async Task<string?> CallAI(string systemPrompt, string userPrompt, string? apiKey, string? provider, string? model, string? oauthToken, int maxTokens = 500, double temperature = 0.3)
    {
        var prov = (provider ?? "openai").ToLower();
        var chosenModel = model;

        return prov switch
        {
            "anthropic" => await CallAnthropic(systemPrompt, userPrompt, apiKey, chosenModel ?? "claude-sonnet-4-20250514", maxTokens, temperature),
            "gemini" => await CallGemini(systemPrompt, userPrompt, apiKey, chosenModel ?? "gemini-2.5-flash", maxTokens, temperature),
            _ => await CallOpenAICompatible(systemPrompt, userPrompt, apiKey, prov, chosenModel ?? "gpt-4o", oauthToken, maxTokens, temperature)
        };
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
        req.Headers.UserAgent.ParseAdd("Statefalse");
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
        req.Headers.UserAgent.ParseAdd("Statefalse");
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
        req.Headers.UserAgent.ParseAdd("Statefalse");
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

    // ─────────────────────────── helpers ───────────────────────────

    public async Task<string?> FetchFileContent(string repo, string path, string? token)
    {
        if (string.IsNullOrEmpty(token)) return null;
        var resp = await _github.GetAsync($"/repos/{repo}/contents/{Uri.EscapeDataString(path)}", token);
        if (resp.StatusCode is < 200 or >= 300 || resp.Body is not { } doc) return null;

        if (doc.TryGetProperty("content", out var contentProp))
        {
            var base64 = contentProp.GetString() ?? "";
            var bytes = Convert.FromBase64String(base64.Trim());
            return Encoding.UTF8.GetString(bytes);
        }
        return null;
    }

    public async Task<List<string>> GetCommitsBetween(string repo, string baseRef, string headRef, string? token)
    {
        if (string.IsNullOrEmpty(token)) return [];
        var encodedBase = Uri.EscapeDataString(baseRef);
        var encodedHead = Uri.EscapeDataString(headRef);
        var resp = await _github.GetAsync($"/repos/{repo}/compare/{encodedBase}...{encodedHead}", token);
        if (resp.StatusCode is < 200 or >= 300 || resp.Body is not { } doc) return [];

        var result = new List<string>();
        if (doc.TryGetProperty("commits", out var commitsProp))
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
        try
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
            req.Headers.UserAgent.ParseAdd("Statefalse");
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", oauthToken);
            req.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            var resp = await _client.SendAsync(req, cts.Token);
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
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Copilot summary generation failed (timeout or error)");
            return "";
        }
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

public sealed record PrPreviewResult(
    string Template,
    List<string> Commits,
    string Summary,
    string SuggestedBody,
    string? SummaryError);
