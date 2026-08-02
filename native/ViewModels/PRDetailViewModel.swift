import Combine
import Foundation
import SwiftUI

@MainActor
final class PRDetailViewModel: ObservableObject {
    let pr: PullRequest
    let gitHubId: Int64
    private let api: ApiClientProtocol
    private let signalR: SignalRServiceProtocol
    private let onDraftChanged: ((Bool) -> Void)?

    @Published var behindBy: Int?
    @Published var aheadBy: Int?
    @Published var detailError: String?
    @Published var merging = false
    @Published var mergeResult: String?
    @Published var mergeError: String?
    @Published var updatingBranch = false
    @Published var branchUpdateResult: String?
    @Published var branchUpdateError: String?
    @Published var togglingDraft = false
    @Published var draftError: String?
    @Published var localDraft: Bool
    @Published var selectedTab = 0
    @Published var commits: [ApiCommitInfo] = []
    @Published var files: [ApiFileInfo] = []
    @Published var checks: [ApiCheckInfo] = []
    @Published var loadingCommits = false
    @Published var loadingFiles = false
    @Published var loadingChecks = false
    @Published var commitsError: String?
    @Published var filesError: String?
    @Published var checksError: String?
    @Published var mergeMethod = "squash"

    init(pr: PullRequest,
         gitHubId: Int64,
         optimisticDraft: Bool?,
         api: ApiClientProtocol,
         signalR: SignalRServiceProtocol,
         onDraftChanged: ((Bool) -> Void)?) {
        self.pr = pr
        self.gitHubId = gitHubId
        self.api = api
        self.signalR = signalR
        self.onDraftChanged = onDraftChanged
        self.localDraft = optimisticDraft ?? pr.draft
    }

    var canMerge: Bool {
        !localDraft && pr.ciStatus == "ready" && pr.reviewApproved
    }

    // MARK: - Details

    func loadDetails() {
        Task {
            let result = await api.fetchPRDetails(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId)
            switch result {
            case .success(let details):
                withAnimation(DS.Animation.default) {
                    behindBy = details.behindBy
                    aheadBy = details.aheadBy
                }
                if details.behindBy == 0 {
                    branchUpdateResult = nil
                    branchUpdateError = nil
                }
                if let backendDraft = details.draft, !togglingDraft, backendDraft != localDraft {
                    localDraft = backendDraft
                    onDraftChanged?(backendDraft)
                }
            case .failure(let message):
                detailError = message
            }
        }
    }

    // MARK: - Commits / Files / Checks

    func loadCommits() {
        loadingCommits = true
        commitsError = nil
        Task {
            let result = await api.fetchCommits(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId)
            loadingCommits = false
            switch result {
            case .success(let items): commits = items
            case .failure(let message): commitsError = message
            }
        }
    }

    func loadFiles() {
        loadingFiles = true
        filesError = nil
        Task {
            let result = await api.fetchFiles(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId)
            loadingFiles = false
            switch result {
            case .success(let items): files = items
            case .failure(let message): filesError = message
            }
        }
    }

    func loadChecks() {
        loadingChecks = true
        checksError = nil
        Task {
            let result = await api.fetchChecks(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId)
            loadingChecks = false
            switch result {
            case .success(let items): checks = items
            case .failure(let message): checksError = message
            }
        }
    }

    // MARK: - Actions

    func performMerge() {
        merging = true
        mergeResult = nil
        mergeError = nil
        Task {
            guard let resp = await api.mergePR(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId, method: mergeMethod) else {
                merging = false
                mergeError = "Merge failed"
                return
            }
            merging = false
            if resp.merged {
                mergeResult = resp.message ?? "Merged"
            } else {
                mergeError = resp.error ?? resp.message ?? "Merge failed"
            }
        }
    }

    func performToggleDraft(_ makeDraft: Bool) {
        let previousDraft = localDraft
        localDraft = makeDraft
        onDraftChanged?(makeDraft)
        draftError = nil
        togglingDraft = true

        Task {
            let error = await api.setDraft(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId, draft: makeDraft)
            togglingDraft = false
            if let error {
                localDraft = previousDraft
                onDraftChanged?(previousDraft)
                draftError = error
            }
        }
    }

    func performUpdateBranch() {
        updatingBranch = true
        branchUpdateResult = nil
        branchUpdateError = nil
        Task {
            let result = await api.updateBranch(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId)
            updatingBranch = false
            switch result {
            case .updated(let message):
                branchUpdateResult = message
            case .sent:
                branchUpdateResult = "Update sent (check PR on GitHub)"
            case .failed(let message):
                branchUpdateError = message
                return
            }
            scheduleReloadDetails()
        }
    }

    private func scheduleReloadDetails() {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            loadDetails()
        }
    }

    func performSubscribe() async {
        _ = await signalR.subscribeToPR(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId)
    }

    func performUnsubscribe() async {
        _ = await signalR.unsubscribeFromPR(prNumber: pr.prNumber, repo: pr.repo, gitHubId: gitHubId)
    }
}
