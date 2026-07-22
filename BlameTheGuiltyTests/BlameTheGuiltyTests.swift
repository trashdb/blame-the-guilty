import Foundation
import Testing
@testable import BlameTheGuilty

// ──────────────────────────────────────────────
// PullRequest
// ──────────────────────────────────────────────

@Test("PullRequest.id format")
func prID() {
    let pr = PullRequest(
        prNumber: 42, title: "", repo: "owner/repo",
        headBranch: "", baseBranch: "", htmlUrl: nil,
        status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    #expect(pr.id == "owner/repo#42")
    #expect(!pr.isMerged)
}

@Test("PullRequest.isMerged")
func prMerged() {
    let pr = PullRequest(
        prNumber: 1, title: "", repo: "r", headBranch: "", baseBranch: "",
        htmlUrl: nil, status: "merged", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    #expect(pr.isMerged)
}

@Test("PullRequest.prUrl uses htmlUrl when present")
func prUrlWithHtml() {
    let pr = PullRequest(
        prNumber: 1, title: "", repo: "r", headBranch: "", baseBranch: "",
        htmlUrl: URL(string: "https://github.com/r/pull/1"),
        status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    #expect(pr.prUrl.absoluteString == "https://github.com/r/pull/1")
}

@Test("PullRequest.prUrl fallback when htmlUrl is nil")
func prUrlFallback() {
    let pr = PullRequest(
        prNumber: 42, title: "", repo: "owner/repo",
        headBranch: "", baseBranch: "", htmlUrl: nil,
        status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    #expect(pr.prUrl.absoluteString == "https://github.com/owner/repo/pull/42")
}

@Test("PullRequest equality by prNumber+repo")
func prEquality() {
    let a = PullRequest(
        prNumber: 1, title: "", repo: "r", headBranch: "", baseBranch: "",
        htmlUrl: nil, status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    let b = PullRequest(
        prNumber: 1, title: "different", repo: "r", headBranch: "", baseBranch: "",
        htmlUrl: nil, status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    #expect(a == b)
}

@Test("PullRequest inequality by prNumber")
func prInequality() {
    let a = PullRequest(
        prNumber: 1, title: "", repo: "r", headBranch: "", baseBranch: "",
        htmlUrl: nil, status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    let c = PullRequest(
        prNumber: 2, title: "", repo: "r", headBranch: "", baseBranch: "",
        htmlUrl: nil, status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    #expect(a != c)
}

@Test("PullRequest inequality by repo")
func prInequalityRepo() {
    let a = PullRequest(
        prNumber: 1, title: "", repo: "r", headBranch: "", baseBranch: "",
        htmlUrl: nil, status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    let d = PullRequest(
        prNumber: 1, title: "", repo: "other", headBranch: "", baseBranch: "",
        htmlUrl: nil, status: "open", conclusion: nil, draft: false,
        mergeableState: nil, ciStatus: "", reviewApproved: false,
        lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
        lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
    #expect(a != d)
}

@Test("PullRequest Codable roundtrip")
func prCoding() throws {
    let pr = PullRequest(
        prNumber: 42, title: "Test PR", repo: "owner/repo",
        headBranch: "feature/x", baseBranch: "main",
        htmlUrl: URL(string: "https://github.com/owner/repo/pull/42"),
        status: "open", conclusion: nil, draft: false,
        mergeableState: "mergeable", ciStatus: "success",
        reviewApproved: true, lastCommentBy: "user",
        lastCommentBody: "LGTM", lastCommentAt: Date(),
        lastCommentUrl: "https://...", lastReviewFilePath: "file.swift",
        lastReviewLine: 10)
    let data = try JSONEncoder().encode(pr)
    let decoded = try JSONDecoder().decode(PullRequest.self, from: data)
    #expect(decoded.prNumber == 42)
    #expect(decoded.repo == "owner/repo")
    #expect(decoded.ciStatus == "success")
    #expect(decoded.reviewApproved)
    #expect(decoded.lastReviewFilePath == "file.swift")
    #expect(decoded.lastReviewLine == 10)
}

// ──────────────────────────────────────────────
// WorkflowRun
// ──────────────────────────────────────────────

@Test("WorkflowRun.isRunning")
func workflowRunning() {
    let run = WorkflowRun(
        id: UUID(), dbId: nil, runId: 1, workflowName: "CI", repo: "r",
        actor: "user", headBranch: nil, trigger: nil, prNumber: nil,
        prTitle: nil, status: "in_progress", htmlUrl: "",
        startedAt: Date(), completedAt: nil, targetGitHubIds: [])
    #expect(run.isRunning)
    #expect(run.duration == nil)
}

@Test("WorkflowRun not running for completed")
func workflowNotRunning() {
    let run = WorkflowRun(
        id: UUID(), dbId: nil, runId: 1, workflowName: "CI", repo: "r",
        actor: "user", headBranch: nil, trigger: nil, prNumber: nil,
        prTitle: nil, status: "completed", htmlUrl: "",
        startedAt: Date(), completedAt: Date(), targetGitHubIds: [])
    #expect(!run.isRunning)
}

@Test("WorkflowRun completed duration")
func workflowDuration() {
    let start = Date()
    let end = start.addingTimeInterval(60)
    let run = WorkflowRun(
        id: UUID(), dbId: nil, runId: 2, workflowName: "CI", repo: "r",
        actor: "user", headBranch: nil, trigger: nil, prNumber: nil,
        prTitle: nil, status: "completed", htmlUrl: "",
        startedAt: start, completedAt: end, targetGitHubIds: [])
    #expect(!run.isRunning)
    if let d = run.duration {
        #expect(abs(d - 60) < 1)
    } else {
        Issue.record("duration should not be nil")
    }
}

@Test("WorkflowRun nil duration when not completed")
func workflowNilDuration() {
    let run = WorkflowRun(
        id: UUID(), dbId: nil, runId: 1, workflowName: "CI", repo: "r",
        actor: "user", headBranch: nil, trigger: nil, prNumber: nil,
        prTitle: nil, status: "queued", htmlUrl: "",
        startedAt: Date(), completedAt: nil, targetGitHubIds: [])
    #expect(run.duration == nil)
}

@Test("WorkflowRun status variations")
func workflowStatuses() {
    for status in ["queued", "in_progress", "completed", "failure", "cancelled", "unknown"] {
        let run = WorkflowRun(
            id: UUID(), dbId: nil, runId: 1, workflowName: "CI", repo: "r",
            actor: "user", headBranch: nil, trigger: nil, prNumber: nil,
            prTitle: nil, status: status, htmlUrl: "",
            startedAt: Date(), completedAt: nil, targetGitHubIds: [])
        let expected = (status == "in_progress")
        #expect(run.isRunning == expected)
    }
}

@Test("WorkflowRun Codable roundtrip")
func workflowCoding() throws {
    let run = WorkflowRun(
        id: UUID(), dbId: 5, runId: 123, workflowName: "CI", repo: "r",
        actor: "user", headBranch: "main", trigger: "push", prNumber: 42,
        prTitle: "Fix bug", status: "completed", htmlUrl: "https://...",
        startedAt: Date(), completedAt: Date(), targetGitHubIds: [1, 2])
    let data = try JSONEncoder().encode(run)
    let decoded = try JSONDecoder().decode(WorkflowRun.self, from: data)
    #expect(decoded.runId == 123)
    #expect(decoded.workflowName == "CI")
    #expect(decoded.prNumber == 42)
    #expect(decoded.prTitle == "Fix bug")
    #expect(decoded.targetGitHubIds == [1, 2])
}

@Test("WorkflowRun Codable with nil optionals")
func workflowCodingNil() throws {
    let run = WorkflowRun(
        id: UUID(), dbId: nil, runId: 1, workflowName: "CI", repo: "r",
        actor: "user", headBranch: nil, trigger: nil, prNumber: nil,
        prTitle: nil, status: "queued", htmlUrl: "",
        startedAt: Date(), completedAt: nil, targetGitHubIds: [])
    let data = try JSONEncoder().encode(run)
    let decoded = try JSONDecoder().decode(WorkflowRun.self, from: data)
    #expect(decoded.dbId == nil)
    #expect(decoded.headBranch == nil)
    #expect(decoded.trigger == nil)
    #expect(decoded.prNumber == nil)
    #expect(decoded.prTitle == nil)
    #expect(decoded.completedAt == nil)
    #expect(decoded.targetGitHubIds.isEmpty)
}

@Test("WorkflowRun Identifiable conformance")
func workflowIdentifiable() {
    let id = UUID()
    let run = WorkflowRun(
        id: id, dbId: nil, runId: 1, workflowName: "CI", repo: "r",
        actor: "user", headBranch: nil, trigger: nil, prNumber: nil,
        prTitle: nil, status: "queued", htmlUrl: "",
        startedAt: Date(), completedAt: nil, targetGitHubIds: [])
    #expect(run.id == id)
}

// ──────────────────────────────────────────────
// WebhookLogEntry
// ──────────────────────────────────────────────

private var isoDecoder: JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}

@Test("WebhookLogEntry decodes from JSON")
func webhookDecode() throws {
    let json = """
    {"eventType":"pull_request","action":"opened","repo":"r","workflowName":null,"outcome":"success","message":null,"occurredAt":"2026-01-15T10:00:00Z"}
    """
    let data = try #require(json.data(using: .utf8))
    let entry = try isoDecoder.decode(WebhookLogEntry.self, from: data)
    #expect(entry.eventType == "pull_request")
    #expect(entry.action == "opened")
    #expect(entry.repo == "r")
    #expect(entry.workflowName == nil)
    #expect(entry.outcome == "success")
    #expect(entry.message == nil)
}

@Test("WebhookLogEntry decodes with all fields")
func webhookDecodeFull() throws {
    let json = """
    {"eventType":"workflow_run","action":"completed","repo":"my/repo","workflowName":"CI","outcome":"failure","message":"oops","occurredAt":"2026-06-01T12:00:00Z"}
    """
    let data = try #require(json.data(using: .utf8))
    let entry = try isoDecoder.decode(WebhookLogEntry.self, from: data)
    #expect(entry.eventType == "workflow_run")
    #expect(entry.workflowName == "CI")
    #expect(entry.message == "oops")
}

@Test("WebhookLogEntry has unique id per instance")
func webhookUniqueID() throws {
    let json = """
    {"eventType":"a","action":null,"repo":null,"workflowName":null,"outcome":"ok","message":null,"occurredAt":"2026-01-01T00:00:00Z"}
    """
    let data = try #require(json.data(using: .utf8))
    let a = try isoDecoder.decode(WebhookLogEntry.self, from: data)
    let b = try isoDecoder.decode(WebhookLogEntry.self, from: data)
    #expect(a.id != b.id)
}

// ──────────────────────────────────────────────
// GitHubUserInfo
// ──────────────────────────────────────────────

@Test("GitHubUserInfo decodes from JSON")
func gitHubUserDecode() throws {
    let json = """
    {"gitHubId":42,"login":"testuser"}
    """
    let data = try #require(json.data(using: .utf8))
    let user = try JSONDecoder().decode(GitHubUserInfo.self, from: data)
    #expect(user.gitHubId == 42)
    #expect(user.login == "testuser")
    #expect(user.id == 42)
}

// ──────────────────────────────────────────────
// BranchInfo
// ──────────────────────────────────────────────

@Test("BranchInfo.ticketNumber extracts ticket from name")
func branchInfoTicket() {
    let b = BranchInfo(name: "feature/LOY-1234-something", repoPath: "", repoName: "",
                       isCurrent: false, isLocal: true, isMerged: false, isDefault: false)
    #expect(b.ticketNumber == "LOY-1234")
}

@Test("BranchInfo.ticketNumber nil when no match")
func branchInfoNoTicket() {
    let b = BranchInfo(name: "main", repoPath: "", repoName: "",
                       isCurrent: true, isLocal: true, isMerged: false, isDefault: true)
    #expect(b.ticketNumber == nil)
}

@Test("BranchInfo Identifiable conformance")
func branchInfoIdentifiable() {
    let b = BranchInfo(name: "x", repoPath: "", repoName: "",
                       isCurrent: false, isLocal: true, isMerged: false, isDefault: false)
    // id is UUID, just check it's not nil
    #expect(b.id.uuidString.isEmpty == false)
}

// ──────────────────────────────────────────────
// extractTicketNumber
// ──────────────────────────────────────────────

@Test("extractTicketNumber standard format")
func extractTicketStandard() {
    #expect(extractTicketNumber(from: "LOY-1234-fix-bug") == "LOY-1234")
}

@Test("extractTicketNumber at start")
func extractTicketStart() {
    #expect(extractTicketNumber(from: "JIRA-567-something") == "JIRA-567")
}

@Test("extractTicketNumber no match")
func extractTicketNone() {
    #expect(extractTicketNumber(from: "main") == nil)
}

@Test("extractTicketNumber lowercase prefix")
func extractTicketLower() {
    #expect(extractTicketNumber(from: "abc-123") == nil)
}

@Test("extractTicketNumber multiple digits")
func extractTicketMultiDigit() {
    #expect(extractTicketNumber(from: "PROJ-99999-task") == "PROJ-99999")
}

@Test("extractTicketNumber empty string")
func extractTicketEmpty() {
    #expect(extractTicketNumber(from: "") == nil)
}

@Test("extractTicketNumber ticket at end")
func extractTicketEnd() {
    #expect(extractTicketNumber(from: "fix/TICK-42") == "TICK-42")
}

@Test("extractTicketNumber special chars in branch")
func extractTicketSpecial() {
    #expect(extractTicketNumber(from: "feature/TICK-1_fix_bug") == "TICK-1")
}

@Test("extractTicketNumber numbers-only prefix")
func extractTicketNumbersOnly() {
    #expect(extractTicketNumber(from: "123-ABC") == nil)
}

// ──────────────────────────────────────────────
// shortRepo
// ──────────────────────────────────────────────

@Test("shortRepo extracts last component")
func shortRepoTest() {
    #expect(shortRepo("owner/repo") == "repo")
    #expect(shortRepo("repo") == "repo")
    #expect(shortRepo("a/b/c") == "b/c")
    #expect(shortRepo("") == "")
    #expect(shortRepo("/") == "")
}

// ──────────────────────────────────────────────
// GitService static
// ──────────────────────────────────────────────

@Test("GitService.repoName from local path")
func gitRepoName() {
    #expect(GitService.repoName(from: "/Users/user/projects/my-repo") == "my-repo")
}

@Test("GitService.repoName trailing slash")
func gitRepoNameTrailingSlash() {
    #expect(GitService.repoName(from: "/tmp/some-project/") == "some-project")
}

@Test("GitService.generatePRTitle strips prefixes")
func generateTitleStripsPrefix() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "feature/add-login")
    #expect(title == "Add login")
}

@Test("GitService.generatePRTitle includes ticket")
func generateTitleWithTicket() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "fix/LOY-999-crash-on-start")
    #expect(title == "[LOY-999] Loy 999 crash on start")
}

@Test("GitService.generatePRTitle without prefix")
func generateTitleNoPrefix() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "update-readme")
    #expect(title == "Update readme")
}

@Test("GitService.generatePRTitle with underscore")
func generateTitleUnderscore() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "chore/clean_up_code")
    #expect(title == "Clean up code")
}

@Test("GitService.generatePRTitle hotfix prefix")
func generateTitleHotfix() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "hotfix/ABC-1-patch")
    #expect(title == "[ABC-1] Abc 1 patch")
}

@Test("GitService.generatePRTitle bugfix prefix")
func generateTitleBugfix() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "bugfix/fix-npe")
    #expect(title == "Fix npe")
}

@Test("GitService.generatePRTitle empty branch")
func generateTitleEmpty() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "")
    #expect(title == "")
}

@Test("GitService.generatePRTitle release prefix")
func generateTitleRelease() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "release/v2.0")
    #expect(title == "V2.0")
}

@Test("GitService.generatePRTitle already formatted preserves ticket")
func generateTitleAlreadyFormatted() async {
    let git = GitService()
    let title = await git.generatePRTitle(from: "feature/[ABC-1]-Add-login")
    #expect(title == "[ABC-1] [Abc 1] Add login")
}

// ──────────────────────────────────────────────
// ScannedRepo / GitBranch / RemoteBranch
// ──────────────────────────────────────────────

@Test("ScannedRepo Identifiable conformance")
func scannedRepoID() {
    let repo = ScannedRepo(path: "/a/b", branches: [], remoteBranches: [],
                           isExpanded: false, error: nil)
    #expect(repo.id == "/a/b")
}

@Test("GitBranch Identifiable conformance")
func gitBranchID() {
    let b = GitBranch(name: "main", isCurrent: true)
    #expect(b.id == "main")
}

@Test("RemoteBranch Identifiable conformance")
func remoteBranchID() {
    let b = RemoteBranch(name: "origin/main", isMerged: false)
    #expect(b.id == "origin/main")
}

// ──────────────────────────────────────────────
// PersistenceService
// ──────────────────────────────────────────────

@Suite(.serialized) struct PersistenceSuite {
    @Test("PersistenceService roundtrip")
    func roundtrip() {
        let pr = PullRequest(
            prNumber: 1, title: "Test", repo: "r", headBranch: "", baseBranch: "",
            htmlUrl: nil, status: "open", conclusion: nil, draft: false,
            mergeableState: nil, ciStatus: "", reviewApproved: false,
            lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
            lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
        PersistenceService.save(prs: [pr])
        let loaded = PersistenceService.loadPRs()
        #expect(loaded.count == 1)
        #expect(loaded.first?.prNumber == 1)
        PersistenceService.save(prs: [])
    }

    @Test("PersistenceService empty save")
    func emptySave() {
        PersistenceService.save(prs: [])
        #expect(PersistenceService.loadPRs().isEmpty)
    }

    @Test("PersistenceService save overwrites")
    func overwrite() {
        let pr1 = PullRequest(
            prNumber: 1, title: "", repo: "r", headBranch: "", baseBranch: "",
            htmlUrl: nil, status: "open", conclusion: nil, draft: false,
            mergeableState: nil, ciStatus: "", reviewApproved: false,
            lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
            lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
        let pr2 = PullRequest(
            prNumber: 2, title: "", repo: "r", headBranch: "", baseBranch: "",
            htmlUrl: nil, status: "open", conclusion: nil, draft: false,
            mergeableState: nil, ciStatus: "", reviewApproved: false,
            lastCommentBy: nil, lastCommentBody: nil, lastCommentAt: nil,
            lastCommentUrl: nil, lastReviewFilePath: nil, lastReviewLine: nil)
        PersistenceService.save(prs: [pr1])
        PersistenceService.save(prs: [pr2])
        #expect(PersistenceService.loadPRs().count == 1)
        #expect(PersistenceService.loadPRs().first?.prNumber == 2)
        PersistenceService.save(prs: [])
    }
}

// ──────────────────────────────────────────────
// Dependencies
// ──────────────────────────────────────────────

@Test("Dependencies mock")
func depsMock() {
    let deps = Dependencies.mock()
    #expect(deps.gitService is MockGitService)
    #expect(deps.signalRService is MockSignalRService)
}

@Test("Dependencies live")
func depsLive() {
    let deps = Dependencies.live()
    #expect(deps.gitService is GitService)
}

// ──────────────────────────────────────────────
// MenuBarBadgeService
// ──────────────────────────────────────────────

@Test("MenuBarBadgeService initial state")
func badgeInit() {
    let badge = MenuBarBadgeService()
    #expect(badge.activePRCount == 0)
    #expect(badge.failedPRCount == 0)
    #expect(badge.runningWorkflowCount == 0)
    #expect(badge.draftCount == 0)
    #expect(badge.waitingCount == 0)
    #expect(badge.reviewCount == 0)
    #expect(badge.readyCount == 0)
    #expect(badge.mergedCount == 0)
    #expect(badge.currentBranches.isEmpty)
    #expect(badge.connectionState == .disconnected)
}

@Test("MenuBarBadgeService iconName is always flame.fill")
func badgeIconName() {
    let badge = MenuBarBadgeService()
    #expect(badge.iconName == "flame.fill")
}

// ──────────────────────────────────────────────
// CachedBranch
// ──────────────────────────────────────────────

@Test("CachedBranch basic construction")
func cachedBranchBasic() {
    let cb = CachedBranch(name: "feature/LOY-1-x", repoPath: "/a/b", repoName: "b", ticketNumber: "LOY-1")
    #expect(cb.name == "feature/LOY-1-x")
    #expect(cb.repoPath == "/a/b")
    #expect(cb.repoName == "b")
    #expect(cb.ticketNumber == "LOY-1")
}

@Test("CachedBranch nil ticket")
func cachedBranchNilTicket() {
    let cb = CachedBranch(name: "main", repoPath: "/a/b", repoName: "b", ticketNumber: nil)
    #expect(cb.ticketNumber == nil)
}

// ──────────────────────────────────────────────
// APIBranch
// ──────────────────────────────────────────────

@Test("APIBranch Codable")
func apiBranchCoding() throws {
    let json = #"{"name":"feature/test"}"#
    let data = try #require(json.data(using: .utf8))
    let branch = try JSONDecoder().decode(APIBranch.self, from: data)
    #expect(branch.name == "feature/test")
}

// ──────────────────────────────────────────────
// PunishmentEvent
// ──────────────────────────────────────────────

@Test("PunishmentEvent basic construction")
func punishmentEvent() {
    let url = URL(string: "https://example.com")
    let event = PunishmentEvent(culprit: "user", repo: "r", runId: 42,
                                workflowName: "CI", workflowURL: url, date: Date())
    #expect(event.culprit == "user")
    #expect(event.repo == "r")
    #expect(event.runId == 42)
    #expect(event.workflowName == "CI")
    #expect(event.workflowURL == url)
}

// ──────────────────────────────────────────────
// TeamDefaults
// ──────────────────────────────────────────────

@Test("TeamDefaults have expected values")
func teamDefaults() {
    #expect(TeamDefaults.jiraBoardUrl == "https://easyjet.atlassian.net/browse/")
    #expect(TeamDefaults.favoriteRepo == "dcp-loyalty-monorepo")
}
