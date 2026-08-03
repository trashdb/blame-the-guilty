namespace Statefalse.Application;

/// <summary>
/// GitHub REST/GraphQL client abstraction. Implemented by <see cref="GitHubClient"/>;
/// kept as an interface so services are testable against a fake.
/// </summary>
public interface IGitHubClient
{
    Task<GitHubResponse> GetAsync(string path, string? token = null, CancellationToken ct = default);

    Task<GitHubResponse> PostAsync(string path, string? token, object? body = null, CancellationToken ct = default);

    Task<GitHubResponse> PutAsync(string path, string? token, object? body = null, CancellationToken ct = default);

    Task<GitHubResponse> GraphQlAsync(string query, string? token, CancellationToken ct = default);
}
