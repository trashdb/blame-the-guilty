# SKILLS.md — Blame the Guilty

Specialized workflows. Load relevant skill when task matches.

---

## Skill: deploy-backend

Deploy backend to VPS.

```bash
./deploy.sh underlayer
```

Steps:
1. `dotnet publish` in `backend/` → Release, self-contained, linux-x64
2. `rsync` to VPS (`underlayer`) at `/opt/blame-the-guilty/`
3. `ssh underlayer 'sudo systemctl restart blame-the-guilty'`

Verify: `ssh underlayer 'sudo journalctl -u blame-the-guilty -f'`

---

## Skill: build-native

Build + install macOS app.

```bash
cd native && bash install.sh
```

Steps:
1. `xcodebuild` Release build
2. Copy `.app` to `~/Applications/`

---

## Skill: run-tests

Run all tests.

```bash
# Backend
cd tests-backend && dotnet test

# Swift (from native/)
xcodebuild test -scheme BlameTheGuiltyTests -project btg.xcodeproj \
  -destination 'platform=macOS'
```

---

## Skill: new-controller

Add new backend controller.

1. Create `backend/Controllers/XxxController.cs`
2. Add route: `[Route("api/xxx")]`
3. Add `DbSet<Xxx>` in `AppDbContext.cs` if new entity
4. Add model in `backend/Models/`
5. Run `dotnet build` to verify
6. Add tests in `tests-backend/`

---

## Skill: new-view

Add new SwiftUI view.

1. Create `native/Views/XxxView.swift`
2. Use `DS.Color`, `DS.Font`, `DS.Spacing` from DesignSystem
3. Use `actionButton()`, `solidButton()`, etc. for consistency
4. Add `.onHover` for cursor pointer on interactive elements
5. Test dark mode only (no light mode support)

---

## Skill: webhook-debug

Debug webhook processing.

1. Check VPS logs: `ssh underlayer 'sudo journalctl -u blame-the-guilty -f'`
2. Check recent webhooks: `curl http://localhost:5000/api/webhook/logs?limit=10`
3. Verify HMAC: check `WebhookSecret` in systemd env
4. Test payload: use `docs.md` curl examples

---

## Skill: migration

Add EF Core migration.

```bash
cd backend
dotnet ef migrations add MigrationName
```

Migrations run automatically on startup. No manual step needed.

---

## Skill: stripe-integration

Add Stripe payment flow.

See Monetization section in PROFESIONALIZACION.md.

Key decisions:
- Stripe Checkout for web (direct distribution)
- License key validation in backend
- 30-day trial, then €0.99/month per seat
- Org billing: admin invites members, pay per seat

---

## Skill: multi-tenant

Work on multi-tenant features.

Convention: all DB queries scoped by `GitHubUser.GitHubId`.
`TargetGitHubIds` (CSV) on `WorkflowRun` controls notification recipients.

---

## Skill: native-git

Work on git-related native features.

`GitService` handles: discover repos, branches, pull, push, PR creation.
`ConflictWatcherService` detects conflicts proactively.
`OAuthService` handles GitHub OAuth flow.
`KeychainService` stores tokens securely.
