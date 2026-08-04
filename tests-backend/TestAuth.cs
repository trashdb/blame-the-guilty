using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Statefalse.Application;

namespace Statefalse.Api.Tests;

/// <summary>
/// Shared JWT test-secret + token helper for integration tests.
/// </summary>
public static class TestAuth
{
    public const string Secret = "test-secret-key-0123456789abcdef0123456789abcdef";

    public static string Token(WebApplicationFactory<Program> factory, long gitHubId, string username)
    {
        using var scope = factory.Services.CreateScope();
        var jwt = scope.ServiceProvider.GetRequiredService<JwtTokenService>();
        return jwt.GenerateToken(gitHubId, username, null);
    }
}
