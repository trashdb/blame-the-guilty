using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Contracts;
using Statefalse.Api.Data;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// pull_request webhook handler: tracks lifecycle (opened, synchronize,
/// ready_for_review, converted_to_draft, closed) and fans out PR updates.
/// </summary>
public class PullRequestWebhookHandler : IWebhookHandler
{
    private readonly AppDbContext _db;
    private readonly PullRequestQueries _prs;
    private readonly SignalRNotifier _notifier;
    private readonly ILogger<PullRequestWebhookHandler> _logger;

    public PullRequestWebhookHandler(
        AppDbContext db,
        PullRequestQueries prs,
        SignalRNotifier notifier,
        ILogger<PullRequestWebhookHandler> logger)
    {
        _db = db;
        _prs = prs;
        _notifier = notifier;
        _logger = logger;
    }

    public string EventType => "pull_request";

    public async Task<ApiResult> HandleAsync(JsonElement payload)
    {
        var action = payload.GetProperty("action").GetString();
        var pr = payload.GetProperty("pull_request");
        var prNumber = pr.GetProperty("number").GetInt32();
        var title = pr.GetProperty("title").GetString() ?? "";
        var htmlUrl = pr.GetProperty("html_url").GetString() ?? "";
        var repo = payload.GetProperty("repository").GetProperty("full_name").GetString() ?? "unknown";
        var baseBranch = pr.GetProperty("base").GetProperty("ref").GetString() ?? "";
        var headBranch = pr.GetProperty("head").GetProperty("ref").GetString() ?? "";
        var authorLogin = pr.GetProperty("user").GetProperty("login").GetString() ?? "";
        var authorId = pr.GetProperty("user").TryGetProperty("id", out var aid) ? aid.GetInt64() : (long?)null;
        var draft = pr.TryGetProperty("draft", out var d) && d.GetBoolean();

        if (action == "opened")
        {
            var headSha = pr.TryGetProperty("head", out var head) && head.TryGetProperty("sha", out var sha) ? sha.GetString() : null;
            return await HandleOpened(prNumber, title, htmlUrl, repo, baseBranch, headBranch, authorLogin, authorId, draft, headSha);
        }
        if (action == "synchronize")
        {
            var headSha = pr.TryGetProperty("head", out var head2) && head2.TryGetProperty("sha", out var sha2) ? sha2.GetString() : null;
            return await HandleSynchronize(prNumber, repo, headSha);
        }
        if (action == "ready_for_review") return await HandleReadyForReview(prNumber, repo);
        if (action == "converted_to_draft") return await HandleConvertedToDraft(prNumber, repo);
        if (action == "closed") return await HandleClosed(prNumber, title, htmlUrl, repo, baseBranch, headBranch, authorLogin, authorId, pr);

        WebhookLog.Log("pull_request", action, repo, null, "ignored", $"Unsupported action '{action}'");
        return ApiResult.Ok($"Ignored: pull_request action '{action}'.");
    }

    private async Task<ApiResult> HandleOpened(
        int prNumber, string title, string htmlUrl, string repo,
        string baseBranch, string headBranch, string authorLogin, long? authorId,
        bool draft, string? headSha)
    {
        _db.PullRequestEvents.Add(new PullRequestEvent
        {
            PrNumber = prNumber, Title = title, AuthorLogin = authorLogin,
            AuthorGitHubId = authorId, RepoFullName = repo,
            HeadBranch = headBranch, BaseBranch = baseBranch, PrUrl = htmlUrl,
            Status = "open", Draft = draft, HeadSha = headSha, OccurredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        _logger.LogInformation("PR #{PrNumber} opened by {Author} (draft={Draft})", prNumber, authorLogin, draft);
        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { prNumber, status = "tracking" });
    }

    private async Task<ApiResult> HandleSynchronize(int prNumber, string repo, string? headSha)
    {
        var existing = await _prs.FindOpenAsync(prNumber, repo);

        if (existing != null)
        {
            existing.ReviewApproved = false;
            existing.ApprovedBy = null;
            existing.HeadSha = headSha;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} synchronized — approval reset, headSha={headSha}", prNumber, headSha);
        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { prNumber, status = "synchronized" });
    }

    private async Task<ApiResult> HandleReadyForReview(int prNumber, string repo)
    {
        var existing = await _prs.FindOpenAsync(prNumber, repo);

        if (existing != null)
        {
            existing.Draft = false;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} marked as ready for review", prNumber);
        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { prNumber, status = "ready_for_review" });
    }

    private async Task<ApiResult> HandleConvertedToDraft(int prNumber, string repo)
    {
        var existing = await _prs.FindOpenAsync(prNumber, repo);

        if (existing != null)
        {
            existing.Draft = true;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} converted to draft", prNumber);
        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { prNumber, status = "converted_to_draft" });
    }

    private async Task<ApiResult> HandleClosed(
        int prNumber, string title, string htmlUrl, string repo,
        string baseBranch, string headBranch, string authorLogin, long? authorId,
        JsonElement pr)
    {
        var merged = pr.TryGetProperty("merged", out var m) && m.GetBoolean();
        var status = merged ? "merged" : "closed";

        var existing = await _prs.FindOpenAsync(prNumber, repo);

        if (existing != null)
        {
            existing.Status = status;
            if (merged) existing.OccurredAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }

        _logger.LogInformation("PR #{PrNumber} {Status} by {Author}", prNumber, status, authorLogin);

        if (merged)
        {
            var mergedByLogin = pr.TryGetProperty("merged_by", out var mb)
                ? mb.TryGetProperty("login", out var ml) ? ml.GetString() : null
                : null;
            var headSha = pr.TryGetProperty("merge_commit_sha", out var mcs) ? mcs.GetString() : null;

            await _notifier.NotifyAllAsync("MainBranchUpdated", new MainBranchUpdatedPayload(
                Repo: repo,
                PrNumber: prNumber,
                MergedBy: mergedByLogin ?? "unknown",
                HeadSha: headSha));
            _logger.LogInformation("MainBranchUpdate sent for {Repo} PR #{PrNumber} by {MergedBy}", repo, prNumber, mergedByLogin);
        }

        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { prNumber, status });
    }
}
