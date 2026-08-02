import Foundation

/// Result of reducing a WorkflowRunCompleted hub event. Pure data: the caller
/// publishes it onto the main actor.
struct WorkflowCompletedUpdate {
    var runStatus: RunStatus?
    var shouldResetStatus: Bool
    var runningWorkflows: [WorkflowRun]
    var recentWorkflows: [WorkflowRun]
    var lastEvent: PunishmentEvent?
    var notification: (title: String, body: String, subtitle: String, url: URL?)?
}

/// Pure reduction of SignalR workflow events into new run-list state.
enum WorkflowEventReducer {
    static func reduceCompleted(
        _ event: WorkflowCompletedEvent,
        runningWorkflows: [WorkflowRun],
        recentWorkflows: [WorkflowRun]
    ) -> WorkflowCompletedUpdate {
        let runId = event.runId
        let succeeded = event.succeeded ?? false
        let conclusion = event.conclusion
        let name = event.workflowName
        let repo = event.repo
        let actor = event.actor ?? "someone"
        let htmlUrl = event.htmlUrl
        let trigger = event.trigger

        let isActualFailure = !succeeded && (conclusion == nil || conclusion == "failure")

        var newRunning = runningWorkflows
        if let idx = newRunning.firstIndex(where: { $0.runId == runId }) {
            newRunning.remove(at: idx)
        }

        let existing = recentWorkflows.first(where: { $0.runId == runId && $0.status == "in_progress" })
        let originalStartedAt = existing?.startedAt ?? Date()
        let completedAt = Date()

        let statusString: String
        if succeeded { statusString = "success" }
        else if let c = conclusion, c != "failure" { statusString = "cancelled" }
        else { statusString = "failure" }

        let completedRun = WorkflowRun(
            id: UUID(), dbId: existing?.dbId,
            runId: runId,
            workflowName: name ?? "Workflow",
            repo: repo,
            actor: actor,
            headBranch: existing?.headBranch,
            trigger: trigger ?? existing?.trigger,
            prNumber: existing?.prNumber,
            prTitle: existing?.prTitle,
            status: statusString,
            htmlUrl: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)",
            startedAt: originalStartedAt,
            completedAt: completedAt,
            targetGitHubIds: existing?.targetGitHubIds ?? []
        )

        var newRecent = recentWorkflows
        if let idx = newRecent.firstIndex(where: { $0.runId == runId && $0.status == "in_progress" }) {
            newRecent[idx] = completedRun
        } else {
            newRecent.insert(completedRun, at: 0)
        }
        if newRecent.count > 10 { newRecent = Array(newRecent.prefix(10)) }

        var update = WorkflowCompletedUpdate(
            runStatus: nil,
            shouldResetStatus: false,
            runningWorkflows: newRunning,
            recentWorkflows: newRecent,
            lastEvent: nil,
            notification: nil
        )

        if isActualFailure {
            update.runStatus = .failure
        } else if succeeded {
            update.runStatus = .success
        }
        if isActualFailure || succeeded { update.shouldResetStatus = true }

        if isActualFailure {
            let wfName = name ?? "Workflow"
            let url = URL(string: htmlUrl ?? "https://github.com/\(repo)/actions/runs/\(runId)")
            update.lastEvent = PunishmentEvent(
                culprit: actor, repo: repo, runId: runId,
                workflowName: wfName,
                workflowURL: url,
                date: Date()
            )
            update.notification = (
                title: "Workflow Failed",
                body: "\(wfName) failed for \(actor) in \(shortRepo(repo))",
                subtitle: "Run #\(runId)",
                url: url
            )
        }

        return update
    }
}
