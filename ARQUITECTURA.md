# Blame the Guilty — Architecture

## Overview

```
macOS App (menu bar)  ←→  Backend (VPS)  ←→  GitHub API + Webhooks
```

The app never talks to GitHub directly — all communication goes through the backend.

## App → Backend

Two communication channels:

### 1. REST API (HTTP)

Request/response for discrete operations:

- `GET /api/pullrequests/active?gitHubId=X` → list of active PRs with CI status
- `POST /api/pullrequests/{n}/draft?repo=...&gitHubId=...&draft=true` → toggle draft
- `POST /api/pullrequests/{n}/update-branch` → trigger GitHub update-branch
- `POST /api/workflows/runs/{id}/rerun` → rerun a workflow
- `POST /api/github/create-pr` → create a PR

All requests are initiated by the app. The backend responds with JSON.

### 2. SignalR (WebSockets)

Persistent connection for real-time push events from backend to app:

| Event | When |
|-------|------|
| `PullRequestsUpdated` | PR list or CI status changed |
| `WorkflowRunCompleted` | A workflow finished (success/failure/cancelled) |
| `WorkflowRunInProgress` | A workflow started |
| `PrApproved` | Your PR got approved |
| `PrCommented` | Someone commented on your PR |

30-second polling fallback as belt-and-suspenders.

## Backend → GitHub

### 1. GitHub REST API (95% of calls)

- `GET /repos/{repo}/pulls/{number}` — PR info
- `GET /repos/{repo}/commits/{sha}/check-runs` — check status
- `PUT /repos/{repo}/pulls/{number}/update-branch` — update branch
- `POST /repos/{repo}/pulls` — create PR
- `GET /repos/{repo}/pulls/{number}/commits` — commits for Copilot summary

### 2. GitHub GraphQL API (draft toggle only)

The REST endpoint `PATCH /repos/{repo}/pulls/{number}` **silently ignores** the `draft` field — it returns HTTP 200 but never changes the draft status. This is a known GitHub issue.

GraphQL mutations are the only reliable way:

```graphql
# Convert to Draft
mutation {
  convertPullRequestToDraft(input: { pullRequestId: "PR_kwDO..." }) {
    pullRequest { id isDraft }
  }
}

# Mark as Ready for Review
mutation {
  markPullRequestReadyForReview(input: { pullRequestId: "PR_kwDO..." }) {
    pullRequest { id isDraft }
  }
}
```

The `pullRequestId` (e.g. `PR_kwDOQZfqss7xmLSC`) is the GraphQL node ID, fetched via REST `GET /repos/{repo}/pulls/{number}` → `node_id`. The backend does a GET to get the node ID, then fires the GraphQL mutation.

### 3. Webhooks (GitHub → Backend)

GitHub sends webhooks to `https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github`:

- `workflow_run` — started or completed
- `pull_request` — opened, synchronize, edited, closed
- `check_suite` — check suite completed

On webhook receipt, the backend: logs it, updates the DB, computes notifications, and pushes SignalR events.

## PR status (ciStatus) calculation

`ciStatus` is what you see on each PR card: WAITING, REVIEW, FAIL, READY, DRAFT.

### Matching runs to PRs

Workflow runs are matched to PRs by `(repo, headSha, workflowName)`. The `headSha` is the commit SHA at the PR's head — only runs from the exact same commit are considered. Runs from previous commits (before force-push or new commits) do NOT affect the status.

### SyncCheckRunsForCommit

On every `GET /api/pullrequests/active`, the backend fetches check-runs from GitHub for each unique head SHA and upserts them into the DB. This covers missed webhooks (ngrok downtime, delivery failures).

### Logic

1. No workflow runs for that headSha → `waiting`
2. Any run `in_progress` → `waiting`
3. Any run `failure` → `failed`
4. All runs `success` → `review` (needs human approval)
5. `review` + `reviewApproved` → `ready`
6. `draft = true` → badge shows **DRAFT** (gray), overrides CI status

## Auth tokens

Every GitHub API call needs a token. Resolution order:

```
User PAT  >  OAuth token  >  Shared PAT
```

1. **UserPatToken** — user-configurable PAT in Settings (scope: `repo`)
2. **AccessToken** — OAuth token from GitHub login (scope: `read:user,repo`)
3. **PatToken** — shared token in `appsettings.json` (optional)

## Database (SQLite)

Stored at `/var/lib/blame-the-guilty/blame_the_guilty.db`.

- **GitHubUsers** — OAuth tokens, PATs, avatar URLs
- **PullRequestEvents** — one row per webhook event (status, draft, headSha, review state, etc.)
- **WorkflowRuns** — run_id, workflow_name, repo, status, headSha, actor, conclusion, etc.
- **NotificationTargets** — who to notify when a workflow finishes

Migrations are raw SQL in `Program.cs` (`ALTER TABLE`).

## Frontend (macOS app)

### Global state

Session state lives in `SignalRService` (`@StateObject` at App level). It survives popover close/reopen.

```swift
@StateObject private var signalR = SignalRService(baseUrl: backendUrl)
```

### Optimistic UI (localDraft)

When clicking "Convert to Draft", the app flips `localDraft` immediately without waiting for the backend. On API success it stays flipped; on error it shows the error message.

### Popovers

`.popover(item: $selectedPR)` anchors the detail popover to the PR card. When `selectedPR` changes to a different object, SwiftUI dismisses and re-presents the popover with fresh data.

### Login Item

Registers via `SMAppService.mainApp.register()` on first launch. No Dock icon (`LSUIElement = YES`).

## Complete data flow (example)

Someone pushes to a PR branch:

1. **GitHub** runs workflows
2. **GitHub** sends `workflow_run` webhook (in_progress) → backend
3. **Backend** creates/updates `WorkflowRun` in DB
4. **Backend** pushes `WorkflowRunInProgress` via SignalR
5. **App** shows the run in "Running workflows"
6. **GitHub** completes the workflow
7. **GitHub** sends `workflow_run` webhook (completed) → backend
8. **Backend** updates DB, computes ciStatus
9. **Backend** pushes `WorkflowRunCompleted` + `PullRequestsUpdated` via SignalR
10. **App** updates PR badges, shows notification on failure

**Webhook missed?** (ngrok down, etc.)
11. **App's** 30s poll calls `GET /api/pullrequests/active`
12. **Backend** calls `SyncCheckRunsForCommit` → catches up from GitHub API
13. **App** receives updated data

## ngrok

The backend runs on port 5000. ngrok creates a public HTTPS tunnel:

```
ngrok http --url=moonlike-silenced-sprung.ngrok-free.dev 5000
```

Without ngrok, GitHub couldn't deliver webhooks. The URL is hardcoded in `native/Models/Models.swift`.

## Deploy

```bash
set -eo pipefail
cd backend
dotnet publish -c Release -r linux-x64 --self-contained -o /tmp/blame-publish
rsync -az --delete /tmp/blame-publish/ underlayer:/opt/blame-the-guilty/
ssh underlayer "sudo systemctl daemon-reload && sudo systemctl restart blame-the-guilty"
```

`set -eo pipefail` is critical — without it a failed `dotnet publish` would go unnoticed.

## Tech stack

| Component | Technology |
|-----------|-----------|
| macOS app | SwiftUI, URLSession, SignalR client |
| Backend | ASP.NET 10, C#, System.Text.Json |
| Database | SQLite (EF Core) |
| Real-time | SignalR (WebSockets) |
| GitHub API | REST (95%) + GraphQL (5%, draft only) |
| Tunnel | ngrok |
| Server | Linux VPS, systemd |

## Predictive Conflict Detection

When someone merges a PR to main, the backend sends a `MainBranchUpdated` SignalR event with the repo, PR number, merged-by user, and merge commit SHA.

The app's `ConflictWatcherService` handles this event and also runs a background poll every 60 seconds as fallback. On each check:

1. `git fetch origin main` (lightweight, no tags)
2. Compare the new `origin/main` SHA against the last known SHA
3. If different: `git diff --name-only <last>..origin/main` to get changed files
4. Get uncommitted files: `git diff --name-only` + `git ls-files --others`
5. Get current branch files vs main: `git diff --name-only origin/main...HEAD`
6. If any file appears in both the "changed in main" set and local sets → notification

```
origin/main ──→ merge PR #895 ──→ new SHA
                    ↓
              diff --name-only
                    ↓
        ┌──── changed files ────┐
        ↓                       ↓
  uncommitted changes    current branch diff
        ↓                       ↓
  ⚠️ Notification       ⚠️ Notification
```

Two notification types:
- **Local changes**: "someone merged changes in `PricingService.cs` — you have uncommitted changes there"
- **Branch changes**: "someone merged changes in `CheckoutHandler.cs` — your branch `feature/LOY-123` also touches it"

Notifications are deduplicated per `(repo, file, type)` for 5 minutes to avoid spam.

The service only runs while the app is alive. It reads the workspace path from Settings (default `~/Desktop/dev`). Repos are matched by the `origin` remote URL.

## FAQ

### Why not call GitHub directly from the app?

Server-side logic is needed: PR/workflow matching, ciStatus computation, token storage, target management. Also, webhooks can't reach a macOS app (no public URL).

### Why SQLite?

Single-server, no setup needed, one file. Ample for the data volume.

### Why ngrok?

The VPS has no static IP or domain. ngrok provides a free public HTTPS URL.
