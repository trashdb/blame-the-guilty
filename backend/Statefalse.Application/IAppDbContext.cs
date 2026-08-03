using Microsoft.EntityFrameworkCore;
using Statefalse.Domain.Models;

namespace Statefalse.Application;

/// <summary>
/// Query/change-tracking surface of the persistence context, kept behind an
/// interface so Application services never depend on the EF Infrastructure
/// assembly. Implemented by <c>Statefalse.Infrastructure.Data.AppDbContext</c>.
/// </summary>
public interface IAppDbContext
{
    DbSet<GitHubUser> GitHubUsers { get; }
    DbSet<PunishmentEvent> PunishmentEvents { get; }
    DbSet<CheckSuiteEvent> CheckSuiteEvents { get; }
    DbSet<PullRequestEvent> PullRequestEvents { get; }
    DbSet<WorkflowRun> WorkflowRuns { get; }

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
