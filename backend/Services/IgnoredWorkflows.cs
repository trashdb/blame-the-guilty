namespace Statefalse.Api.Services;

/// <summary>
/// Workflow names that never trigger notifications or punishments (noisy bots).
/// Shared by WebhookService + WorkflowService.
/// </summary>
public static class IgnoredWorkflows
{
    private static readonly HashSet<string> Names = new(StringComparer.OrdinalIgnoreCase)
    {
        "CodeQL High Severity",
        "Dependency Review",
        "Label PR by Team Member",
        "Verify ForgeRock Secrets"
    };

    public static bool IsIgnored(string? workflowName)
        => workflowName != null && Names.Contains(workflowName);
}
