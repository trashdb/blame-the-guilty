using System.Collections.Concurrent;

namespace Statefalse.Application;

/// <summary>
/// Bounded in-memory ring buffer of recent webhook outcomes, surfaced at
/// GET /api/webhook/logs for the native webhook-log panel.
/// </summary>
public static class WebhookLog
{
    private static readonly ConcurrentQueue<WebhookLogEntry> _recent = new();
    private const int MaxEntries = 100;

    public static List<WebhookLogEntry> GetRecent(int limit)
        => _recent.Reverse().Take(limit).ToList();

    public static void Log(string eventType, string? action, string? repo, string? workflowName, string outcome, string? message = null)
    {
        _recent.Enqueue(new WebhookLogEntry
        {
            EventType = eventType,
            Action = action,
            Repo = repo,
            WorkflowName = workflowName,
            Outcome = outcome,
            Message = message,
            OccurredAt = DateTime.UtcNow
        });
        while (_recent.Count > MaxEntries)
            _recent.TryDequeue(out _);
    }
}

public record WebhookLogEntry
{
    public string EventType { get; init; } = "";
    public string? Action { get; init; }
    public string? Repo { get; init; }
    public string? WorkflowName { get; init; }
    public string Outcome { get; init; } = "";
    public string? Message { get; init; }
    public DateTime OccurredAt { get; init; }
}
