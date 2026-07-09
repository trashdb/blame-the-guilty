import SwiftUI

private struct PRDetailsResponse: Decodable {
    let mergeableState: String?
    let behindBy: Int?
    let aheadBy: Int?
}

struct PRDetailView: View {
    let pr: PullRequest
    let gitHubId: Int64

    @State private var behindBy: Int?
    @State private var aheadBy: Int?
    @State private var loadingDetails = false
    @State private var detailError: String?

    var mergeableInfo: (label: String, color: Color) {
        guard let state = pr.mergeableState else {
            return ("UNKNOWN", .gray)
        }
        switch state {
        case "clean":        return ("READY TO MERGE", .green)
        case "behind":       return ("BEHIND BASE", .orange)
        case "dirty":        return ("HAS CONFLICTS", .red)
        case "unstable":     return ("CHECKS FAILING", .yellow)
        case "has_hooks":    return ("PENDING", .blue)
        case "unknown":      return ("CHECKING...", .gray)
        default:             return (state.uppercased(), .gray)
        }
    }

    var ciInfo: (label: String, color: Color) {
        switch pr.ciStatus {
        case "waiting": return ("CI WAITING", .orange)
        case "failed":  return ("CI FAIL", .red)
        case "review":  return ("CI READY", .blue)
        default:        return ("CI READY", .green)
        }
    }

    var approvalInfo: (label: String, color: Color)? {
        if pr.reviewApproved {
            return ("APPROVED", .green)
        }
        if pr.ciStatus == "ready" && !pr.reviewApproved {
            return nil // already green
        }
        return nil
    }

    var conclusionInfo: (label: String, color: Color)? {
        guard let c = pr.conclusion else { return nil }
        switch c {
        case "success": return ("CHECKS PASS", .green)
        case "failure": return ("CHECKS FAIL", .red)
        case "neutral": return ("CHECKS NEUTRAL", .gray)
        default:        return (c.uppercased(), .secondary)
        }
    }

    var compareUrl: URL {
        URL(string: "https://github.com/\(pr.repo)/compare/\(pr.baseBranch)...\(pr.headBranch)")!
    }

    var checksUrl: URL {
        URL(string: "\(pr.prUrl)/checks")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Spacer()
                linkButton("Open PR", url: pr.prUrl)
                linkButton("Compare", url: compareUrl)
                linkButton("Checks", url: checksUrl)
            }

            HStack(spacing: 6) {
                let m = mergeableInfo
                Text(m.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(m.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(m.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))

                let c = ciInfo
                Text(c.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(c.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(c.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))

                if let cl = conclusionInfo {
                    Text(cl.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(cl.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(cl.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }

                if let a = approvalInfo {
                    Text(a.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(a.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(a.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }

                Spacer()
            }

            Text(pr.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text(shortRepo(pr.repo))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("→")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(pr.baseBranch)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 4) {
                Text("head:")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text(pr.headBranch)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("PR #\(pr.prNumber)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if pr.draft {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                    Text("Draft")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                }
            }

            if loadingDetails {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Loading details...")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else if let error = detailError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
            } else if let behind = behindBy, let ahead = aheadBy {
                Divider()
                HStack(spacing: 12) {
                    if behind > 0 {
                        Label("\(behind) behind", systemImage: "arrow.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Label("Up to date", systemImage: "checkmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    if ahead > 0 {
                        Label("\(ahead) ahead", systemImage: "arrow.up")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 320, height: 260)
        .onAppear(perform: loadDetails)
    }

    private func linkButton(_ label: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    private func loadDetails() {
        let repoEscaped = pr.repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pr.repo
        guard let url = URL(string: "\(backendUrl)/api/pullrequests/\(pr.prNumber)/detail?repo=\(repoEscaped)&gitHubId=\(gitHubId)") else { return }
        loadingDetails = true
        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                loadingDetails = false
                if let err { detailError = err.localizedDescription; return }
                guard let data else { return }
                if let decoded = try? JSONDecoder().decode(PRDetailsResponse.self, from: data) {
                    behindBy = decoded.behindBy
                    aheadBy = decoded.aheadBy
                }
            }
        }.resume()
    }
}
