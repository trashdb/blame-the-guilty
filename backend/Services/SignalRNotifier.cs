using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Statefalse.Api.Data;
using Statefalse.Api.Hubs;
using Statefalse.Api.Models;

namespace Statefalse.Api.Services;

/// <summary>
/// Centralized SignalR fan-out. Single owner of hub payload shapes so every
/// caller broadcasts the same DTOs to the same targets.
/// </summary>
public class SignalRNotifier
{
    private readonly IHubContext<PunishmentHub> _hub;
    private readonly AppDbContext _db;

    public SignalRNotifier(IHubContext<PunishmentHub> hub, AppDbContext db)
    {
        _hub = hub;
        _db = db;
    }

    public Task NotifyPullRequestsUpdatedAsync()
        => _hub.Clients.All.SendAsync("PullRequestsUpdated");

    public Task NotifyAllAsync(string method, object payload)
        => _hub.Clients.All.SendAsync(method, payload);

    public Task NotifyUserAsync(long gitHubId, string method, object payload)
        => _hub.Clients.Group(gitHubId.ToString()).SendAsync(method, payload);

    public Task NotifyConnectionAsync(string connectionId, string method, object payload)
        => _hub.Clients.Client(connectionId).SendAsync(method, payload);

    /// <summary>
    /// Notifies every subscriber (except <paramref name="excludeGitHubId"/>) that
    /// has an active SignalR connection. Returns the number of connections notified.
    /// </summary>
    public async Task<int> NotifySubscribersAsync(PullRequestEvent pr, string method, object payload, long? excludeGitHubId = null)
    {
        var subscriberIds = IdListSerializer.Deserialize(pr.SubscriberIds);
        if (subscriberIds.Length == 0) return 0;

        var connections = await _db.GitHubUsers
            .Where(u => subscriberIds.Contains(u.GitHubId) && u.SignalRConnectionId != null
                && (excludeGitHubId == null || u.GitHubId != excludeGitHubId.Value))
            .Select(u => u.SignalRConnectionId!)
            .ToListAsync();

        foreach (var conn in connections)
            await _hub.Clients.Client(conn).SendAsync(method, payload);

        return connections.Count;
    }
}
