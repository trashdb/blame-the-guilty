# CLAUDE.md — Blame the Guilty

<!-- caveman:activate -->
Respond terse like smart caveman. All technical substance stay. Only fluff die.

Rules:
- Drop: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Fragments OK. Short synonyms. Technical terms exact. Code unchanged.
- Pattern: [thing] [action] [reason]. [next step].
- Not: "Sure! I'd be happy to help you with that."
- Yes: "Bug in auth middleware. Fix:"

Switch level: /caveman lite|full|ultra|wenyan
Stop: "stop caveman" or "normal mode"

Auto-Clarity: drop caveman for security warnings, irreversible actions, user confused. Resume after.
Boundaries: code/commits/PRs written normal.
<!-- /caveman:activate -->

---

## Project: Blame the Guilty

GitHub PR/workflow monitor. macOS menu-bar app + .NET backend + SQLite + SignalR.

### Architecture

```
[macOS App (SwiftUI)] ←SignalR+REST→ [ngrok tunnel] → [ASP.NET Kestrel:5000]
                                       (Hetzner VPS)       ↓
                                                    SQLite /var/lib/blame-the-guilty/
```

### Stack

| Layer | Tech |
|-------|------|
| Backend | .NET 10, ASP.NET Core Minimal + Controllers, EF Core + SQLite, SignalR |
| Native | Swift 5 / SwiftUI, macOS menu-bar only (LSUIElement), no AppKit windows |
| Infra | Hetzner VPS (SSH alias: `underlayer`), systemd, ngrok |
| Auth | GitHub OAuth 2.0 + optional PAT stored in Keychain |
| Real-time | SignalR WebSocket hub at `/hubs/punishment` |

### Repo layout

```
backend/
  Program.cs                      ← DI, CORS, SignalR, DB migrations on start
  Controllers/
    AuthController.cs             ← /api/auth (login, callback, me, pat)
    WebhookController.cs          ← /api/webhook/github (HMAC-SHA256 verified)
    GitHubApiController.cs        ← /api/github (branches, create-pr, interpret)
    PullRequestsController.cs     ← /api/pullrequests (active, detail, merge, etc.)
    WorkflowsController.cs        ← /api/workflows (runs, rerun, sync-active, targets)
    PunishmentsController.cs      ← /api/punishments (list, summary)
  Models/                         ← EF entities
  Services/                       ← GitHubOAuthService, UtcDateTimeConverter
  Hubs/PunishmentHub.cs           ← SignalR: RegisterConnection, user groups
  Data/AppDbContext.cs             ← 5 DbSets
  Migrations/                     ← EF migrations

native/
  App/BlameTheGuiltyApp.swift     ← NSStatusItem, no Dock
  Models/Models.swift             ← Swift DTOs
  Services/
    SignalRService.swift          ← WebSocket, reconnect, event parsing
    OAuthService.swift            ← GitHub OAuth flow
    GitService.swift              ← local git ops (branch, push, PR preview)
    KeychainService.swift         ← token storage
    PersistenceService.swift      ← UserDefaults wrapper
    ConflictWatcherService.swift  ← detects git conflicts on local repos
  Views/                          ← All SwiftUI views
  Utils/DesignSystem.swift        ← Colors, spacing, fonts

tests-backend/                    ← xUnit, WebApplicationFactory integration tests
deploy/                           ← systemd units, setup-vps.sh
```

### Key commands

```bash
# Deploy backend → VPS
./deploy.sh underlayer

# Build + install native app
cd native && bash install.sh

# Run locally
cd backend && dotnet run

# Tests
cd tests-backend && dotnet test

# Logs
ssh underlayer 'sudo journalctl -u blame-the-guilty -f'
```

### Conventions

- No Docker, no nginx. Pure Kestrel :5000 behind ngrok.
- Webhook secret: `Environment=WebhookSecret=...` in systemd service or `appsettings.Production.json`.
- EF migrations run automatically on `Program.cs` startup (`db.Database.Migrate()`).
- Native: server URL in `AppConfig.serverBaseUrl` (UserDefaults). Default dev: `http://localhost:5000`.
- `TargetGitHubIds` (CSV string) on `WorkflowRun` → which users get notified.
- Multi-tenant: all queries scoped by `GitHubUser`.

### DB tables

| Table | Notes |
|-------|-------|
| `GitHubUsers` | OAuth token, optional PAT, `ConnectionId` (SignalR) |
| `WorkflowRuns` | status: in_progress/success/failure/cancelled/superseded |
| `PullRequestEvents` | prNumber, title, author, CiStatus, ApprovalCount, CommentCount |
| `CheckSuiteEvents` | per-SHA, tracks conclusion |
| `PunishmentEvents` | who broke CI, when |

### SignalR events (hub → native app)

| Event | Payload |
|-------|---------|
| `PunishmentEvent` | workflow failed blame |
| `WorkflowCompleted` | run status changed |
| `PullRequestUpdated` | PR state changed |
| `CheckSuiteCompleted` | checks done |

