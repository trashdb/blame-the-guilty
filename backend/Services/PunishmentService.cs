using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;

namespace Statefalse.Api.Services;

public class PunishmentSummary
{
    public List<CulpritRanking> TopCulprits { get; set; } = new();
    public List<WorkflowRanking> TopWorkflows { get; set; } = new();
    public List<RepoRanking> TopRepos { get; set; } = new();
}

public class CulpritRanking
{
    public string Login { get; set; } = string.Empty;
    public int Count { get; set; }
    public DateTime LastFailure { get; set; }
}

public class WorkflowRanking
{
    public string Name { get; set; } = string.Empty;
    public string Repo { get; set; } = string.Empty;
    public int Count { get; set; }
}

public class RepoRanking
{
    public string FullName { get; set; } = string.Empty;
    public int Count { get; set; }
}

/// <summary>
/// Punishment (failed workflow) leaderboards + recent event feed.
/// </summary>
public class PunishmentService
{
    private readonly AppDbContext _db;

    public PunishmentService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ApiResult> GetRecentAsync(int days = 7, int limit = 50)
    {
        var since = DateTime.UtcNow.AddDays(-days);

        var events = await _db.PunishmentEvents
            .Where(e => e.OccurredAt >= since)
            .OrderByDescending(e => e.OccurredAt)
            .Take(limit)
            .Select(e => new
            {
                e.RunId,
                e.CulpritLogin,
                e.RepoFullName,
                e.WorkflowName,
                e.WorkflowUrl,
                e.OccurredAt,
                e.WasNotified
            })
            .ToListAsync();

        return ApiResult.Ok(events);
    }

    public async Task<ApiResult> GetSummaryAsync(int days = 7)
    {
        var since = DateTime.UtcNow.AddDays(-days);

        var topCulprits = await _db.PunishmentEvents
            .Where(e => e.OccurredAt >= since)
            .GroupBy(e => e.CulpritLogin)
            .Select(g => new CulpritRanking
            {
                Login = g.Key,
                Count = g.Count(),
                LastFailure = g.Max(e => e.OccurredAt)
            })
            .OrderByDescending(c => c.Count)
            .Take(5)
            .ToListAsync();

        var topWorkflows = await _db.PunishmentEvents
            .Where(e => e.OccurredAt >= since && e.WorkflowName != null)
            .GroupBy(e => new { e.WorkflowName, e.RepoFullName })
            .Select(g => new WorkflowRanking
            {
                Name = g.Key.WorkflowName!,
                Repo = g.Key.RepoFullName,
                Count = g.Count()
            })
            .OrderByDescending(w => w.Count)
            .Take(5)
            .ToListAsync();

        var topRepos = await _db.PunishmentEvents
            .Where(e => e.OccurredAt >= since)
            .GroupBy(e => e.RepoFullName)
            .Select(g => new RepoRanking
            {
                FullName = g.Key,
                Count = g.Count()
            })
            .OrderByDescending(r => r.Count)
            .Take(5)
            .ToListAsync();

        return ApiResult.Ok(new PunishmentSummary
        {
            TopCulprits = topCulprits,
            TopWorkflows = topWorkflows,
            TopRepos = topRepos
        });
    }
}
