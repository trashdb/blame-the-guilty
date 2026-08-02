import Foundation

/// Pure mapping between API DTOs and domain models. Extracted from
/// SignalRService so the mapping is unit-testable and the service stays thin.
enum DTOMapper {
    static func workflowRun(_ r: ApiWorkflowRun) -> WorkflowRun {
        WorkflowRun(
            id: UUID(),
            dbId: r.id,
            runId: r.runId,
            workflowName: r.workflowName ?? "Workflow",
            repo: r.repo,
            actor: r.actor,
            headBranch: r.headBranch,
            trigger: r.trigger,
            prNumber: r.prNumber,
            prTitle: r.prTitle,
            status: r.status,
            htmlUrl: r.htmlUrl ?? "",
            startedAt: r.startedAt,
            completedAt: nil,
            targetGitHubIds: r.targetGitHubIds ?? []
        )
    }

    static func pullRequest(_ pr: ApiPullRequest) -> PullRequest {
        PullRequest(
            prNumber: pr.prNumber, title: pr.title,
            repo: pr.repo,
            headBranch: pr.headBranch ?? "",
            baseBranch: pr.baseBranch ?? "",
            htmlUrl: URL(string: pr.htmlUrl ?? ""),
            status: pr.status ?? "open",
            conclusion: pr.conclusion,
            draft: pr.draft ?? false,
            mergeableState: pr.mergeableState,
            ciStatus: pr.ciStatus ?? "ready",
            reviewApproved: pr.reviewApproved ?? false,
            lastCommentBy: pr.lastCommentBy,
            lastCommentBody: pr.lastCommentBody,
            lastCommentAt: pr.lastCommentAt,
            lastCommentUrl: nil,
            lastReviewFilePath: nil,
            lastReviewLine: nil,
            isSubscribed: pr.isSubscribed ?? false,
            subscriberIds: pr.subscriberIds ?? [],
            authorGitHubId: pr.authorGitHubId
        )
    }

    static func startedDate(from string: String?) -> Date {
        string.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
    }
}
