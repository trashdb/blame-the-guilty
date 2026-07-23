# CODEX.md — Blame the Guilty

Caveman mode ON. Terse responses. Technical substance only.

## Project

macOS menu-bar app + .NET 10 backend. GitHub PR/workflow monitor.

```
[macOS SwiftUI] ←SignalR+REST→ [ngrok] → [Kestrel:5000 Hetzner VPS] → SQLite
```

## Stack

| Layer | Tech |
|-------|------|
| Backend | .NET 10, ASP.NET Core, EF Core + SQLite, SignalR |
| Native | Swift/SwiftUI macOS menu-bar (LSUIElement=1) |
| Infra | Hetzner VPS, systemd, ngrok |
| Auth | GitHub OAuth 2.0 + PAT in Keychain |

## Commands

```bash
./deploy.sh underlayer        # deploy backend
cd native && bash install.sh  # build + install app
cd backend && dotnet run      # local dev
cd tests-backend && dotnet test  # backend tests
```

## Conventions

- Dark mode only. Menu bar: `flame.fill` red, fixed.
- No Docker, no nginx. Kestrel :5000 direct.
- All DB queries scoped by GitHub user (multi-tenant).
- EF migrations auto-run on startup.
- Code/commits written normal (caveman only for conversation).
