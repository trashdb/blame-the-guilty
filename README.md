# Blame the Guilty

> When a GitHub Actions workflow fails after a merge, the culprit gets an instant notification in their macOS menu bar. No more finding out hours later.

## How it works

```
Workflow fails on GitHub ──► Webhook ──► Backend (VPS) ──► SignalR ──► Your Mac (menu bar 🔥)
                                                              │
                                                    Identifies who
                                                    merged it
```

The backend is already running on a VPS, exposed via ngrok. No need to set it up yourself.

## Requirements

- macOS (Sequoia or newer)
- Xcode CLI tools (`xcode-select --install`) or Xcode
- A GitHub account

## Installation (one-time)

```bash
# Clone the repo
git clone git@github.com:trashdb/blame-the-guilty.git
cd blame-the-guilty/native

# Build and install
swift build -c release
bash install.sh
```

This installs `BlameTheGuilty.app` in `~/Applications/` and launches it automatically. A 🔥 icon will appear in your menu bar.

## Daily usage

1. Click the 🔥 icon in the menu bar
2. Click **"Sign in with GitHub"**
3. Your browser opens — authorize the app
4. Go back to the menu: you'll see **"Connected & watching"** in green

From now on, whenever someone merges a failing workflow, you'll get a notification with the culprit, repo, and run ID. Click the notification to open the workflow in your browser.

## Connect your repos

Each repo you want to monitor needs a webhook pointing at the backend:

1. On GitHub: **Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github`
3. **Content type:** `application/json`
4. **Events:** "Let me select individual events" → check **"Workflow runs"**
5. **Active:** ✅
6. **Add webhook**

## How to test (without breaking anything)

```bash
curl -X POST https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github \
  -H "Content-Type: application/json" \
  -d '{
    "action": "completed",
    "workflow_run": {
      "id": 999,
      "conclusion": "failure",
      "head_commit": { "author": { "username": "the-culprits-username" } },
      "pull_requests": [{
        "merged_by": { "id": 12345, "login": "the-culprits-username" },
        "user": { "id": 12345, "login": "the-culprits-username" }
      }]
    },
    "repository": { "full_name": "your-org/your-repo" },
    "sender": { "id": 12345, "login": "the-culprits-username" }
  }'
```

If the app is open and connected, you'll get the notification.

## Repo structure

```
blame-the-guilty/
├── backend/          # .NET API + SignalR (already deployed on VPS)
│   ├── Controllers/  # WebhookController, AuthController
│   ├── Hubs/         # SignalR hub
│   └── appsettings.*.json
├── native/           # macOS client (SwiftUI, menu bar app)
│   ├── Sources/BlameTheGuilty/
│   │   ├── App.swift        # Menu bar UI
│   │   ├── SignalRService.swift
│   │   ├── OAuthService.swift
│   │   └── CustomNotification.swift
│   └── install.sh
└── deploy/           # Backend deployment scripts
```
