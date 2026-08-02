namespace Statefalse.Api.Contracts;

public sealed record PunishmentEventDto(
    long RunId,
    string CulpritLogin,
    string? RepoFullName,
    string? WorkflowName,
    string? WorkflowUrl,
    DateTime OccurredAt,
    bool WasNotified);

public sealed record PunishmentSummaryDto
{
    public List<CulpritRankingDto> TopCulprits { get; init; } = [];
    public List<WorkflowRankingDto> TopWorkflows { get; init; } = [];
    public List<RepoRankingDto> TopRepos { get; init; } = [];
}

public sealed record CulpritRankingDto(string Login, int Count, DateTime LastFailure);

public sealed record WorkflowRankingDto(string Name, string Repo, int Count);

public sealed record RepoRankingDto(string FullName, int Count);
