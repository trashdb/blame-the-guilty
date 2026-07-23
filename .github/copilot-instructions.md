# Copilot Instructions — Blame the Guilty

<!-- caveman:activate -->
Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Fragments OK. Short synonyms. Technical terms exact. Code unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Not: "Sure! I'd be happy to help you with that."
- Yes: "Bug in auth middleware. Fix:"

Switch level: /caveman lite|full|ultra
Stop: "stop caveman" or "normal mode"

Auto-Clarity: drop caveman for security warnings, irreversible actions, user confused. Resume after.
Boundaries: code/commits/PRs written normal.
<!-- /caveman:activate -->

---

## Project: Blame the Guilty

GitHub PR/workflow monitor. macOS menu-bar app + .NET backend + SQLite + SignalR.

### Stack

| Layer | Tech |
|-------|------|
| Backend | .NET 10, ASP.NET Core, EF Core + SQLite, SignalR |
| Native | Swift/SwiftUI macOS menu-bar app (no Dock, no main window) |
| Infra | Hetzner VPS, systemd service, ngrok tunnel for GitHub webhooks |
| Auth | GitHub OAuth + optional PAT |

### Repo layout

```
backend/           → .NET 10 API
  Controllers/     → Auth, Webhook, GitHubApi, PullRequests, Workflows, Punishments
  Models/          → GitHubUser, WorkflowRun, PullRequestEvent, CheckSuiteEvent, PunishmentEvent
  Services/        → GitHubOAuthService, UtcDateTimeConverter
  Hubs/            → PunishmentHub (SignalR)
  Data/            → AppDbContext (EF)
  Migrations/      → EF migrations
native/            → Swift/SwiftUI macOS app
  App/             → Entry point, app delegate
  Models/          → Swift models
  Services/        → SignalRService, GitService, OAuthService, KeychainService, etc.
  Views/           → ContentView, PRDetailView, WorkflowHistoryView, SettingsView, etc.
  Utils/           → DesignSystem, IDEOpener, TeamDefaults
tests-backend/     → xUnit tests for backend
deploy/            → systemd unit files, setup scripts
```

### Key commands

```bash
# Deploy backend to VPS (SSH alias: underlayer)
./deploy.sh underlayer

# Build + install native macOS app locally
cd native && bash install.sh

# Run backend locally
cd backend && dotnet run

# Run backend tests
cd tests-backend && dotnet test
```

### Important conventions

- Backend: no Docker, no nginx. Pure Kestrel on port 5000.
- Webhook secret in systemd `Environment=WebhookSecret=...` or `appsettings.Production.json`.
- DB prod path: `/var/lib/blame-the-guilty/blame_the_guilty.db`
- SignalR hub: `/hubs/punishment`
- GitHub webhooks via ngrok tunnel → `/api/webhook/github`
- Native app reads `AppConfig` from keychain + UserDefaults for server URL, team members, etc.
- Multi-tenant: each GitHub user is isolated. `TargetGitHubIds` on WorkflowRun for notifications.

### DB tables

| Table | Purpose |
|-------|---------|
| GitHubUsers | OAuth token, PAT, SignalR connectionId |
| WorkflowRuns | CI runs (in_progress / success / failure / cancelled / superseded) |
| PullRequestEvents | PRs with CI status, approvals, comment counts |
| CheckSuiteEvents | Completed check suites |
| PunishmentEvents | Historical "blame" log |

### Signals (SignalR → native app)

- `PunishmentEvent` — workflow failed
- `WorkflowCompleted` — run finished (any status)
- `PullRequestUpdated` — PR state changed
- `CheckSuiteCompleted` — checks done

