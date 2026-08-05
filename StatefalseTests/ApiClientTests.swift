import XCTest
@testable import Statefalse

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let (response, data) = try handler(request)
            MockURLProtocol.lastRequest = request
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ApiClientTests: XCTestCase {
    private func makeClient() -> LiveApiClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return LiveApiClient(baseUrl: "http://localhost:5000", session: URLSession(configuration: config))
    }

    private func jsonResponse(_ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: URL(string: "http://localhost:5000")!,
                         statusCode: status,
                         httpVersion: nil,
                         headerFields: ["Content-Type": "application/json"])!,
         Data(body.utf8))
    }

    private func queryItem(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    // MARK: - URL construction

    func testDetailRequestBuildsPathAndQuery() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "{}") }
        _ = await makeClient().fetchPRDetails(prNumber: 7, repo: "owner/repo")
        let url = MockURLProtocol.lastRequest!.url!
        XCTAssertEqual(url.path, "/api/pullrequests/7/detail")
        XCTAssertEqual(queryItem("repo", in: url), "owner/repo")
        XCTAssertNil(queryItem("gitHubId", in: url))
    }

    // MARK: - fetchPRDetails

    func testFetchPRDetailsDecodesSuccess() async {
        MockURLProtocol.handler = { _ in
            self.jsonResponse(200, #"{"mergeableState":"clean","behindBy":0,"aheadBy":3,"draft":false}"#)
        }
        let result = await makeClient().fetchPRDetails(prNumber: 7, repo: "owner/repo")
        guard case .success(let details) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(details.mergeableState, "clean")
        XCTAssertEqual(details.aheadBy, 3)
        XCTAssertEqual(details.draft, false)
    }

    func testFetchPRDetailsFailureOnBadBody() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "not json") }
        let result = await makeClient().fetchPRDetails(prNumber: 7, repo: "owner/repo")
        guard case .failure(let message) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertTrue(message.hasPrefix("Parse error"))
    }

    // MARK: - fetchList

    func testFetchCommitsDecodesList() async {
        MockURLProtocol.handler = { _ in
            self.jsonResponse(200, #"[{"sha":"abc","message":"Fix","authorName":"Alice","authorLogin":"alice","date":null,"url":null}]"#)
        }
        let result = await makeClient().fetchCommits(prNumber: 7, repo: "owner/repo")
        guard case .success(let commits) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].sha, "abc")
        XCTAssertEqual(commits[0].authorLogin, "alice")
    }

    func testFetchListFailureSurfacesBackendError() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(500, #"{"error":"boom"}"#) }
        let result = await makeClient().fetchFiles(prNumber: 7, repo: "owner/repo")
        guard case .failure(let message) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertTrue(message.contains("boom"))
    }

    func testFetchChecksDecodesNullableFields() async {
        MockURLProtocol.handler = { _ in
            self.jsonResponse(200, #"[{"name":"CI","status":"completed","conclusion":"success","startedAt":"2024-01-01T10:00:00Z","completedAt":null,"url":null}]"#)
        }
        let result = await makeClient().fetchChecks(prNumber: 7, repo: "owner/repo")
        guard case .success(let checks) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(checks[0].name, "CI")
        XCTAssertEqual(checks[0].conclusion, "success")
    }

    // MARK: - subscribers

    func testFetchSubscribersDecodesWrapper() async {
        MockURLProtocol.handler = { _ in
            self.jsonResponse(200, #"{"subscribers":[{"gitHubId":1,"gitHubUsername":"alice","avatarUrl":"u1"}]}"#)
        }
        let result = await makeClient().fetchSubscribers(prNumber: 7, repo: "owner/repo")
        guard case .success(let subscribers) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(subscribers.count, 1)
        XCTAssertEqual(subscribers[0].gitHubUsername, "alice")
    }

    func testFetchAvailableUsersDecodesList() async {
        MockURLProtocol.handler = { _ in
            self.jsonResponse(200, #"[{"gitHubId":2,"login":"bob","avatarUrl":"u2"}]"#)
        }
        let result = await makeClient().fetchAvailableUsers()
        guard case .success(let users) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(users[0].login, "bob")
    }

    // MARK: - merge / draft

    func testMergePRDecodesResponse() async {
        MockURLProtocol.handler = { _ in
            self.jsonResponse(200, #"{"merged":true,"sha":"def","message":null,"error":null}"#)
        }
        let response = await makeClient().mergePR(prNumber: 7, repo: "owner/repo", method: "squash")
        XCTAssertEqual(response?.merged, true)
        XCTAssertEqual(response?.sha, "def")
    }

    func testSetDraftReturnsNilOnSuccess() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "") }
        let error = await makeClient().setDraft(prNumber: 7, repo: "owner/repo", draft: true)
        XCTAssertNil(error)
    }

    func testSetDraftReturnsHTTPError() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(500, "") }
        let error = await makeClient().setDraft(prNumber: 7, repo: "owner/repo", draft: false)
        XCTAssertEqual(error, "HTTP 500")
    }

    // MARK: - updateBranch

    func testUpdateBranchMessage() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, #"{"message":"updated"}"#) }
        let result = await makeClient().updateBranch(prNumber: 7, repo: "owner/repo")
        guard case .updated(let message) = result else {
            return XCTFail("expected updated, got \(result)")
        }
        XCTAssertEqual(message, "updated")
    }

    func testUpdateBranchSentOnBare2xx() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "") }
        let result = await makeClient().updateBranch(prNumber: 7, repo: "owner/repo")
        guard case .sent = result else {
            return XCTFail("expected sent, got \(result)")
        }
    }

    func testUpdateBranchFailureSurfacesBackendError() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(400, #"{"error":"conflict"}"#) }
        let result = await makeClient().updateBranch(prNumber: 7, repo: "owner/repo")
        guard case .failed(let message) = result else {
            return XCTFail("expected failed, got \(result)")
        }
        XCTAssertEqual(message, "conflict")
    }

    // MARK: - subscriber mutation

    func testAddSubscriberReturnsBackendErrorOn4xx() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(403, #"{"error":"not allowed"}"#) }
        let error = await makeClient().addSubscriber(prNumber: 7, repo: "owner/repo", subscriberId: 9)
        XCTAssertEqual(error, "not allowed")
    }

    func testRemoveSubscriberNilOnSuccess() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "") }
        let error = await makeClient().removeSubscriber(prNumber: 7, repo: "owner/repo", subscriberId: 9)
        XCTAssertNil(error)
    }

    // MARK: - parseISO8601

    func testParseISO8601HandlesFormats() {
        let withFractional = ApiJSON.parseISO8601("2024-01-01T10:00:00.123Z")
        XCTAssertNotNil(withFractional)
        XCTAssertEqual(withFractional!.timeIntervalSince1970, 1_704_103_200, accuracy: 1)

        let plain = ApiJSON.parseISO8601("2024-01-01T10:00:00Z")
        XCTAssertNotNil(plain)
        XCTAssertEqual(plain!.timeIntervalSince1970, 1_704_103_200, accuracy: 1)

        XCTAssertNotNil(ApiJSON.parseISO8601("2024-01-01 10:00:00"))
        XCTAssertNil(ApiJSON.parseISO8601("garbage"))
    }

    // MARK: - 401 session-expiry detection

    func test401FiresOnUnauthorizedOncePerToken() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(401, #"{"error":"unauthorized"}"#) }
        let client = makeClient()
        client.authToken = "jwt"
        var calls = 0
        client.onUnauthorized = { calls += 1 }
        _ = await client.fetchMe()
        _ = await client.fetchMe()
        XCTAssertEqual(calls, 1, "should fire only once per token")
    }

    func testNewTokenResetsUnauthorizedGuard() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(401, "") }
        let client = makeClient()
        client.authToken = "jwt-1"
        var calls = 0
        client.onUnauthorized = { calls += 1 }
        _ = await client.fetchMe()
        client.authToken = "jwt-2"
        _ = await client.fetchMe()
        XCTAssertEqual(calls, 2, "new token should reset the once-per-token guard")
    }

    func testNon401DoesNotFireOnUnauthorized() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(500, "") }
        let client = makeClient()
        client.authToken = "jwt"
        var calls = 0
        client.onUnauthorized = { calls += 1 }
        _ = await client.fetchMe()
        XCTAssertEqual(calls, 0)
    }

    // MARK: - workflow run management

    func testRerunWorkflowNilOn200() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "") }
        let error = await makeClient().rerunWorkflow(runId: 42)
        XCTAssertNil(error)
    }

    func testRerunWorkflowReturnsErrorOnFailure() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(500, #"{"error":"boom"}"#) }
        let error = await makeClient().rerunWorkflow(runId: 42)
        XCTAssertEqual(error, "HTTP 500: {\"error\":\"boom\"}")
    }

    func testSetTargetGitHubIdsTrueOn200() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "") }
        let ok = await makeClient().setTargetGitHubIds(dbId: 9, targetIds: [1, 2])
        XCTAssertTrue(ok)
    }

    func testSetTargetGitHubIdsFalseOn4xx() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(400, "") }
        let ok = await makeClient().setTargetGitHubIds(dbId: 9, targetIds: [1, 2])
        XCTAssertFalse(ok)
    }

    // MARK: - webhook logs

    func testFetchWebhookLogsDecodes() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, #"[{"eventType":"workflow_run","action":null,"repo":"owner/repo","workflowName":"CI","outcome":"processed","message":null,"occurredAt":"2026-08-01T10:00:00Z"}]"#) }
        let logs = await makeClient().fetchWebhookLogs(limit: 50)
        XCTAssertEqual(logs?.first?.eventType, "workflow_run")
        XCTAssertNotNil(logs?.first?.occurredAt)
    }

    // MARK: - auth helpers

    func testSavePATUsesCustomBackendUrl() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, "") }
        let client = makeClient()
        client.authToken = "jwt"
        _ = await client.savePAT(patToken: "ghp_abc", to: "https://custom.example.com")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://custom.example.com/api/auth/pat")
    }

    // MARK: - PR preview

    func testFetchPRPreviewSuccess() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(200, #"{"summary":"s","suggestedBody":"b","summaryError":null}"#) }
        let result = await makeClient().fetchPRPreview(repo: "owner/repo", head: "feature/x", baseBranch: "main", title: "Title", useAI: false)
        guard case .success(let preview) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(preview.summary, "s")
        XCTAssertEqual(preview.suggestedBody, "b")
    }

    func testFetchPRPreviewFailureOn4xx() async {
        MockURLProtocol.handler = { _ in self.jsonResponse(500, #"{"error":"boom"}"#) }
        let result = await makeClient().fetchPRPreview(repo: "owner/repo", head: "feature/x", baseBranch: "main", title: "Title", useAI: false)
        guard case .failure(let message) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        XCTAssertEqual(message, "boom")
    }
}
