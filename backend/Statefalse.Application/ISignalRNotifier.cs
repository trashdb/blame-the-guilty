using Statefalse.Domain.Models;

namespace Statefalse.Application;

/// <summary>
/// SignalR fan-out contract. Implemented by the Infrastructure notifier so
/// Application services can push hub events without depending on ASP.NET Core.
/// </summary>
public interface ISignalRNotifier
{
    Task NotifyPullRequestsUpdatedAsync();

    Task NotifyAllAsync(string method, object payload);

    Task NotifyUserAsync(long gitHubId, string method, object payload);

    Task NotifyConnectionAsync(string connectionId, string method, object payload);

    Task<int> NotifySubscribersAsync(PullRequestEvent pr, string method, object payload, long? excludeGitHubId = null);
}
