namespace Statefalse.Api.Services;

/// <summary>
/// Pure mapping of GitHub workflow conclusions to the persisted DB status.
/// Isolated so webhook handling and tests share one definition.
/// </summary>
public static class WorkflowConclusionMapper
{
    public static bool IsTerminal(string? conclusion)
        => conclusion is "success" or "failure" or "cancelled" or "timed_out" or "stale"
            or "action_required" or "skipped" or "neutral" or "startup_failure";

    public static bool IsNonFailure(string? conclusion)
        => conclusion is "success" or "cancelled" or "timed_out" or "stale"
            or "action_required" or "skipped" or "neutral" or "startup_failure";

    public static string? ToDbStatus(string? conclusion)
    {
        if (!IsTerminal(conclusion)) return null;
        return conclusion switch
        {
            "success" => "success",
            "failure" => "failure",
            _ => "cancelled"
        };
    }
}
