namespace Statefalse.Domain.Contracts;

public sealed record PullRequestDto(
    long PrNumber,
    string Title,
    string Repo,
    string? HeadBranch,
    string? BaseBranch,
    string? HtmlUrl,
    string Status,
    string? Conclusion,
    bool Draft,
    string? MergeableState,
    string CiStatus,
    bool ReviewApproved,
    string? LastCommentBy,
    string? LastCommentBody,
    DateTime? LastCommentAt,
    string? LastCommentUrl,
    string? LastReviewFilePath,
    int? LastReviewLine,
    bool IsSubscribed,
    long[] SubscriberIds,
    long? AuthorGitHubId);

public sealed record PullRequestDetailDto(
    long PrNumber,
    string Repo,
    string? MergeableState,
    int? BehindBy,
    int? AheadBy,
    string? Title,
    string? HeadBranch,
    string? BaseBranch,
    string? Status,
    bool Draft,
    string? LastCommentBy,
    string? LastCommentBody,
    DateTime? LastCommentAt,
    string? LastCommentUrl,
    string? LastReviewFilePath,
    int? LastReviewLine);

public sealed record CommitDto(
    string? Sha,
    string? Message,
    string? AuthorName,
    string? AuthorLogin,
    string? Date,
    string? Url);

public sealed record PrFileDto(string? Filename, string? Status, int Additions, int Deletions);

public sealed record CheckRunDto(
    string? Name,
    string? Status,
    string? Conclusion,
    string? StartedAt,
    string? CompletedAt,
    string? Url);
