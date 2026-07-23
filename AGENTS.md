# AGENTS.md — Blame the Guilty

Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Fragments OK. Short synonyms. Technical terms exact. Code unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Not: "Sure! I'd be happy to help you with that."
- Yes: "Bug in auth middleware. Fix:"

Switch level: /caveman lite|full|ultra|wenyan
Stop: "stop caveman" or "normal mode"
Auto-Clarity: drop caveman for security warnings, irreversible actions, user confused.
Boundaries: code/commits/PRs written normal.

---

## Project: Blame the Guilty

GitHub PR/workflow monitor. macOS menu-bar app + .NET 10 backend + SQLite + SignalR.

### Architecture

```
[macOS SwiftUI app] <--SignalR+REST--> [ngrok] --> [Kestrel:5000 on Hetzner VPS] --> SQLite
```

### Stack

- Backend: .NET 10, ASP.NET Core, EF Core + SQLite, SignalR
- Native: Swift/SwiftUI macOS menu-bar (LSUIElement=1, no Dock)
- Infra: Hetzner VPS, systemd service, ngrok tunnel for GitHub webhooks
- Auth: GitHub OAuth 2.0 + optional PAT stored in Keychain

### Key commands

```bash
./deploy.sh underlayer        # publish + scp + restart systemd on VPS
cd native && bash install.sh  # build Xcode Release + install to ~/Applications
cd backend && dotnet run      # local dev on port 5000
cd tests-backend && dotnet test
ssh underlayer 'sudo journalctl -u blame-the-guilty -f'
```

### Conventions

- No Docker, no nginx. Kestrel direct on port 5000.
- Webhook secret in systemd: Environment=WebhookSecret=...
- EF migrations run automatically on startup in Program.cs.
- All DB queries scoped by authenticated GitHub user (multi-tenant).
- TargetGitHubIds (CSV string on WorkflowRun) controls who gets notified.

