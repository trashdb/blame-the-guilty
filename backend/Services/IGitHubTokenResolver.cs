using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// Resolves the effective GitHub token for a user. Precedence:
/// User PAT > OAuth access token > shared server PAT.
/// </summary>
public interface IGitHubTokenResolver
{
    Task<GitHubUser?> GetUserAsync(long gitHubId);

    string? ResolveForUser(GitHubUser? user);

    Task<string?> ResolveAsync(long gitHubId);

    string? SharedPat { get; }

    Task<GitHubUser?> FindByLoginAsync(string login);

    Task<GitHubUser?> FindConnectedUserAsync(string login, long? gitHubId);
}
