using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Statefalse.Infrastructure.Data;
using Statefalse.Domain.Models;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Statefalse.Api.Tests;

[CollectionDefinition("BackendIntegration", DisableParallelization = true)]
public class BackendIntegrationCollection { }

[Collection("BackendIntegration")]
public class ControllersTests : IClassFixture<WebApplicationFactory<Program>>, IDisposable
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;
    private readonly SqliteConnection _sqliteConnection;
    private static int _counter;

    public ControllersTests(WebApplicationFactory<Program> factory)
    {
        _sqliteConnection = new SqliteConnection("DataSource=:memory:");
        _sqliteConnection.Open();

        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.UseSetting("Jwt:Secret", TestAuth.Secret);
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<AppDbContext>>();
                services.RemoveAll<AppDbContext>();
                services.AddDbContext<AppDbContext>(options =>
                    options.UseSqlite(_sqliteConnection));
            });
        });

        _client = _factory.CreateClient();

        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.Database.EnsureCreated();
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
        _sqliteConnection.Close();
        _sqliteConnection.Dispose();
    }

    private HttpClient AuthClient(long gitHubId)
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer",
            TestAuth.Token(_factory, gitHubId, $"user{gitHubId}"));
        return client;
    }

    private long SeedUser(Action<GitHubUser>? configure = null)
    {
        var id = Interlocked.Increment(ref _counter) + 1000L;
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = new GitHubUser
        {
            GitHubId = id,
            GitHubUsername = $"user{id}",
            CreatedAt = DateTime.UtcNow,
            LastLoginAt = DateTime.UtcNow,
            UserPatToken = "ghp_test_token_" + id
        };
        configure?.Invoke(user);
        db.GitHubUsers.Add(user);
        db.SaveChanges();
        return id;
    }

    // ───────────── Health ─────────────

    [Fact]
    public async Task Health_ReturnsOk()
    {
        var response = await _client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.NotNull(body);
        Assert.Contains("status", body!.Keys);
        Assert.Contains("database", body.Keys);
    }

    // ───────────── OpenAPI / Swagger ─────────────

    [Fact]
    public async Task OpenApiEndpoint_ReturnsJson()
    {
        var response = await _client.GetAsync("/openapi/v1.json");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("application/json", response.Content.Headers.ContentType?.ToString() ?? "");
    }

    // ───────────── Auth guard ─────────────

    [Fact]
    public async Task ProtectedEndpoints_WithoutBearer_ReturnsUnauthorized()
    {
        var responses = await Task.WhenAll(
            _client.GetAsync("/api/users"),
            _client.GetAsync("/api/punishments"),
            _client.GetAsync("/api/webhook/logs"),
            _client.GetAsync("/api/workflows/runs"),
            _client.GetAsync("/api/pullrequests/active"));
        foreach (var r in responses)
            Assert.Equal(HttpStatusCode.Unauthorized, r.StatusCode);
    }

    [Fact]
    public async Task ProtectedEndpoints_WithInvalidToken_ReturnsUnauthorized()
    {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", "not-a-valid-token");
        var response = await client.GetAsync("/api/users");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ───────────── Users ─────────────

    [Fact]
    public async Task GetUsers_Empty_ReturnsEmptyList()
    {
        var client = AuthClient(1001);
        var response = await client.GetAsync("/api/users");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var users = await response.Content.ReadFromJsonAsync<List<Dictionary<string, object>>>();
        Assert.NotNull(users);
    }

    [Fact]
    public async Task GetUsers_WithData_ReturnsUsers()
    {
        SeedUser();
        SeedUser();

        var client = AuthClient(1001);
        var response = await client.GetAsync("/api/users");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var users = await response.Content.ReadFromJsonAsync<List<Dictionary<string, object>>>();
        Assert.NotNull(users);
        Assert.True(users!.Count >= 2);
    }

    // ───────────── Punishments ─────────────

    [Fact]
    public async Task GetPunishments_Empty_ReturnsEmptyList()
    {
        var client = AuthClient(1001);
        var response = await client.GetAsync("/api/punishments?days=7&limit=50");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var events = await response.Content.ReadFromJsonAsync<List<Dictionary<string, object>>>();
        Assert.NotNull(events);
        Assert.Empty(events!);
    }

    [Fact]
    public async Task GetPunishments_WithData_ReturnsEvents()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.PunishmentEvents.Add(new PunishmentEvent
        {
            RunId = 1, CulpritLogin = "testuser", RepoFullName = "owner/repo",
            WorkflowName = "CI", OccurredAt = DateTime.UtcNow
        });
        db.SaveChanges();

        var client = AuthClient(1001);
        var response = await client.GetAsync("/api/punishments?days=7&limit=50");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var events = await response.Content.ReadFromJsonAsync<List<JsonElement>>();
        Assert.NotNull(events);
        Assert.Single(events!);
        Assert.Equal("testuser", events![0].GetProperty("culpritLogin").GetString());
    }

    [Fact]
    public async Task GetPunishmentsSummary_ReturnsRankings()
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.PunishmentEvents.Add(new PunishmentEvent
        {
            RunId = 1, CulpritLogin = "culpritA", RepoFullName = "org/repo1",
            WorkflowName = "CI", OccurredAt = DateTime.UtcNow
        });
        db.PunishmentEvents.Add(new PunishmentEvent
        {
            RunId = 2, CulpritLogin = "culpritA", RepoFullName = "org/repo1",
            WorkflowName = "CI", OccurredAt = DateTime.UtcNow
        });
        db.PunishmentEvents.Add(new PunishmentEvent
        {
            RunId = 3, CulpritLogin = "culpritB", RepoFullName = "org/repo2",
            WorkflowName = "Tests", OccurredAt = DateTime.UtcNow
        });
        db.SaveChanges();

        var client = AuthClient(1001);
        var response = await client.GetAsync("/api/punishments/summary?days=7");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.True(body.TryGetProperty("topCulprits", out var culprits));
        Assert.True(body.TryGetProperty("topWorkflows", out var workflows));
        Assert.True(body.TryGetProperty("topRepos", out var repos));
    }

    // ───────────── Webhook Logs ─────────────

    [Fact]
    public async Task GetWebhookLogs_ReturnsList()
    {
        var client = AuthClient(1001);
        var response = await client.GetAsync("/api/webhook/logs?limit=10");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var logs = await response.Content.ReadFromJsonAsync<List<Dictionary<string, object>>>();
        Assert.NotNull(logs);
    }

    // ───────────── Auth ─────────────

    [Fact]
    public async Task GetAuthLogin_Redirects()
    {
        var noRedirectClient = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
        var response = await noRedirectClient.GetAsync("/api/auth/login");
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
    }

    [Fact]
    public async Task GetAuthCallback_NoCode_ReturnsBadRequest()
    {
        var response = await _client.GetAsync("/api/auth/callback");
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task SavePat_NoUser_ReturnsNotFound()
    {
        var client = AuthClient(999999);
        var content = JsonContent.Create(new { patToken = "ghp_new_token" });
        var response = await client.PostAsync("/api/auth/pat", content);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task SavePat_SavesToken()
    {
        var id = SeedUser(u => u.UserPatToken = null);
        var client = AuthClient(id);

        var content = JsonContent.Create(new { patToken = "ghp_new_pat" });
        var response = await client.PostAsync("/api/auth/pat", content);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        // Verify token was saved
        var tokenResponse = await client.GetAsync("/api/auth/token");
        var tokenBody = await tokenResponse.Content.ReadFromJsonAsync<Dictionary<string, string>>();
        Assert.NotNull(tokenBody);
        Assert.Equal("ghp_new_pat", tokenBody!["token"]);
    }

    // ───────────── Workflows ─────────────

    [Fact]
    public async Task GetWorkflowRuns_Empty_ReturnsEmptyList()
    {
        var id = SeedUser();
        var client = AuthClient(id);
        var response = await client.GetAsync("/api/workflows/runs?limit=20");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var runs = await response.Content.ReadFromJsonAsync<List<Dictionary<string, object>>>();
        Assert.NotNull(runs);
        Assert.Empty(runs!);
    }

    [Fact]
    public async Task GetWorkflowRuns_WithData_ReturnsRuns()
    {
        var id = SeedUser();
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.WorkflowRuns.Add(new WorkflowRun
        {
            RunId = 100, GitHubId = id, WorkflowName = "CI", Repo = "org/repo",
            Actor = "user", Status = "in_progress", StartedAt = DateTime.UtcNow
        });
        db.SaveChanges();

        var client = AuthClient(id);
        var response = await client.GetAsync("/api/workflows/runs?limit=20");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var runs = await response.Content.ReadFromJsonAsync<List<JsonElement>>();
        Assert.NotNull(runs);
        Assert.NotEmpty(runs!);
        Assert.Equal("CI", runs![0].GetProperty("workflowName").GetString());
    }

    [Fact]
    public async Task SetWorkflowTarget_NoRun_ReturnsNotFound()
    {
        var client = AuthClient(1001);
        var body = JsonContent.Create(new { targetGitHubIds = new long[] { 1, 2 } });
        var response = await client.PutAsync("/api/workflows/runs/9999/target", body);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task SetWorkflowTarget_SavesTargets()
    {
        var id = SeedUser();
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        db.WorkflowRuns.Add(new WorkflowRun
        {
            RunId = 200, GitHubId = id, WorkflowName = "CI", Repo = "org/repo",
            Actor = "user", Status = "in_progress", StartedAt = DateTime.UtcNow
        });
        db.SaveChanges();
        var runId = db.WorkflowRuns.First().Id;

        var client = AuthClient(id);
        var body = JsonContent.Create(new { targetGitHubIds = new long[] { 42, 99 } });
        var response = await client.PutAsync($"/api/workflows/runs/{runId}/target", body);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(200, result.GetProperty("runId").GetInt64());
    }

    // ───────────── PullRequests ─────────────

    [Fact]
    public async Task GetActivePRs_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync("/api/pullrequests/active");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetActivePRs_WithAuth_ReturnsOk()
    {
        var id = SeedUser();
        var client = AuthClient(id);
        var response = await client.GetAsync("/api/pullrequests/active");
        // Returns empty list since no PRs exist (GitHub API calls may fail but
        // the endpoint returns 200 with partial data)
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task GetPRDetail_NoPR_ReturnsPartialData()
    {
        var id = SeedUser();
        var client = AuthClient(id);
        var response = await client.GetAsync("/api/pullrequests/999999/detail?repo=org/repo");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task MergePR_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.PostAsync("/api/pullrequests/1/merge?repo=org/repo&method=squash", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task UpdateBranch_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.PostAsync("/api/pullrequests/1/update-branch?repo=org/repo", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetPRCommits_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync("/api/pullrequests/1/commits?repo=org/repo");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetPRFiles_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync("/api/pullrequests/1/files?repo=org/repo");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetPRChecks_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync("/api/pullrequests/1/checks?repo=org/repo");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task SetDraft_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.PostAsync("/api/pullrequests/1/draft?repo=org/repo&draft=true", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ───────────── GitHub API Proxy ─────────────

    [Fact]
    public async Task GetMyBranches_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync("/api/github/my-branches?repo=org/repo");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task CreatePR_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.PostAsync(
            "/api/github/create-pr?repo=org/repo&head=feature/test&baseBranch=main&title=Test", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task PRPreview_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.PostAsync(
            "/api/github/pr-preview?repo=org/repo&head=feature/test&baseBranch=main&title=Test", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    // ───────────── Workflows (GitHub-dependent) ─────────────

    [Fact]
    public async Task SyncActive_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.PostAsync("/api/workflows/sync-active", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task RerunRun_NoRun_ReturnsNotFound()
    {
        var id = SeedUser();
        var client = AuthClient(id);
        var response = await client.PostAsync("/api/workflows/runs/999999/rerun", null);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ───────────── Interpret ─────────────

    [Fact]
    public async Task Interpret_NoAuth_ReturnsUnauthorized()
    {
        var body = JsonContent.Create(new { query = "create pr" });
        var response = await _client.PostAsync("/api/github/interpret", body);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Interpret_NoQuery_ReturnsBadRequest()
    {
        var id = SeedUser();
        var client = AuthClient(id);
        var body = JsonContent.Create(new { });
        var response = await client.PostAsync("/api/github/interpret", body);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Interpret_NoApiKeyOrToken_ReturnsBadRequest()
    {
        var id = SeedUser(u => u.AccessToken = null);
        var client = AuthClient(id);
        var body = JsonContent.Create(new { query = "create pr" });
        var response = await client.PostAsync("/api/github/interpret", body);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
