---
name: statefalse
description: Use when working on the statefalse repo (backend, native macOS app, tests, deploy, or commits). Enforces repo workflow: build/install native, run tests, deploy on push, and always commit after changes.
---

# StateFalse — Dev Workflow

Project: GitHub PR/workflow monitor. macOS menu-bar SwiftUI app + .NET 10 backend + SQLite + SignalR.

```
[macOS SwiftUI app] <--SignalR+REST--> [ngrok] --> [Kestrel:5000 on Hetzner VPS] --> SQLite
```

## Response style
Always terse caveman. No articles, no filler, no hedging. Technical terms exact. Only fluff dies.

## Hard rules
- Never leave uncommitted work. After code change: commit.
- Native change → ALSO `bash native/install.sh` (build Release + install + relaunch). User checks this.
- Push to origin/main auto-deploys backend (GitHub Actions `deploy-backend.yml`). Backend-only changes → commit + push is enough.
- `gh` CLI NOT installed locally. Verify deploy over SSH: `ssh underlayer 'curl -sf http://localhost:5000/health'`.
- Dark mode only. Cursor pointer on clickable elements. Production URLs only (never localhost:5000).

## Commands
- Build + install native: `bash native/install.sh`
- Backend local dev: `cd backend && dotnet run`
- Backend tests: `cd tests-backend && dotnet test`
- Live logs: `ssh underlayer 'sudo journalctl -u statefalse -f'`
- Deploy manual: `./deploy.sh underlayer`

## Multi-tenant rule
All DB queries scoped by authenticated GitHub user. `TargetGitHubIds` (CSV string on WorkflowRun) controls who gets notified.

## Verification
- Backend change: `cd tests-backend && dotnet test` must pass before push.
- Native change: `bash native/install.sh` must succeed.
- Deploy: health check via SSH after push.
