# Blame the Guilty

> macOS menu bar app that notifies you when your GitHub Actions workflows fail after a merge — instantly, without checking your phone or email.

## Features

- **Instant notifications** when a workflow fails after you merge a PR
- **Workflow history** — see recent runs, their status, and rerun failed workflows
- **Active PRs** — watch open pull requests with their draft/merge status at a glance
- **Multi-target** — assign one or more teammates to get notified on workflow completion
- **Not just blame**: also alerts on success if you asked for it (useful for long-running deploys)

## Architecture

```
┌──────────┐     webhooks      ┌──────────┐    SignalR     ┌──────────────────┐
│  GitHub   │ ──────────────►  │ Backend  │ ──────────────► │  macOS menu bar  │
│  Actions  │                  │ (.NET)   │                 │  (SwiftUI)       │
│  + PRs    │ ◄──── rerun ──── │ VPS/any  │                 │                  │
└──────────┘    (via API)     └──────────┘                 └──────────────────┘
                                     │                          ▲
                                     │ OAuth login              │
                                     ▼                          │
                               ┌──────────┐                     │
                               │  GitHub   │ ────────────────────┘
                               │ OAuth App │   auth callback
                               └──────────┘
```

## Prerequisites

- **macOS** Sequoia or newer
- **Xcode** or Xcode CLI tools (`xcode-select --install`)
- **A VPS** (or any publicly accessible server) — for the backend
- **ngrok** (or any tunnel) — if running the backend locally
- **A GitHub account** with access to the repos you want to monitor
- **A GitHub OAuth App** registered under your GitHub account or org
- **.NET 10 SDK** — for building the backend
- A domain or ngrok URL for the webhook callback

## Setup Guide

### 1. Register a GitHub OAuth App

1. Go to **GitHub Settings → Developer settings → OAuth Apps → New OAuth App**
2. Fill in:
   - **Application name:** `BlameTheGuilty` (or whatever)
   - **Homepage URL:** `https://github.com/trashdb/blame-the-guilty`
   - **Authorization callback URL:** `https://your-tunnel-url.ngrok-free.dev/api/auth/callback`
     (or your actual domain, e.g. `https://blame.example.com/api/auth/callback`)
3. Click **Register application**
4. Note the **Client ID** and generate a **Client Secret** — you'll need both.

> If your organization uses OAuth App access restrictions, you'll need to request approval for the app (or use a PAT as fallback).

### 2. Set up the backend

```bash
# Clone the repo
git clone git@github.com:trashdb/blame-the-guilty.git
cd blame-the-guilty/backend

# Restore and build
dotnet restore
dotnet build -c Release

# Edit appsettings.json with your OAuth credentials and DB path
# (or create appsettings.Production.json — it's gitignored)
```

**`appsettings.Production.json`** (example):

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=/var/lib/blame-the-guilty/blame_the_guilty.db"
  },
  "GitHubOAuth": {
    "ClientId": "your-client-id",
    "ClientSecret": "your-client-secret",
    "RedirectUri": "https://your-tunnel-url.ngrok-free.dev/api/auth/callback"
  }
}
```

**Deploy to your VPS:**

```bash
# Build a self-contained Linux binary and rsync it
dotnet publish -c Release --self-contained true -r linux-x64 -o ./publish
rsync -az --delete ./publish/ user@your-vps:/opt/blame-the-guilty/
scp appsettings.Production.json user@your-vps:/opt/blame-the-guilty/

# Set up systemd service (see deploy/blame-the-guilty.service)
ssh user@your-vps "sudo systemctl daemon-reload && sudo systemctl enable blame-the-guilty && sudo systemctl start blame-the-guilty"
```

### 3. Expose the backend with ngrok (or your domain)

```bash
ngrok http 5000
```

Update the `RedirectUri` in your OAuth App and `appsettings.Production.json` to match the ngrok URL.

### 4. Set up GitHub webhooks

For each repo you want to monitor, add a webhook:

1. **Repo Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://your-tunnel-url.ngrok-free.dev/api/webhook/github`
3. **Content type:** `application/json`
4. **Events:**
   - ☑ **Workflow runs**
   - ☑ **Pull requests**
   - ☑ **Check suites**
5. **Active:** ✅
6. **Add webhook**

The backend handles all three event types:
- `workflow_run` — tracks runs, notifies on failure/success
- `pull_request` — keeps active PR list in sync (opened, closed, draft changes)
- `check_suite` — additional check tracking (requested, completed)

### 5. (Optional) Set a shared PAT for rerun

If your org restricts OAuth apps, you can configure a Personal Access Token as fallback:

1. Generate a PAT with `workflow` scope from a GitHub account that has access to your repos
2. Add it to `appsettings.Production.json`:
   ```json
   {
     "GitHub": { "PatToken": "ghp_your_token_here" }
   }
   ```
3. Restart the backend

The backend tries the user's OAuth token first, then falls back to this PAT.

### 6. Build and install the macOS app

```bash
cd blame-the-guilty/native

# Build
xcodebuild -project btg.xcodeproj -scheme BlameTheGuilty -configuration Release build

# Kill any running instance
pkill -x BlameTheGuilty 2>/dev/null; sleep 1

# Copy to Applications
rm -rf ~/Applications/BlameTheGuilty.app
cp -R "$(find ~/Library/Developer/Xcode/DerivedData -name BlameTheGuilty.app -path '*/Release/*' | head -1)" ~/Applications/

# Launch
open ~/Applications/BlameTheGuilty.app
```

_Note: `install.sh` exists but may silently fall back to a stale build. Use the manual steps above._

### 7. Login

1. Click the 🔥 icon in the menu bar
2. Click **Sign in with GitHub**
3. Your browser opens — authorize the app
4. Go back to the menu bar: you'll see your avatar and **Connected** in green

## Usage

### Notifications

When a workflow you triggered fails (or succeeds with a target assigned), a notification appears in macOS Notification Center. Click it to open the workflow run in your browser.

### Workflow History

Click the list icon in the toolbar to see recent workflow runs with status colors:
- 🟢 Success
- 🔴 Failure
- 🟠 In progress

For each completed run, click 🔄 to rerun it directly from the app (calls the GitHub rerun API).

### Assigning Targets

For any in-progress workflow, click 👤 to open the target picker. Select one or more teammates — they'll get notified when the workflow completes, even if they didn't trigger it.

_Selection is per individual run attempt, not per GitHub runId (so retries are independent)._

### Active PRs

The Active PRs section shows all open pull requests with their status:
- **DRAFT** / **WAITING** / **READY** / **FAIL** / **MERGED**
- Background color reflects the PR state
- Data refreshes via SignalR push when GitHub webhooks arrive

## Development

### Run backend locally

```bash
cd backend
dotnet run
# Listens on http://localhost:5000
```

Expose with ngrok: `ngrok http 5000`

Update `native/Models/Models.swift` to point `backendUrl` to your local/ngrok URL.

### Update the native URL

```swift
// native/Models/Models.swift
let backendUrl = "http://localhost:5000"  // or your ngrok URL
```

### Test a webhook locally

```bash
curl -X POST http://localhost:5000/api/webhook/github \
  -H "Content-Type: application/json" \
  -d '{
    "action": "completed",
    "workflow_run": {
      "id": 999,
      "conclusion": "failure",
      "pull_requests": [{
        "merged_by": { "id": 12345, "login": "your-username" },
        "user": { "id": 12345, "login": "your-username" }
      }]
    },
    "repository": { "full_name": "your-org/your-repo" },
    "sender": { "id": 12345, "login": "your-username" }
  }'
```

## Project Structure

```
blame-the-guilty/
├── backend/                  # .NET 10 API + SignalR
│   ├── Controllers/
│   │   ├── AuthController.cs         # GitHub OAuth login/callback
│   │   ├── WebhookController.cs      # GitHub webhook receiver
│   │   ├── WorkflowsController.cs    # Workflow runs, targets, rerun
│   │   └── PullRequestsController.cs # Active PRs API
│   ├── Hubs/
│   │   └── PunishmentHub.cs          # SignalR hub
│   ├── Models/                       # DB models (WorkflowRun, PullRequestEvent, etc.)
│   ├── Services/
│   │   └── GitHubOAuthService.cs     # OAuth token exchange + user info
│   ├── Data/
│   │   └── AppDbContext.cs           # EF Core SQLite context
│   ├── appsettings.json              # Default config (dev only)
│   ├── appsettings.Production.json   # Gitignored — production secrets
│   └── BlameTheGuilty.Api.csproj
├── native/                   # macOS SwiftUI menu bar app
│   ├── btg.xcodeproj         # Xcode project (LSUIElement = YES — no Dock icon)
│   ├── Models/Models.swift   # Data models + backend URL
│   ├── Services/
│   │   ├── SignalRService.swift      # WebSocket + SignalR client
│   │   ├── OAuthService.swift        # OAuth login flow
│   │   ├── KeychainService.swift     # Session persistence
│   │   └── NotificationService.swift # macOS notifications
│   ├── Views/
│   │   ├── ContentView.swift         # Main popover
│   │   ├── WorkflowHistoryView.swift  # History rows with target picker
│   │   ├── ActivePRsView.swift       # Active PR cards
│   │   └── LoggedInCardView.swift    # Avatar + connected state
│   ├── install.sh            # Legacy — use manual build instead
│   └── btg/                  # App entry (BTGApp.swift)
├── deploy/                   # VPS deployment config
│   ├── blame-the-guilty.service     # systemd unit
│   └── setup-vps.sh                  # One-time VPS setup
└── deploy.sh                 # Build + rsync + restart (run from local)
```

## How it works (internally)

1. GitHub sends a `workflow_run` webhook to the backend when a workflow starts or completes
2. The backend identifies who merged the PR (using `merged_by` or `sender`)
3. If the workflow failed, a `PunishmentEvent` is saved to SQLite
4. SignalR pushes the notification to the macOS app in real-time
5. The menu bar shows the event, and macOS posts a Notification Center alert
6. Active PRs are kept in sync via `pull_request` webhooks + GitHub API calls
7. The rerun button calls GitHub's `POST /repos/{repo}/actions/runs/{runId}/rerun` using the user's OAuth token (or PAT fallback)

## License

MIT
