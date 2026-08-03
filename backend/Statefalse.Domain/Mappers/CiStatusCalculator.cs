namespace Statefalse.Domain;

/// <summary>
/// Pure ciStatus computation for a pull request. Input runs must already be
/// filtered to the PR's (repo, headSha) combination.
/// </summary>
public static class CiStatusCalculator
{
    private static readonly string[] ExcludedRunStatuses = ["superseded", "cancelled", "skipped"];

    public static string Calculate(
        string? headSha,
        bool isOpen,
        bool reviewApproved,
        IEnumerable<(int Id, string? WorkflowName, string Status)> runs)
    {
        if (headSha == null) return "review";

        var latestByWorkflow = runs
            .Where(r => !ExcludedRunStatuses.Contains(r.Status))
            .GroupBy(r => r.WorkflowName)
            .Select(g => g.OrderByDescending(r => r.Id).First())
            .ToList();

        var ciStatus = latestByWorkflow.Count == 0 ? "waiting"
            : latestByWorkflow.Any(r => r.Status == "in_progress") ? "waiting"
            : latestByWorkflow.Any(r => r.Status == "failure") ? "failed"
            : "review";

        if (isOpen && ciStatus == "review" && reviewApproved)
            ciStatus = "ready";

        return ciStatus;
    }
}
