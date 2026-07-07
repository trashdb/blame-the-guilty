# Blame the Guilty

macOS menu bar app that notifies you when a GitHub Actions workflow fails after your merge — and lets you rerun failed workflows, assign teammates as targets, and track open PRs.

## Requirements

- macOS Sequoia or newer
- Xcode (or CLI tools: `xcode-select --install`)
- A GitHub account with access to the repos you work on

## Install

```bash
git clone git@github.com:trashdb/blame-the-guilty.git
cd blame-the-guilty/native
bash install.sh
```

A 🔥 icon appears in your menu bar. If `install.sh` doesn't work, do it manually:

```bash
xcodebuild -project btg.xcodeproj -scheme BlameTheGuilty -configuration Release build
pkill -x BlameTheGuilty 2>/dev/null; sleep 1
rm -rf ~/Applications/BlameTheGuilty.app
cp -R "$(find ~/Library/Developer/Xcode/DerivedData -name BlameTheGuilty.app -path '*/Release/*' | head -1)" ~/Applications/
open ~/Applications/BlameTheGuilty.app
```

## Login

1. Click the 🔥 icon → **Sign in with GitHub**
2. Your browser opens — authorize the app
3. Done. You'll see your avatar and **Connected** in green.

## Interface

### Main view

| Element | What it does |
|---------|-------------|
| 🔥 Icon | App is running (no Dock icon — only menu bar) |
| Orange badge | Number of workflows currently running |
| Bell icon | Sends a test notification (for debugging) |
| List icon | Opens Workflow History (only visible when logged in) |

### Active PRs (top section)

Shows all open pull requests with a coloured card:

| Badge | Meaning |
|-------|---------|
| **DRAFT** | PR is a draft — not ready for review |
| **WAITING** | Open, waiting for checks/review |
| **READY** | Good to merge |
| **FAIL** | Checks are failing |
| **MERGED** | PR was merged (briefly shown before disappearing) |

Click any PR card to open it in your browser.

### Workflow History

Click the list icon to see recent workflow runs:

| Icon | Meaning |
|------|---------|
| 🟢 | Success |
| 🔴 | Failure |
| 🟠 | In progress |
| 🔄 **button** | Rerun the workflow (uses your GitHub session) |
| 👤 **button** | Assign teammate(s) to get notified on completion |
| ↗️ **button** | Open the run in your browser |

### Assigning targets

1. Click 👤 on any in-progress workflow
2. Select one or more teammates
3. Tap **Done** — they'll get notified when the workflow finishes

Targets are per individual run attempt (each retry is independent).

## For repo admins: webhook setup

Each repo needs a webhook pointing at the backend. If you have admin access:

1. **Repo Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github`
3. **Content type:** `application/json`
4. **Events:**
   - ☑ **Workflow runs**
   - ☑ **Pull requests**
   - ☑ **Check suites**
5. **Active:** ✅
6. **Add webhook**

The webhook events the app uses:
- `workflow_run` — tracks runs and sends notifications
- `pull_request` — keeps the Active PRs list in sync
- `check_suite` — additional check tracking

## Structure (native app only)

```
blame-the-guilty/native/
├── btg.xcodeproj/       # Xcode project
├── install.sh           # Build + install helper
├── Models/
│   └── Models.swift     # Data types + backend URL
├── Services/
│   ├── SignalRService.swift    # Real-time connection to backend
│   ├── OAuthService.swift      # GitHub login
│   ├── KeychainService.swift   # Session storage
│   └── NotificationService.swift
└── Views/
    ├── ContentView.swift           # Main popover
    ├── WorkflowHistoryView.swift   # Workflow rows + target picker
    ├── ActivePRsView.swift         # PR cards
    └── LoggedInCardView.swift      # Avatar + connected state
```

The backend is already running on a VPS. No need to set it up yourself.
