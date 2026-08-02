using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Contracts;
using Statefalse.Api.Data;

namespace Statefalse.Api.Services;

/// <summary>
/// pull_request_review webhook handler: tracks approvals/dismissals and notifies
/// the PR author plus subscribers.
/// </summary>
public class PullRequestReviewWebhookHandler : IWebhookHandler
{
    private readonly AppDbContext _db;
    private readonly PullRequestQueries _prs;
    private readonly SignalRNotifier _notifier;
    private readonly ILogger<PullRequestReviewWebhookHandler> _logger;

    public PullRequestReviewWebhookHandler(
        AppDbContext db,
        PullRequestQueries prs,
        SignalRNotifier notifier,
        ILogger<PullRequestReviewWebhookHandler> logger)
    {
        _db = db;
        _prs = prs;
        _notifier = notifier;
        _logger = logger;
    }

    public string EventType => "pull_request_review";

    public async Task<ApiResult> HandleAsync(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        if (action != "submitted")
        {
            WebhookLog.Log("pull_request_review", action, TryGetRepo(payload), null, "ignored", $"Unsupported action '{action}'");
            return ApiResult.Ok($"Ignored: pull_request_review action '{action}'.");
        }

        var review = payload.GetProperty("review");
        var reviewState = review.GetProperty("state").GetString();
        var pr = payload.GetProperty("pull_request");
        var prNumber = pr.GetProperty("number").GetInt32();
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var reviewerLogin = review.GetProperty("user").GetProperty("login").GetString() ?? "unknown";

        var existing = await _prs.FindOpenAsync(prNumber, repo);

        if (existing == null)
        {
            WebhookLog.Log("pull_request_review", action, repo, null, "ignored", "PR not tracked");
            return ApiResult.Ok("PR not tracked, ignoring.");
        }

        // Only update ReviewApproved on explicit approval or dismissal.
        // "commented" reviews must NOT reset an existing approval — that's the
        // most common cause of PRs staying stuck on "review" instead of "ready".
        var approved = reviewState == "approved";
        if (approved)
        {
            existing.ReviewApproved = true;
            existing.ApprovedBy = reviewerLogin;
        }
        else if (reviewState is "dismissed" or "changes_requested")
        {
            existing.ReviewApproved = false;
            existing.ApprovedBy = null;
        }
        // "commented" → don't touch ReviewApproved at all
        await _db.SaveChangesAsync();

        WebhookLog.Log("pull_request_review", action, repo, null, approved ? "approved" : reviewState!,
            $"PR #{prNumber} reviewed by {reviewerLogin}: {reviewState}");

        var payload2 = new PrApprovedPayload(prNumber, repo, reviewerLogin, existing.Title);

        // Notify PR author when approved
        if (approved && existing.AuthorGitHubId.HasValue)
        {
            var approverToken = await _db.GitHubUsers
                .Where(u => u.GitHubId == existing.AuthorGitHubId.Value)
                .Select(u => u.SignalRConnectionId)
                .FirstOrDefaultAsync();

            if (!string.IsNullOrEmpty(approverToken))
                await _notifier.NotifyConnectionAsync(approverToken, "PrApproved", payload2);
        }

        // Notify subscribers (excluding the reviewer themselves)
        var reviewerUser = await _db.GitHubUsers.Where(u => u.GitHubUsername == reviewerLogin).Select(u => u.GitHubId).FirstOrDefaultAsync();
        await _notifier.NotifySubscribersAsync(existing, "PrApproved", payload2, reviewerUser);

        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { prNumber, approved });
    }

    private static string? TryGetRepo(JsonElement payload)
    {
        if (payload.TryGetProperty("repository", out var repo) &&
            repo.TryGetProperty("full_name", out var name))
            return name.GetString();
        return null;
    }
}
