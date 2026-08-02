using System.Text.Json;
using Statefalse.Api.Data;

namespace Statefalse.Api.Services;

/// <summary>
/// pull_request_review_comment webhook handler (inline review comments).
/// </summary>
public class PullRequestReviewCommentWebhookHandler : PullRequestCommentHandlerBase
{
    public PullRequestReviewCommentWebhookHandler(
        AppDbContext db,
        PullRequestQueries prs,
        SignalRNotifier notifier,
        ILogger<PullRequestReviewCommentWebhookHandler> logger)
        : base(db, prs, notifier, logger)
    {
    }

    public override string EventType => "pull_request_review_comment";

    protected override string? TryGetIgnoreReason(JsonElement payload)
    {
        var commenterType = payload.GetProperty("comment").GetProperty("user").GetProperty("type").GetString();
        return commenterType == "User" ? null : $"Commenter type={commenterType}, skipping";
    }

    protected override string GetCommenterLogin(JsonElement payload)
        => payload.GetProperty("comment").GetProperty("user").GetProperty("login").GetString() ?? "unknown";

    protected override string GetCommentBody(JsonElement payload)
        => payload.GetProperty("comment").TryGetProperty("body", out var b) ? b.GetString() ?? "" : "";

    protected override string? GetCommentUrl(JsonElement payload)
        => payload.GetProperty("comment").TryGetProperty("html_url", out var hu) ? hu.GetString() : null;

    protected override string? GetFilePath(JsonElement payload)
        => payload.GetProperty("comment").TryGetProperty("path", out var p) ? p.GetString() : null;

    protected override int? GetLine(JsonElement payload)
        => payload.GetProperty("comment").TryGetProperty("line", out var l) ? l.GetInt32() : null;

    protected override string BuildProcessedMessage(JsonElement payload, int prNumber, string commenterLogin)
        => $"PR #{prNumber} review comment by {commenterLogin} on {GetFilePath(payload)}:{GetLine(payload)}";

    protected override object BuildResult(JsonElement payload, int prNumber, string commenterLogin)
        => new { prNumber, commenterLogin, filePath = GetFilePath(payload), line = GetLine(payload) };
}
