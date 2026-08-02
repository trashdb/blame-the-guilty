using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Contracts;
using Statefalse.Api.Data;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// Shared logic for PR comment webhooks (issue_comment + pull_request_review_comment).
/// Both update the same LastComment* fields, then notify the author and subscribers.
/// Subclasses provide the payload accessors and ignore rules that differ per event.
/// </summary>
public abstract class PullRequestCommentHandlerBase : IWebhookHandler
{
    protected readonly AppDbContext Db;
    protected readonly PullRequestQueries Prs;
    protected readonly SignalRNotifier Notifier;
    protected readonly ILogger Logger;

    private const int MaxCommentLength = 500;

    protected PullRequestCommentHandlerBase(
        AppDbContext db,
        PullRequestQueries prs,
        SignalRNotifier notifier,
        ILogger logger)
    {
        Db = db;
        Prs = prs;
        Notifier = notifier;
        Logger = logger;
    }

    public abstract string EventType { get; }

    public async Task<ApiResult> HandleAsync(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        if (action != "created")
        {
            WebhookLog.Log(EventType, action, TryGetRepo(payload), null, "ignored", $"Unsupported action '{action}'");
            return ApiResult.Ok($"Ignored: {EventType} action '{action}'.");
        }

        if (TryGetIgnoreReason(payload) is { } reason)
        {
            WebhookLog.Log(EventType, action, TryGetRepo(payload), null, "ignored", reason);
            return ApiResult.Ok($"Ignored: {reason}");
        }

        var pr = payload.GetProperty("pull_request");
        var prNumber = pr.GetProperty("number").GetInt32();
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var commenterLogin = GetCommenterLogin(payload);
        var commentBody = GetCommentBody(payload);
        var commentUrl = GetCommentUrl(payload);

        var existing = await Prs.FindOpenAsync(prNumber, repo);

        if (existing == null)
        {
            WebhookLog.Log(EventType, action, repo, null, "ignored", "PR not tracked");
            return ApiResult.Ok("PR not tracked, ignoring.");
        }

        existing.LastCommentBy = commenterLogin;
        existing.LastCommentBody = commentBody.Length > MaxCommentLength ? commentBody[..MaxCommentLength] : commentBody;
        existing.LastCommentAt = DateTime.UtcNow;
        existing.LastCommentUrl = commentUrl;
        await Db.SaveChangesAsync();

        WebhookLog.Log(EventType, action, repo, null, "processed",
            BuildProcessedMessage(payload, prNumber, commenterLogin));

        var notifPayload = new PrCommentedPayload(
            prNumber, repo, commenterLogin, existing.Title,
            existing.LastCommentBody, commentUrl, GetFilePath(payload), GetLine(payload));

        // Notify PR author
        if (existing.AuthorGitHubId.HasValue)
        {
            var authorConn = await Db.GitHubUsers
                .Where(u => u.GitHubId == existing.AuthorGitHubId.Value)
                .Select(u => u.SignalRConnectionId)
                .FirstOrDefaultAsync();

            if (!string.IsNullOrEmpty(authorConn))
                await Notifier.NotifyConnectionAsync(authorConn, "PrCommented", notifPayload);
        }

        // Notify subscribers (excluding the commenter)
        var commenterUser = await Db.GitHubUsers.Where(u => u.GitHubUsername == commenterLogin).Select(u => u.GitHubId).FirstOrDefaultAsync();
        await Notifier.NotifySubscribersAsync(existing, "PrCommented", notifPayload, commenterUser);

        await Notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(BuildResult(payload, prNumber, commenterLogin));
    }

    /// <summary>Non-null reason short-circuits the handler (e.g. not a user, not a PR comment).</summary>
    protected abstract string? TryGetIgnoreReason(JsonElement payload);
    protected abstract string GetCommenterLogin(JsonElement payload);
    protected abstract string GetCommentBody(JsonElement payload);
    protected abstract string? GetCommentUrl(JsonElement payload);
    protected virtual string? GetFilePath(JsonElement payload) => null;
    protected virtual int? GetLine(JsonElement payload) => null;
    protected virtual string BuildProcessedMessage(JsonElement payload, int prNumber, string commenterLogin)
        => $"PR #{prNumber} comment by {commenterLogin}";
    protected virtual object BuildResult(JsonElement payload, int prNumber, string commenterLogin)
        => new { prNumber, commenterLogin };

    protected static string? TryGetRepo(JsonElement payload)
    {
        if (payload.TryGetProperty("repository", out var repo) &&
            repo.TryGetProperty("full_name", out var name))
            return name.GetString();
        return null;
    }
}
