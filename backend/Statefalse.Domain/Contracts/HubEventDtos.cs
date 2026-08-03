namespace Statefalse.Domain.Contracts;

public sealed record WorkflowRunStartedPayload(
    int Id,
    long RunId,
    string? WorkflowName,
    string Repo,
    string? Branch,
    string? Trigger,
    string? Actor,
    string? HtmlUrl);

public sealed record WorkflowRunCompletedPayload(
    long RunId,
    bool Succeeded,
    string? Conclusion,
    string? WorkflowName,
    string Repo,
    string? Actor,
    string? HtmlUrl,
    string? Trigger);

public sealed record CheckSuiteStartedPayload(
    long CheckSuiteId,
    string? AppName,
    string Repo,
    string? Branch,
    int? PrNumber,
    string Author);

public sealed record CheckSuiteCompletedPayload(
    long CheckSuiteId,
    string Conclusion,
    bool Succeeded,
    int? PrNumber,
    string Repo,
    string? HeadBranch,
    string PrAuthor);

public sealed record PrApprovedPayload(
    int PrNumber,
    string Repo,
    string ReviewerLogin,
    string? Title);

public sealed record PrCommentedPayload(
    int PrNumber,
    string Repo,
    string CommenterLogin,
    string? Title,
    string? CommentBody,
    string? CommentUrl,
    string? FilePath = null,
    int? Line = null);

public sealed record MainBranchUpdatedPayload(
    string Repo,
    int PrNumber,
    string MergedBy,
    string? HeadSha);
