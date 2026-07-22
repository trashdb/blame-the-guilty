import Foundation
import OSLog

private let branchLog = OSLog(subsystem: "com.blametheguilty", category: "branches")

struct ScannedRepo: Identifiable {
    var id: String { path }
    let path: String
    var branches: [GitBranch]
    var remoteBranches: [RemoteBranch]
    var isExpanded: Bool
    var error: String?
}

struct GitBranch: Identifiable {
    var id: String { name }
    let name: String
    let isCurrent: Bool
}

struct RemoteBranch: Identifiable {
    var id: String { name }
    let name: String
    let isMerged: Bool
}

struct APIBranch: Codable {
    let name: String
}

private final class RunGitDone: @unchecked Sendable {
    private var _done = false
    private let lock = NSLock()
    func exchange(_ value: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let prev = _done
        _done = value
        return prev
    }
}

actor GitService: GitServiceProtocol {
    static func discoverRepos(workspacePath: String) -> [String] {
        let url = URL(fileURLWithPath: workspacePath)
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsPackageDescendants]
        ) else { return [] }
        var seen = Set<String>()
        var repos: [String] = []
        while let item = enumerator.nextObject() as? URL {
            if item.lastPathComponent == ".git" {
                let parent = item.deletingLastPathComponent().path
                if seen.insert(parent).inserted {
                    repos.append(parent)
                }
                enumerator.skipDescendants()
            }
            if item.pathComponents.count - url.pathComponents.count > 3 {
                enumerator.skipDescendants()
            }
        }
        return repos.sorted()
    }

    func listBranches(repoPath: String) async throws -> [(name: String, isCurrent: Bool)] {
        let output = try await runGit(repoPath: repoPath, args: ["branch"])
        return output.split(separator: "\n").map { line in
            let s = String(line)
            return (name: s.hasPrefix("*") ? String(s.dropFirst(2)) : String(s.dropFirst(2)),
                    isCurrent: s.hasPrefix("*"))
        }
    }

    func checkoutBranch(repoPath: String, name: String) async throws {
        try await runGit(repoPath: repoPath, args: ["checkout", name])
    }

    func hasUpstream(repoPath: String) async -> Bool {
        (try? await runGit(repoPath: repoPath, args: ["rev-parse", "--abbrev-ref", "@{u}"])) != nil
    }

    func hasUpstream(repoPath: String, branch: String) async -> Bool {
        (try? await runGit(repoPath: repoPath, args: ["rev-parse", "--verify", "origin/\(branch)"])) != nil
    }

    func pullCurrentBranch(repoPath: String, token: String? = nil) async -> PullResult {
        guard await hasUpstream(repoPath: repoPath) else { return .noUpstream }
        // Always pull over HTTPS using the token — never fall back to SSH `git pull`,
        // which fails in a GUI app with "permission denied (publickey)".
        guard let t = token ?? Self.storedPAT(),
              let fullName = await repoFullName(repoPath: repoPath),
              let branch = try? await currentBranchName(repoPath: repoPath) ?? "",
              !branch.isEmpty else {
            return .noToken
        }
        do {
            let url = "https://x-access-token:\(t)@github.com/\(fullName).git"
            try await runGit(repoPath: repoPath, args: ["fetch", url, branch])
            try await runGit(repoPath: repoPath, args: ["rebase", "FETCH_HEAD"])
            return .success
        } catch let error as GitError {
            let msg = error.localizedDescription.lowercased()
            return msg.contains("conflict") ? .conflict : .failed
        } catch {
            return .failed
        }
    }

    func deleteLocalBranch(repoPath: String, name: String) async throws {
        try await runGit(repoPath: repoPath, args: ["branch", "-D", name])
    }

    func fetchRepo(repoPath: String) async {
        let _ = try? await runGit(repoPath: repoPath, args: ["fetch", "origin", "--prune", "--no-tags", "--quiet"])
    }

    func baseRefName(repoPath: String) async -> String? {
        for candidate in ["origin/main", "origin/master", "main", "master"] {
            if (try? await runGit(repoPath: repoPath, args: ["rev-parse", "--verify", candidate])) != nil {
                return candidate.hasPrefix("origin/") ? candidate : "origin/\(candidate)"
            }
        }
        return nil
    }

    func listMyRemoteBranches(repoPath: String, email: String) async -> [(name: String, isMerged: Bool)] {
        guard let output = try? await runGit(repoPath: repoPath, args: ["branch", "-r"]) else { return [] }
        let baseRef = await baseRefName(repoPath: repoPath)
        let emailLower = email.lowercased()
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var results: [(name: String, isMerged: Bool)] = []
        for line in lines {
            if line == "origin/HEAD" || line == baseRef { continue }
            if let baseRef {
                if let out = try? await runGit(repoPath: repoPath, args: ["log", "--oneline", "\(baseRef)..\(line)", "--author=\(email)"]),
                   !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // unique commits by user — definitely theirs
                } else {
                    guard let tip = try? await runGit(repoPath: repoPath, args: ["log", "-1", "--format=%ae", line]),
                          tip.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == emailLower else { continue }
                }
            } else {
                guard let tip = try? await runGit(repoPath: repoPath, args: ["log", "-1", "--format=%ae", line]),
                      tip.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == emailLower else { continue }
            }
            let isMerged: Bool
            if let baseRef,
               let mergeOut = try? await runGit(repoPath: repoPath, args: ["log", "--oneline", "\(baseRef)..\(line)"]),
               mergeOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isMerged = true
            } else {
                isMerged = false
            }
            let displayName = line.hasPrefix("origin/") ? String(line.dropFirst(7)) : line
            results.append((name: displayName, isMerged: isMerged))
        }
        return results
    }

    func repoFullName(repoPath: String) async -> String? {
        guard let raw = try? await runGit(repoPath: repoPath, args: ["config", "--get", "remote.origin.url"]) else { return nil }
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = url.firstIndex(of: ":") {
            var after = String(url[url.index(after: colon)...])
            if after.hasSuffix(".git") { after = String(after.dropLast(4)) }
            return after
        }
        if let scheme = url.range(of: "://") {
            let afterScheme = url[scheme.upperBound...]
            if let slash = afterScheme.firstIndex(of: "/") {
                var after = String(afterScheme[afterScheme.index(after: slash)...])
                if after.hasSuffix(".git") { after = String(after.dropLast(4)) }
                return after
            }
        }
        var s = url
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        return s
    }

    func listMyRemoteBranchesViaAPI(repoPath: String, backendUrl: String, gitHubId: Int64) async -> [(name: String, isMerged: Bool)] {
        guard let fullName = await repoFullName(repoPath: repoPath) else {
            let email = await currentUserEmail() ?? ""
            return await listMyRemoteBranches(repoPath: repoPath, email: email)
        }
        guard var components = URLComponents(string: "\(backendUrl)/api/github/my-branches") else {
            let email = await currentUserEmail() ?? ""
            return await listMyRemoteBranches(repoPath: repoPath, email: email)
        }
        components.queryItems = [
            .init(name: "gitHubId", value: "\(gitHubId)"),
            .init(name: "repo", value: fullName)
        ]
        guard let url = components.url else {
            let email = await currentUserEmail() ?? ""
            return await listMyRemoteBranches(repoPath: repoPath, email: email)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let branches = try JSONDecoder().decode([APIBranch].self, from: data)
            let baseRef = await baseRefName(repoPath: repoPath)
            return await withTaskGroup(of: (String, Bool).self) { group in
                for branch in branches {
                    group.addTask {
                        let isMerged: Bool
                        if let baseRef,
                           let mergeOut = try? await self.runGit(repoPath: repoPath, args: ["log", "--oneline", "\(baseRef)..origin/\(branch.name)"]),
                           mergeOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isMerged = true
                        } else {
                            isMerged = false
                        }
                        return (branch.name, isMerged)
                    }
                }
                var results: [(name: String, isMerged: Bool)] = []
                for await (name, isMerged) in group {
                    results.append((name: name, isMerged: isMerged))
                }
                return results
            }
        } catch {
            let email = await currentUserEmail() ?? ""
            return await listMyRemoteBranches(repoPath: repoPath, email: email)
        }
    }

    func deleteRemoteBranch(repoPath: String, name: String) async throws {
        try await runGit(repoPath: repoPath, args: ["push", "origin", "--delete", name])
    }

    func createPR(repoPath: String, branchName: String, backendUrl: String, gitHubId: Int64,
                  overrideTitle: String? = nil, overrideBody: String? = nil) async throws -> CreatePRResult {
        // Check if the specific branch exists on remote
        let remoteRef = "origin/\(branchName)"
        let hasRemote = (try? await runGit(repoPath: repoPath, args: ["rev-parse", "--verify", remoteRef])) != nil
        if !hasRemote {
            throw GitError.commandFailed("Branch '\(branchName)' has no remote tracking branch.\n\nPush it first with:\ngit push -u origin \(branchName)")
        }

        guard let fullName = await repoFullName(repoPath: repoPath) else {
            throw GitError.commandFailed("Could not determine repo owner/name from git remote")
        }
        let base = await baseRefName(repoPath: repoPath) ?? "main"
        let cleanBase = base.hasPrefix("origin/") ? String(base.dropFirst(7)) : base
        let title = overrideTitle ?? generatePRTitle(from: branchName)

        guard var components = URLComponents(string: "\(backendUrl)/api/github/create-pr") else {
            throw GitError.commandFailed("Invalid URL")
        }
        components.queryItems = [
            .init(name: "gitHubId", value: "\(gitHubId)"),
            .init(name: "repo", value: fullName),
            .init(name: "head", value: branchName),
            .init(name: "baseBranch", value: cleanBase),
            .init(name: "title", value: title)
        ]
        if let body = overrideBody, !body.isEmpty {
            components.queryItems?.append(.init(name: "body", value: body))
        }
        guard let url = components.url else { throw GitError.commandFailed("Invalid URL") }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw GitError.commandFailed("No response from server")
        }

        struct PRResponse: Decodable { let prNumber: Int64; let url: String; let existing: Bool? }
        guard let result = try? JSONDecoder().decode(PRResponse.self, from: data) else {
            // Try decoding as error
            struct ErrResp: Decodable { let error: String }
            if let err = try? JSONDecoder().decode(ErrResp.self, from: data) {
                throw GitError.commandFailed(err.error)
            }
            throw GitError.commandFailed("HTTP \(http.statusCode)")
        }

        guard let prURL = URL(string: result.url) else {
            throw GitError.commandFailed("Invalid PR URL from server")
        }
        return CreatePRResult(url: prURL, isExisting: result.existing ?? false)
    }

    func generatePRTitle(from branchName: String) -> String {
        let cleaned = branchName
            .replacingOccurrences(of: #"^(feature|fix|hotfix|bugfix|chore|release)/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .enumerated()
            .map { i, word in i == 0 ? String(word).capitalized : String(word) }
            .joined(separator: " ")
        if let ticket = extractTicketNumber(from: branchName) {
            return "[\(ticket)] \(cleaned)"
        }
        return cleaned
    }

    func defaultBranchRef(repoPath: String) async -> String {
        if let out = try? await runGit(repoPath: repoPath, args: ["rev-parse", "--abbrev-ref", "origin/HEAD"]),
           !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let ref = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if ref.hasPrefix("origin/") { return ref }
            if ref == "main" || ref == "master" { return "origin/\(ref)" }
        }
        if (try? await runGit(repoPath: repoPath, args: ["rev-parse", "--verify", "main"])) != nil { return "main" }
        if (try? await runGit(repoPath: repoPath, args: ["rev-parse", "--verify", "master"])) != nil { return "master" }
        return "origin/main"
    }

    func defaultBranchName(repoPath: String) async -> String {
        let ref = await defaultBranchRef(repoPath: repoPath)
        if ref.hasPrefix("origin/") { return String(ref.dropFirst(7)) }
        return ref
    }

    func currentUserEmail() async -> String? {
        if let output = try? await runGitSimple(args: ["config", "--global", "user.email"]) {
            let email = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty { return email }
        }
        return nil
    }

    func listMyBranches(repoPath: String) async throws -> [(name: String, isCurrent: Bool)] {
        let allBranches = try await listBranches(repoPath: repoPath)
        var email = await currentUserEmail()
        if email == nil {
            if let out = try? await runGit(repoPath: repoPath, args: ["config", "user.email"]) {
                let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { email = trimmed }
            }
        }
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        os_log("[Branches] %{public}@: email=%{public}@, total=%d", log: branchLog, type: .debug,
               repoName, email ?? "nil", allBranches.count)
        let ws = CharacterSet.whitespacesAndNewlines
        // Collect all remote branch names for fast lookup
        var remoteBranches = Set<String>()
        if let out = try? await runGit(repoPath: repoPath, args: ["branch", "-r"]) {
            for line in out.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: ws)
                if trimmed.hasPrefix("origin/") {
                    remoteBranches.insert(String(trimmed.dropFirst(7)))
                }
            }
        }
        os_log("[Branches] %{public}@: remoteBranches=%d", log: branchLog, type: .debug,
               repoName, remoteBranches.count)
        var filtered: [(name: String, isCurrent: Bool)] = []
        for b in allBranches {
            if b.isCurrent { filtered.append(b); continue }
            if let email,
               let out = try? await runGit(repoPath: repoPath, args: ["log", "--oneline", b.name, "--author=\(email)"]),
               !out.trimmingCharacters(in: ws).isEmpty {
                filtered.append(b)
                continue
            }
            let onRemote = remoteBranches.contains(b.name)
            os_log("[Branches] %{public}@: %{public}@ current=%d myCommit=%d onRemote=%d → %{public}@",
                   log: branchLog, type: .debug,
                   repoName, b.name, b.isCurrent, 0, onRemote ? 1 : 0,
                   b.isCurrent || (email != nil) || !onRemote ? "INCLUDE" : "EXCLUDE")
            if !onRemote {
                filtered.append(b)
            }
        }
        return filtered.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func repoName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    static func scanCurrentBranches(workspacePath: String) async -> [CachedBranch] {
        let expanded = (workspacePath as NSString).expandingTildeInPath
        let paths = discoverRepos(workspacePath: expanded)
        let git = GitService()
        var result: [CachedBranch] = []
        for p in paths {
            if let name = await git.currentBranchName(repoPath: p) {
                result.append(CachedBranch(
                    name: name, repoPath: p,
                    repoName: repoName(from: p),
                    ticketNumber: extractTicketNumber(from: name)
                ))
            }
        }
        return result
    }

    func findRepoPath(ownerRepo: String, workspacePath: String) async -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: workspacePath),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        var candidates: [String] = []
        while let item = enumerator.nextObject() as? URL {
            let depth = item.pathComponents.count - workspacePath.components(separatedBy: "/").count
            if depth > 3 {
                enumerator.skipDescendants()
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.appendingPathComponent(".git").path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            candidates.append(item.path)
        }
        for path in candidates {
            if let origin = try? await runGitSimple(args: ["-C", path, "remote", "get-url", "origin"]) {
                let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains(ownerRepo) || trimmed.hasSuffix("/\(ownerRepo).git") {
                    return path
                }
            }
        }
        // fallback: match by directory name
        let repoName = ownerRepo.split(separator: "/").last.map(String.init) ?? ownerRepo
        return candidates.first { Self.repoName(from: $0) == repoName }
    }

    // ─── Conflict detection helpers ────────────────────────────────────────

    func fetchMainAndGetDiff(repoPath: String, lastKnownSha: String?) async -> (currentSha: String, changedFiles: [String])? {
        let _ = try? await runGit(repoPath: repoPath, args: ["fetch", "origin", "main", "--no-tags", "--quiet"])
        guard let currentSha = try? await runGit(repoPath: repoPath, args: ["rev-parse", "origin/main"]) else { return nil }
        let trimmed = currentSha.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = lastKnownSha, last != trimmed {
            let out = (try? await runGit(repoPath: repoPath, args: ["diff", "--name-only", last, "origin/main"])) ?? ""
            let files = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            return (trimmed, files)
        }
        return (trimmed, [])
    }

    func getUncommittedFiles(repoPath: String) async -> [String] {
        guard let out = try? await runGit(repoPath: repoPath, args: ["diff", "--name-only"]) else { return [] }
        let files = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        // Also include untracked files
        if let untracked = try? await runGit(repoPath: repoPath, args: ["ls-files", "--others", "--exclude-standard"]) {
            let ut = untracked.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            return Array(Set(files + ut)).sorted()
        }
        return files
    }

    func getBranchFilesAgainstBase(repoPath: String, baseRef: String) async -> [String] {
        guard let out = try? await runGit(repoPath: repoPath, args: ["diff", "--name-only", "\(baseRef)...HEAD"]) else { return [] }
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func currentBranchName(repoPath: String) async -> String? {
        try? await runGit(repoPath: repoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func updateBranch(repoPath: String, branch: String, baseBranch: String, ownerRepo: String, token: String) async throws -> String {
        try await runGit(repoPath: repoPath, args: ["fetch", "origin", "--prune", "--no-tags", "--quiet"])
        try await runGit(repoPath: repoPath, args: ["checkout", branch])
        try await runGit(repoPath: repoPath, args: ["pull", "--rebase", "origin", baseBranch])
        // Push via HTTPS using token to avoid SSH key issues
        let result = try await runGit(repoPath: repoPath, args: ["push", "https://x-access-token:\(token)@github.com/\(ownerRepo).git", branch])
        return "Branch updated: rebased \(branch) onto \(baseBranch)"
    }

    func pullBranch(repoPath: String, name: String, token: String? = nil) async throws {
        let current = try? await currentBranchName(repoPath: repoPath) ?? ""
        if current != name {
            try await runGit(repoPath: repoPath, args: ["checkout", name])
        }
        // Always pull over HTTPS using the token. We never fall back to `git pull`
        // (which would use the SSH `origin` remote) because a sandboxed GUI app has
        // no SSH agent and that fails with "permission denied (publickey)".
        guard let t = token ?? Self.storedPAT() else {
            throw GitError.commandFailed("No GitHub token available for pull. Open Settings → save your Personal Access Token, then try again.")
        }
        guard let fullName = await repoFullName(repoPath: repoPath) else {
            throw GitError.commandFailed("Could not determine the GitHub owner/repo from this repository's remote.")
        }
        let url = "https://x-access-token:\(t)@github.com/\(fullName).git"
        try await runGit(repoPath: repoPath, args: ["fetch", url, name])
        try await runGit(repoPath: repoPath, args: ["rebase", "FETCH_HEAD"])
        if let current = current, !current.isEmpty, current != name {
            try await runGit(repoPath: repoPath, args: ["checkout", current])
        }
    }

    static func fetchPAT(backendUrl: String, gitHubId: Int64) async -> String? {
        guard let url = URL(string: "\(backendUrl)/api/auth/token?gitHubId=\(gitHubId)") else { return storedPAT() }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let token = json["token"], !token.isEmpty else {
            // Backend unreachable or returned no token — fall back to the locally
            // saved PAT so pulls still work over HTTPS instead of failing to SSH.
            return storedPAT()
        }
        return token
    }

    static func storedPAT() -> String? {
        UserDefaults.standard.string(forKey: "patToken")
    }

    func createBranch(repoPath: String, from sourceBranch: String, newName: String) async throws {
        try await runGit(repoPath: repoPath, args: ["checkout", "-b", newName, sourceBranch])
    }

    private func runGitSimple(args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            let out = Pipe()
            process.standardOutput = out
            process.terminationHandler = { process in
                let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Find the SSH agent socket from launchd (GUI apps don't inherit SSH_AUTH_SOCK).
    private func resolveSSHAgentSocket() -> String? {
        if let sock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"], !sock.isEmpty {
            return sock
        }
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: "/var/run"),
              let dir = dirs.first(where: { $0.hasPrefix("com.apple.launchd.") }) else { return nil }
        let candidate = "/var/run/\(dir)/Listeners"
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    /// Look up the real hostname (HostName) for an SSH host alias from ~/.ssh/config.
    /// e.g. `github-trashdb` → `github.com`
    private func resolveSSHHostName(for alias: String) -> String? {
        let configPath = NSHomeDirectory() + "/.ssh/config"
        guard let config = try? String(contentsOfFile: configPath) else { return nil }
        let lines = config.components(separatedBy: "\n")
        var inBlock = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("host ") {
                let patterns = t.dropFirst(5).trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
                inBlock = patterns.contains(where: { $0 == alias || $0 == "*" })
            } else if inBlock && t.lowercased().hasPrefix("hostname ") {
                return String(t.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            } else if inBlock && t.lowercased().hasPrefix("host ") {
                inBlock = false
            }
        }
        return nil
    }

    /// Parse ~/.ssh/config to find the IdentityFile for the SSH host in this repo's remote URL.
    private func resolveSSHIdentityFile(for repoPath: String) -> String? {
        guard let output = try? String(contentsOfFile: "\(repoPath)/.git/config") else { return nil }
        // Find remote "origin" URL
        var foundOrigin = false
        var remoteLine: String?
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[remote") && t.contains("\"origin\"") { foundOrigin = true; continue }
            if foundOrigin {
                if t.hasPrefix("[") { break }
                if t.hasPrefix("url") {
                    let comps = t.split(separator: "=", maxSplits: 1)
                    if comps.count == 2 { remoteLine = String(comps[1]).trimmingCharacters(in: .whitespaces); break }
                }
            }
        }
        guard let url = remoteLine, url.hasPrefix("git@") else { return nil }
        let host = url.dropFirst(4).split(separator: ":").first.map(String.init) ?? ""

        // Read SSH config and find matching Host block
        let configPath = NSHomeDirectory() + "/.ssh/config"
        guard let config = try? String(contentsOfFile: configPath) else { return nil }

        var inBlock = false
        for line in config.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("host ") {
                let patterns = t.dropFirst(5).trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
                inBlock = patterns.contains(where: { $0 == host || $0 == "*" })
            } else if inBlock && t.lowercased().hasPrefix("identityfile") {
                let path = t.dropFirst(12).trimmingCharacters(in: .whitespaces)
                let expanded = path.hasPrefix("~") ? NSHomeDirectory() + path.dropFirst(1) : path
                if FileManager.default.fileExists(atPath: expanded) { return expanded }
            } else if inBlock && t.lowercased().hasPrefix("host ") {
                inBlock = false
            }
        }
        // Fallback: try common default keys
        for key in ["id_ed25519", "id_rsa", "id_ecdsa"] {
            let candidate = NSHomeDirectory() + "/.ssh/\(key)"
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    @discardableResult
    private func runGit(repoPath: String, args: [String], timeout: TimeInterval = 15) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        // GUI apps lack SSH agent environment — try agent socket, fall back to identity file
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil || env["HOME"]?.isEmpty == true {
            env["HOME"] = NSHomeDirectory()
        }
        let hasAgent = resolveSSHAgentSocket()
        if let sock = hasAgent {
            env["SSH_AUTH_SOCK"] = sock
        } else if env["GIT_SSH_COMMAND"] == nil,
                  let identityFile = resolveSSHIdentityFile(for: repoPath) {
            env["GIT_SSH_COMMAND"] = "ssh -i \(identityFile) -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no"
        }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await withCheckedThrowingContinuation { continuation in
            let done = RunGitDone()
            process.terminationHandler = { p in
                if done.exchange(true) { return }
                let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errOutput = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: GitError.commandFailed(errOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [process] in
                    if done.exchange(true) { return }
                    process.terminate()
                    continuation.resume(throwing: GitError.commandFailed("Git command timed out after \(Int(timeout))s"))
                }
            } catch {
                if done.exchange(true) { return }
                continuation.resume(throwing: error)
            }
        }
    }
}
