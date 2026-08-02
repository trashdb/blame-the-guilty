import Foundation

/// Detects PRs that transition INTO a ready-to-merge state and fires a
/// notification for each, deduplicated while the PR stays ready. A PR that
/// stops being ready is forgotten, so it can notify again if it regresses
/// (new commits) and becomes ready once more.
final class ReadyMergeNotifier {
    private var readyNotifiedPRs: Set<String> = []
    private var didSeed = false
    private let notify: (_ title: String, _ body: String, _ subtitle: String, _ url: URL?) -> Void

    init(notify: @escaping (_ title: String, _ body: String, _ subtitle: String, _ url: URL?) -> Void) {
        self.notify = notify
    }

    /// A PR is "ready to merge" when it's open, not a draft, CI + review are
    /// green (`ciStatus == "ready"` means approved + checks passing), and GitHub
    /// doesn't report conflicts.
    static func isReadyToMerge(_ pr: PullRequest) -> Bool {
        guard pr.status == "open", !pr.draft, !pr.isMerged else { return false }
        guard pr.ciStatus == "ready" else { return false }
        if let state = pr.mergeableState, state == "dirty" || state == "behind" { return false }
        return true
    }

    func reset() {
        readyNotifiedPRs = []
        didSeed = false
    }

    /// Runs on every PR sync (30s poll + SignalR events). The first sync only
    /// seeds the set so we don't spam notifications for already-ready PRs on launch.
    func process(current: [PullRequest]) {
        let currentIds = Set(current.map { $0.id })

        if !didSeed {
            didSeed = true
            readyNotifiedPRs = Set(current.filter { Self.isReadyToMerge($0) }.map { $0.id })
            return
        }

        for pr in current where Self.isReadyToMerge(pr) {
            if readyNotifiedPRs.insert(pr.id).inserted {
                notify(
                    "PR #\(pr.prNumber) ready to merge 🚀",
                    pr.title,
                    shortRepo(pr.repo),
                    pr.prUrl
                )
            }
        }
        // Allow re-notification if a PR stops being ready (e.g. new commits), and
        // forget PRs that are gone (merged/closed).
        readyNotifiedPRs = readyNotifiedPRs.intersection(currentIds)
        for pr in current where !Self.isReadyToMerge(pr) {
            readyNotifiedPRs.remove(pr.id)
        }
    }
}
