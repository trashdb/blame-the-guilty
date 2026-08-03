import XCTest
@testable import Statefalse

final class GitServiceTests: XCTestCase {
    private let git = GitService()

    // MARK: - extractTicketNumber

    func testExtractTicketNumberFindsTicket() {
        XCTAssertEqual(extractTicketNumber(from: "feature/JIRA-123-fix"), "JIRA-123")
        XCTAssertEqual(extractTicketNumber(from: "ABC-1-whatever"), "ABC-1")
    }

    func testExtractTicketNumberNilWhenAbsent() {
        XCTAssertNil(extractTicketNumber(from: "chore/foo"))
        XCTAssertNil(extractTicketNumber(from: "feature/login"))
    }

    func testExtractTicketNumberRequiresUppercaseTicket() {
        XCTAssertNil(extractTicketNumber(from: "feature/jira-123-fix"))
    }

    // MARK: - generatePRTitle

    func testGeneratePRTitleStripsPrefixAndCapitalizes() {
        XCTAssertEqual(git.generatePRTitle(from: "feature/login-screen"), "Login screen")
        XCTAssertEqual(git.generatePRTitle(from: "hotfix/crash-fix"), "Crash fix")
        XCTAssertEqual(git.generatePRTitle(from: "chore/release-notes"), "Release notes")
    }

    func testGeneratePRTitleHandlesUnderscores() {
        XCTAssertEqual(git.generatePRTitle(from: "feature/user_profile"), "User profile")
    }

    func testGeneratePRTitlePrependsTicket() {
        XCTAssertEqual(git.generatePRTitle(from: "fix/user-service/JIRA-45-typo"), "[JIRA-45] User service typo")
        XCTAssertEqual(git.generatePRTitle(from: "feature/ABC-10-widget"), "[ABC-10] Widget")
    }

    func testGeneratePRTitlePreservesInternalCase() {
        XCTAssertEqual(git.generatePRTitle(from: "fix/myFeature-build"), "MyFeature build")
        XCTAssertEqual(git.generatePRTitle(from: "fix/iOS-build"), "IOS build")
    }

    // MARK: - repoFullName

    func testRepoFullNameSSH() {
        XCTAssertEqual(GitService.repoFullName(fromRemoteURL: "git@github.com:owner/repo.git"), "owner/repo")
        XCTAssertEqual(GitService.repoFullName(fromRemoteURL: "git@github.com:owner/repo"), "owner/repo")
    }

    func testRepoFullNameHTTPS() {
        XCTAssertEqual(GitService.repoFullName(fromRemoteURL: "https://github.com/owner/repo.git"), "owner/repo")
        XCTAssertEqual(GitService.repoFullName(fromRemoteURL: "https://github.com/owner/repo"), "owner/repo")
    }

    func testRepoFullNameSSHScheme() {
        XCTAssertEqual(GitService.repoFullName(fromRemoteURL: "ssh://git@github.com/owner/repo.git"), "owner/repo")
    }

    func testRepoFullNameTrimsWhitespace() {
        XCTAssertEqual(GitService.repoFullName(fromRemoteURL: "  git@github.com:owner/repo.git\n"), "owner/repo")
    }

    func testRepoFullNamePlainPath() {
        XCTAssertEqual(GitService.repoFullName(fromRemoteURL: "owner/repo.git"), "owner/repo")
    }

    func testRepoNameFromPath() {
        XCTAssertEqual(GitService.repoName(from: "/Users/alice/Projects/awesome"), "awesome")
        XCTAssertEqual(GitService.repoName(from: "/tmp/repo"), "repo")
    }
}
