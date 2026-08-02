using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// Resolves the effective GitHub token for a user. Precedence:
/// User PAT > OAuth access token > shared server PAT.
/// </summary>
public class GitHubTokenResolver : IGitHubTokenResolver
{
    private readonly AppDbContext _db;
    private readonly IConfiguration _configuration;

    public GitHubTokenResolver(AppDbContext db, IConfiguration configuration)
    {
        _db = db;
        _configuration = configuration;
    }

    public async Task<GitHubUser?> GetUserAsync(long gitHubId)
        => await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId);

    public string? ResolveForUser(GitHubUser? user)
        => user?.UserPatToken ?? user?.AccessToken ?? _configuration["GitHub:PatToken"];

    public async Task<string?> ResolveAsync(long gitHubId)
        => ResolveForUser(await GetUserAsync(gitHubId));

    public string? SharedPat => _configuration["GitHub:PatToken"];

    public async Task<GitHubUser?> FindByLoginAsync(string login)
        => await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == login);

    public async Task<GitHubUser?> FindConnectedUserAsync(string login, long? gitHubId)
        => gitHubId.HasValue
            ? await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubId == gitHubId.Value && u.SignalRConnectionId != null)
            : await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == login && u.SignalRConnectionId != null);
}
