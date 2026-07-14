import Foundation

struct ScannedRepo: Identifiable {
    let id = UUID()
    let path: String
    var branches: [GitBranch]
    var remoteBranches: [RemoteBranch]
    var isExpanded: Bool
    var error: String?
}

struct GitBranch: Identifiable {
    let id = UUID()
    let name: String
    let isCurrent: Bool
}

struct RemoteBranch: Identifiable {
    let id = UUID()
    let name: String
    let isMerged: Bool
}

struct APIBranch: Codable {
    let name: String
}

actor GitService {
    enum GitError: LocalizedError {
        case gitNotFound
        case commandFailed(String)
        var errorDescription: String? {
            switch self {
            case .gitNotFound: return "Git not found"
            case .commandFailed(let s): return s
            }
        }
    }

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
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove("/")
        guard let encoded = fullName.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "\(backendUrl)/api/github/my-branches?gitHubId=\(gitHubId)&repo=\(encoded)") else {
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
        guard let output = try? await runGitSimple(args: ["config", "--global", "user.email"]) else { return nil }
        let email = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? nil : email
    }

    func listMyBranches(repoPath: String) async throws -> [(name: String, isCurrent: Bool)] {
        let myEmail = await currentUserEmail()
        let allBranches = try await listBranches(repoPath: repoPath)
        guard let email = myEmail else { return allBranches }
        let baseRef = await baseRefName(repoPath: repoPath)
        let currentBranch = (try? await runGit(repoPath: repoPath, args: ["rev-parse", "--abbrev-ref", "HEAD"]))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        var filtered: [(name: String, isCurrent: Bool)] = []
        for b in allBranches {
            if b.isCurrent { filtered.append(b); continue }
            if let baseRef {
                if let out = try? await runGit(repoPath: repoPath, args: ["log", "--oneline", "\(baseRef)..\(b.name)", "--author=\(email)"]),
                   !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filtered.append(b)
                } else if let out2 = try? await runGit(repoPath: repoPath, args: ["log", "--oneline", b.name, "--author=\(email)"]),
                          !out2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filtered.append(b)
                }
            } else if let out2 = try? await runGit(repoPath: repoPath, args: ["log", "--oneline", b.name, "--author=\(email)"]),
                      !out2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                filtered.append(b)
            }
        }
        return filtered.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func repoName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
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

    @discardableResult
    private func runGit(repoPath: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { process in
                let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errorOutput = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: GitError.commandFailed(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                    return
                }
                continuation.resume(returning: output)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
