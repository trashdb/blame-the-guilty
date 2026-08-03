using System.Text.Json;
using Statefalse.Application;

namespace Statefalse.Application;

/// <summary>
/// issue_comment webhook handler for PR comments (bot-filtered, PR-only).
/// </summary>
public class IssueCommentWebhookHandler : PullRequestCommentHandlerBase
{
    public IssueCommentWebhookHandler(
        IAppDbContext db,
        PullRequestQueries prs,
        ISignalRNotifier notifier,
        ILogger<IssueCommentWebhookHandler> logger)
        : base(db, prs, notifier, logger)
    {
    }

    public override string EventType => "issue_comment";

    protected override string? TryGetIgnoreReason(JsonElement payload)
    {
        var issue = payload.GetProperty("issue");
        if (!issue.TryGetProperty("pull_request", out _))
            return "Not a PR comment";

        var commenterType = payload.GetProperty("comment").GetProperty("user").GetProperty("type").GetString();
        return commenterType == "User" ? null : $"Commenter type={commenterType}, skipping";
    }

    protected override string GetCommenterLogin(JsonElement payload)
        => payload.GetProperty("comment").GetProperty("user").GetProperty("login").GetString() ?? "unknown";

    protected override string GetCommentBody(JsonElement payload)
        => payload.GetProperty("comment").TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";

    protected override string? GetCommentUrl(JsonElement payload)
        => payload.GetProperty("comment").TryGetProperty("html_url", out var hu) ? hu.GetString() : null;
}
