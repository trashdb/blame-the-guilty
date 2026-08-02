using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// Shared PullRequestEvent database lookups. Single implementation of the
/// "latest event for (prNumber, repo)" query used across webhook handlers and
/// pull request services.
/// </summary>
public class PullRequestQueries
{
    private readonly AppDbContext _db;

    public PullRequestQueries(AppDbContext db)
    {
        _db = db;
    }

    public Task<PullRequestEvent?> FindOpenAsync(long prNumber, string repo)
        => _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

    public Task<PullRequestEvent?> FindLatestAsync(long prNumber, string repo)
        => _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo)
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();

    public Task<PullRequestEvent?> FindLatestOpenAsync(long prNumber, string repo)
        => _db.PullRequestEvents
            .Where(e => e.PrNumber == prNumber && e.RepoFullName == repo && e.Status == "open")
            .OrderByDescending(e => e.Id)
            .FirstOrDefaultAsync();
}
