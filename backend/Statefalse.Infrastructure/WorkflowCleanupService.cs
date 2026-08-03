using Microsoft.EntityFrameworkCore;
using Statefalse.Infrastructure.Data;

namespace Statefalse.Infrastructure;

/// <summary>
/// Periodic data maintenance for workflow runs: recovers stuck in_progress runs
/// and marks superseded ones. Also invoked once on startup after migrations.
/// </summary>
public sealed class WorkflowCleanupService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<WorkflowCleanupService> _logger;

    public WorkflowCleanupService(
        IServiceScopeFactory scopeFactory,
        IConfiguration configuration,
        ILogger<WorkflowCleanupService> logger)
    {
        _scopeFactory = scopeFactory;
        _configuration = configuration;
        _logger = logger;
    }

    public async Task RunOnceAsync()
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Recover stuck runs: mark in_progress older than 24h as cancelled
        var cutoff = DateTime.UtcNow.AddHours(-24);
        var stuck = db.WorkflowRuns.Count(w => w.Status == "in_progress" && w.StartedAt < cutoff);
        if (stuck > 0)
        {
            db.Database.ExecuteSqlRaw("""
                UPDATE "WorkflowRuns" SET "Status" = 'cancelled'
                WHERE "Status" = 'in_progress' AND "StartedAt" < {0}
                """, cutoff);
            _logger.LogInformation("Marked {Count} stale in_progress runs as cancelled", stuck);
        }

        // Mark superseded runs: any in_progress run that is NOT the latest
        // (by RunId) for its (Repo, WorkflowName, HeadBranch) combo
        var superseded = db.Database.ExecuteSqlRaw("""
            UPDATE "WorkflowRuns"
            SET "Status" = 'superseded'
            WHERE "Id" IN (
                SELECT w1."Id"
                FROM "WorkflowRuns" w1
                INNER JOIN (
                    SELECT "Repo", "WorkflowName", "HeadBranch", MAX("RunId") AS "MaxRunId"
                    FROM "WorkflowRuns"
                    WHERE "HeadBranch" IS NOT NULL
                    GROUP BY "Repo", "WorkflowName", "HeadBranch"
                ) w2 ON w1."Repo" = w2."Repo"
                    AND w1."WorkflowName" = w2."WorkflowName"
                    AND w1."HeadBranch" = w2."HeadBranch"
                    AND w1."RunId" < w2."MaxRunId"
                WHERE w1."Status" = 'in_progress'
            )
            """);
        if (superseded > 0)
            _logger.LogInformation("Marked {Count} superseded in_progress runs as superseded", superseded);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var intervalMinutes = _configuration.GetValue("WorkflowCleanup:IntervalMinutes", 360);
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(intervalMinutes));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await RunOnceAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Workflow cleanup failed");
            }
        }
    }
}
