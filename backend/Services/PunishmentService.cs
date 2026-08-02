using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Contracts;
using Statefalse.Api.Data;

namespace Statefalse.Api.Services;

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
            .Select(e => new PunishmentEventDto(
                e.RunId,
                e.CulpritLogin,
                e.RepoFullName,
                e.WorkflowName,
                e.WorkflowUrl,
                e.OccurredAt,
                e.WasNotified))
            .ToListAsync();

        return ApiResult.Ok(events);
    }

    public async Task<ApiResult> GetSummaryAsync(int days = 7)
    {
        var since = DateTime.UtcNow.AddDays(-days);

        var events = await _db.PunishmentEvents
            .Where(e => e.OccurredAt >= since)
            .Select(e => new { e.CulpritLogin, e.WorkflowName, e.RepoFullName, e.OccurredAt })
            .ToListAsync();

        var topCulprits = events
            .GroupBy(e => e.CulpritLogin)
            .Select(g => new CulpritRankingDto(g.Key, g.Count(), g.Max(e => e.OccurredAt)))
            .OrderByDescending(c => c.Count)
            .Take(5)
            .ToList();

        var topWorkflows = events
            .Where(e => e.WorkflowName != null)
            .GroupBy(e => new { e.WorkflowName, e.RepoFullName })
            .Select(g => new WorkflowRankingDto(g.Key.WorkflowName!, g.Key.RepoFullName, g.Count()))
            .OrderByDescending(w => w.Count)
            .Take(5)
            .ToList();

        var topRepos = events
            .GroupBy(e => e.RepoFullName)
            .Select(g => new RepoRankingDto(g.Key, g.Count()))
            .OrderByDescending(r => r.Count)
            .Take(5)
            .ToList();

        return ApiResult.Ok(new PunishmentSummaryDto
        {
            TopCulprits = topCulprits,
            TopWorkflows = topWorkflows,
            TopRepos = topRepos
        });
    }
}
