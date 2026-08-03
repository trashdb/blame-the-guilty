namespace Statefalse.Domain;

/// <summary>
/// Maps GitHub check-run status/conclusion to the persisted WorkflowRun status.
/// </summary>
public static class CheckRunStatusMapper
{
    public static string Map(string? status, string? conclusion)
        => status == "completed"
            ? conclusion == "success" ? "success"
            : conclusion is "failure" or "timed_out" ? "failure"
            : "cancelled"
            : "in_progress";
}
