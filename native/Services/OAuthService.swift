import AppKit
import Foundation
import Network

class OAuthService {
    func startLogin(backendUrl: String) async throws -> (id: Int64, username: String) {
        try await withCheckedThrowingContinuation { continuation in
            let port = UInt16.random(in: 49152...65535)
            let redirectUri = "http://localhost:\(port)/callback"
            let loginUrl = "\(backendUrl)/api/auth/login?redirect_uri=\(redirectUri)"

            do {
                let listener = try NWListener(using: .tcp, on: .init(rawValue: port)!)

                final class Flag: @unchecked Sendable { var value = false }
                let handled = Flag()

                listener.stateUpdateHandler = { state in
                    if case .failed = state, !handled.value {
                        handled.value = true
                        continuation.resume(throwing: OAuthError.failed)
                    }
                }

                listener.newConnectionHandler = { connection in
                    guard !handled.value else {
                        connection.cancel()
                        return
                    }
                    handled.value = true

                    connection.start(queue: .main)

                    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                        guard let data = data,
                              let request = String(data: data, encoding: .utf8) else {
                            connection.cancel()
                            listener.cancel()
                            continuation.resume(throwing: OAuthError.failed)
                            return
                        }

                        guard let path = request.split(separator: " ").dropFirst().first,
                              let query = path.split(separator: "?").last,
                              let components = URLComponents(string: "://localhost?" + String(query)),
                              let idStr = components.queryItems?.first(where: { $0.name == "id" })?.value,
                              let id = Int64(idStr),
                              let username = components.queryItems?.first(where: { $0.name == "username" })?.value else {
                            connection.cancel()
                            listener.cancel()
                            continuation.resume(throwing: OAuthError.failed)
                            return
                        }

                        let body = """
                        <!DOCTYPE html>
                        <html lang="en">
                        <head>
                          <meta charset="UTF-8">
                          <meta name="viewport" content="width=device-width, initial-scale=1.0">
                          <title>Blame the Guilty</title>
                          <style>
                            *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
                            body {
                              min-height: 100vh; display: flex; align-items: center; justify-content: center;
                              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                              background: #0d0d0d; color: #f0f0f0;
                            }
                            .card {
                              text-align: center; padding: 56px 64px;
                              background: #1a1a1a; border: 1px solid #2a2a2a;
                              border-radius: 20px; box-shadow: 0 32px 80px rgba(0,0,0,0.6);
                              max-width: 440px; width: 90%;
                              animation: fadeUp 0.5s cubic-bezier(0.16,1,0.3,1) both;
                            }
                            @keyframes fadeUp {
                              from { opacity: 0; transform: translateY(24px); }
                              to   { opacity: 1; transform: translateY(0); }
                            }
                            .icon-wrap {
                              width: 80px; height: 80px;
                              background: rgba(52,199,89,0.12); border-radius: 50%;
                              display: flex; align-items: center; justify-content: center;
                              margin: 0 auto 28px;
                              animation: pop 0.4s 0.3s cubic-bezier(0.16,1,0.3,1) both;
                            }
                            @keyframes pop {
                              from { transform: scale(0.4); opacity: 0; }
                              to   { transform: scale(1);   opacity: 1; }
                            }
                            .checkmark {
                              width: 36px; height: 36px; stroke: #34c759; stroke-width: 3;
                              fill: none; stroke-linecap: round; stroke-linejoin: round;
                              stroke-dasharray: 60; stroke-dashoffset: 60;
                              animation: draw 0.5s 0.5s ease forwards;
                            }
                            @keyframes draw { to { stroke-dashoffset: 0; } }
                            .badge {
                              display: inline-flex; align-items: center; gap: 6px;
                              font-size: 11px; font-weight: 600; letter-spacing: 0.08em;
                              text-transform: uppercase; color: #cc3333;
                              background: rgba(204,51,51,0.12);
                              border: 1px solid rgba(204,51,51,0.25);
                              border-radius: 100px; padding: 4px 12px; margin-bottom: 20px;
                            }
                            h1 { font-size: 22px; font-weight: 700; letter-spacing: -0.3px; margin-bottom: 10px; }
                            p { font-size: 14px; color: #888; line-height: 1.6; }
                            .divider { height: 1px; background: #2a2a2a; margin: 28px 0; }
                            .hint { font-size: 12px; color: #555; }
                          </style>
                        </head>
                        <body>
                          <div class="card">
                            <div class="icon-wrap">
                              <svg class="checkmark" viewBox="0 0 24 24">
                                <polyline points="20 6 9 17 4 12"/>
                              </svg>
                            </div>
                            <div class="badge">⚠ Blame the Guilty</div>
                            <h1>Authentication successful</h1>
                            <p>You're now connected to the CI/CD punishment system.<br>You may close this tab.</p>
                            <div class="divider"></div>
                            <span class="hint">The menu bar app is now active and watching for failures.</span>
                          </div>
                        </body>
                        </html>
                        """
                        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"

                        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                            listener.cancel()
                            continuation.resume(returning: (id, username))
                        })
                    }
                }

                Task {
                    try? await Task.sleep(for: .seconds(120))
                    if !handled.value {
                        handled.value = true
                        continuation.resume(throwing: OAuthError.timeout)
                    }
                }

                listener.start(queue: .main)
                NSWorkspace.shared.open(URL(string: loginUrl)!)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum OAuthError: Error {
        case failed
        case timeout
    }
}
