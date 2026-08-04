using System.Net;
using System.Net.Http.Json;
using Statefalse.Infrastructure.Data;
using Statefalse.Domain.Models;
using Statefalse.Application;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Statefalse.Api.Tests;

[Collection("BackendIntegration")]
public class AuthControllerTests : IClassFixture<WebApplicationFactory<Program>>, IDisposable
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;
    private readonly SqliteConnection _sqliteConnection;

    private static int _userIdCounter;

    public AuthControllerTests(WebApplicationFactory<Program> factory)
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

        // Create schema
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

    private void Authenticate(long gitHubId, string? username = null)
    {
        _client.DefaultRequestHeaders.Authorization = new("Bearer",
            TestAuth.Token(_factory, gitHubId, username ?? $"u{gitHubId}"));
    }

    [Fact]
    public async Task GetToken_NoAuth_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync("/api/auth/token");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetToken_WithoutUser_ReturnsUnauthorized()
    {
        Authenticate(99999);
        var response = await _client.GetAsync("/api/auth/token");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetToken_WithUserPatToken_ReturnsToken()
    {
        var id = SeedUser(u => u.UserPatToken = "ghp_test_pat_token");
        Authenticate(id);

        var response = await _client.GetAsync("/api/auth/token");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<Dictionary<string, string>>();
        Assert.NotNull(body);
        Assert.Equal("ghp_test_pat_token", body["token"]);
    }

    [Fact]
    public async Task GetToken_FallsBackToAccessToken()
    {
        var id = SeedUser(u => u.AccessToken = "gho_access_token");
        Authenticate(id);

        var response = await _client.GetAsync("/api/auth/token");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<Dictionary<string, string>>();
        Assert.NotNull(body);
        Assert.Equal("gho_access_token", body["token"]);
    }

    [Fact]
    public async Task GetMe_ReturnsUser()
    {
        var id = SeedUser(u =>
        {
            u.GitHubUsername = "meuser";
            u.AvatarUrl = "https://avatars.example.com/me.png";
        });
        Authenticate(id);

        var response = await _client.GetAsync("/api/auth/me");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.NotNull(body);
        Assert.Equal("meuser", body["username"].ToString());
    }

    [Fact]
    public async Task GetMe_NonExistent_ReturnsNotFound()
    {
        Authenticate(999);
        var response = await _client.GetAsync("/api/auth/me");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private long SeedUser(Action<GitHubUser> configure)
    {
        var id = Interlocked.Increment(ref _userIdCounter);
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = new GitHubUser
        {
            GitHubId = id,
            GitHubUsername = $"u{id}",
            CreatedAt = DateTime.UtcNow,
            LastLoginAt = DateTime.UtcNow
        };
        configure(user);
        db.GitHubUsers.Add(user);
        db.SaveChanges();
        return id;
    }
}
