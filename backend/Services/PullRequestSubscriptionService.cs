using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Contracts;
using Statefalse.Api.Data;

namespace Statefalse.Api.Services;

/// <summary>
/// Pull request subscriber management (who gets notified about a PR).
/// </summary>
public class PullRequestSubscriptionService
{
    private readonly AppDbContext _db;
    private readonly PullRequestQueries _prs;
    private readonly SignalRNotifier _notifier;

    public PullRequestSubscriptionService(
        AppDbContext db,
        PullRequestQueries prs,
        SignalRNotifier notifier)
    {
        _db = db;
        _prs = prs;
        _notifier = notifier;
    }

    public async Task<ApiResult> SubscribeAsync(long prNumber, string repo, long gitHubId)
    {
        var pr = await _prs.FindOpenAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (!current.Contains(gitHubId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Append(gitHubId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { subscribed = true, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }

    public async Task<ApiResult> UnsubscribeAsync(long prNumber, string repo, long gitHubId)
    {
        var pr = await _prs.FindOpenAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (current.Contains(gitHubId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Where(id => id != gitHubId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { subscribed = false, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }

    public async Task<ApiResult> GetSubscribersAsync(long prNumber, string repo)
    {
        var pr = await _prs.FindLatestAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        var ids = IdListSerializer.Deserialize(pr.SubscriberIds);

        var users = await _db.GitHubUsers
            .Where(u => ids.Contains(u.GitHubId))
            .Select(u => new { u.GitHubId, u.GitHubUsername, u.AvatarUrl })
            .ToListAsync();

        return ApiResult.Ok(new { subscribers = users, subscriberIds = ids });
    }

    public async Task<ApiResult> AddSubscriberAsync(long prNumber, string repo, long gitHubId, string? username, long? subscriberId)
    {
        var pr = await _prs.FindOpenAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        // Only PR author can add subscribers (or self-subscribe)
        if (pr.AuthorGitHubId != gitHubId)
            return ApiResult.Forbid();

        long targetId;
        if (subscriberId.HasValue)
        {
            targetId = subscriberId.Value;
            var userExists = await _db.GitHubUsers.AnyAsync(u => u.GitHubId == targetId);
            if (!userExists) return ApiResult.NotFound(new { error = "User not found in database" });
        }
        else if (!string.IsNullOrEmpty(username))
        {
            var user = await _db.GitHubUsers.FirstOrDefaultAsync(u => u.GitHubUsername == username);
            if (user == null) return ApiResult.NotFound(new { error = "User not found in database" });
            targetId = user.GitHubId;
        }
        else
        {
            return ApiResult.BadRequest(new { error = "Must provide username or subscriberId" });
        }

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (!current.Contains(targetId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Append(targetId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { added = true, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }

    public async Task<ApiResult> RemoveSubscriberAsync(long prNumber, string repo, long gitHubId, long subscriberId)
    {
        var pr = await _prs.FindOpenAsync(prNumber, repo);
        if (pr == null) return ApiResult.NotFound(new { error = "PR not found" });

        // Only PR author can remove subscribers (or self-unsubscribe)
        if (pr.AuthorGitHubId != gitHubId && subscriberId != gitHubId)
            return ApiResult.Forbid();

        var current = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (current.Contains(subscriberId))
        {
            pr.SubscriberIds = IdListSerializer.Serialize(current.Where(id => id != subscriberId).ToArray());
            await _db.SaveChangesAsync();
        }

        await _notifier.NotifyPullRequestsUpdatedAsync();
        return ApiResult.Ok(new { removed = true, subscribers = IdListSerializer.Deserialize(pr.SubscriberIds) });
    }
}
