namespace Statefalse.Api.Contracts;

public sealed record WorkflowRunDto(
    int Id,
    long RunId,
    string? WorkflowName,
    string Repo,
    string Actor,
    string? HeadBranch,
    string? Trigger,
    string Status,
    string? HtmlUrl,
    DateTime StartedAt,
    long[] TargetGitHubIds,
    int? PrNumber,
    string? PrTitle);

public sealed record SetTargetRequest
{
    public long[]? TargetGitHubIds { get; set; }
}

public sealed record SyncResult(int Synced, int? Repos = null, string? Message = null);
