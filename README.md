# Blame the Guilty

macOS menu bar app that tracks GitHub Actions workflows, notifies you on failures, lets you rerun workflows, assign targets, track open PRs with real‑time status, and manage local/remote git branches with checkout, delete, and Jira integration.

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

A 🔥 icon appears in your menu bar.

The install script picks the most recent build from DerivedData (by binary mtime) and copies it to `~/Applications/BlameTheGuilty.app`, then relaunches.

## First‑time setup

### 1. Sign in with GitHub

Click the 🔥 icon → **Sign in with GitHub**. Your browser opens to authorize the app. Once connected, you'll see your avatar and **Connected** in green.

### 2. Configure your Personal Access Token (PAT)

The app uses GitHub's API for branch management and reruns. Each person **must** set up their own PAT:

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens) → **Generate new token (classic)**
2. Scopes: **`repo`** (full control of private repos)
3. If your org enforces SAML SSO (e.g. `easyjet-dev`), click **Configure SSO** and authorize the token
4. Copy the token (starts with `github_pat_...`)
5. Open the app → ⚙️ **Settings** → **Personal Access Token** → paste and **Save**

The token is stored per‑user in the backend and takes priority over OAuth:
`User PAT > OAuth token > Shared PAT`

### 3. Set your workspace path

The app scans a directory recursively (max depth 3) to discover git repos for branch management.

Default: `~/Desktop/dev`. Change it in **Settings** → **Workspace Path** if your repos live elsewhere (e.g. `~/Desktop/ej`).

### 4. Configure Jira (optional)

**Settings** → **Jira Board URL** — used when clicking a Jira ticket link in the branch detail popover.

Default: `https://easyjet.atlassian.net/browse/`

### 5. Select your favorite repo

**Settings** → **Favorite Repo** — pick the repo you work on most often.

The **See All PRs** button in the toolbar opens `https://github.com/easyjet-dev/{repo}/pulls`.

## Interface

### Popover layout (top to bottom)

| Section | Height | Description |
|---------|--------|-------------|
| **Active PRs** | 170pt | PR cards with CI status + approval state |
| **Branches** | 180pt | Local/Remote git branches |
| **Running workflows** | auto | Current in‑progress runs with rerun/target buttons |
| **Toolbar** | auto | Settings, Workflow History, Webhook Log, See All PRs, avatar |

The popover is **not** scrollable as a whole — each section has a fixed height with its own internal scroll.

### PR status badges

| Badge | Meaning |
|-------|---------|
| **DRAFT** | PR is a draft — not ready for review |
| **WAITING** | Open, waiting for checks/review |
| **REVIEW** | Pending human approval (CI may be green) |
| **READY** | CI passed + approved — good to merge |
| **FAIL** | Checks are failing |
| **MERGED** | PR was merged (briefly shown before disappearing) |

Click a PR card to see a detail popover with:
- Mergeable state (`behind`, `clean`, `dirty`, `blocked`)
- CI badge per relevant workflow
- Behind/ahead commit counts
- Latest comment preview (non‑bot)
- Links to GitHub Compare / Checks
- **Merge PR** button (Squash / Rebase / Merge)

PR status is computed server‑side from the **latest** run per workflow (`repo + headBranch + workflowName`). Historical failures from previous commits do NOT mark a PR as FAIL.

### Notifications

- **Failures:** red accent, loud sound, dock bounce
- **Approvals & comments:** blue accent, gentle `Ping.aiff`, no dock bounce
- Notifications only for important workflows (CI, account‑api, lambdas, terraform) — CodeQL, Dependency Review, Label PR, ForgeRock Secrets are silently ignored.

### Workflow History

Click the list icon (📋) to see recent workflow runs:

| Icon | Meaning |
|------|---------|
| 🟢 | Success |
| 🔴 | Failure |
| 🟠 | In progress |
| 🔄 | Rerun the workflow |
| 👤 | Assign teammate(s) for completion notification |
| ↗️ | Open the run in GitHub |

Completed runs show duration; in‑progress runs show relative time.

### Assigning targets

1. Click 👤 on any in‑progress workflow
2. Select one or more teammates
3. Tap **Done** — they get a notification when the workflow finishes

Targets are per individual run attempt (each retry has its own `dbId`).

### Branch management

The **Branches** section has two tabs:

#### Local Branches

Shows local branches where you have ≥1 commit (or you're the tip author). The current branch is always shown with a `*` prefix.

- **Click a branch** → detail popover with:
  - Jira ticket link (auto‑detected from branch name via `[A-Z]+-\d+`)
  - **Checkout** → runs `git checkout` + `git pull --rebase`, then opens **JetBrains Rider** with the repo's solution file (`.slnx`/`.sln`)
  - **Delete** → runs `git branch -D` (protected: `main`/`master` cannot be deleted)
- **Trash icon** → quick delete with in‑popover confirmation overlay (avoids closing the main popover)

#### Remote Branches

GitHub API lists branches where `commit.author.login` matches your GitHub username. Merged branches are green and can be deleted; unmerged are orange and read‑only.

- Uses `GET /api/github/my-branches` (falls back to git‑based filtering if API fails)
- Checks merged status via `git log origin/main..origin/<branch>`
- Delete runs `git push origin --delete <branch>`

#### Workspace scanning

The workspace path (configurable in Settings) is scanned recursively for git repos (max depth 3). This runs once when the tabs section first appears. A background `git fetch origin --prune --no-tags` runs after results are shown so it doesn't block the UI.

### Viewing PRs

Click the **tray.full icon** in the toolbar to open `https://github.com/easyjet-dev/{favoriteRepo}/pulls` in your browser.

## For repo admins: webhook setup

Each repo needs a webhook pointing at the backend:

1. **Repo Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github`
3. **Content type:** `application/json`
4. **Events:**
   - ☑ **Workflow runs**
   - ☑ **Pull requests**
   - ☑ **Check suites**
5. **Active:** ✅
6. **Add webhook**

Events used:
- `workflow_run` — tracks runs and sends notifications
- `pull_request` — keeps the Active PRs list in sync
- `check_suite` — additional check tracking

## Settings panel

Opened via the ⚙️ button. A floating NSPanel window (not a sheet) that's recreated on each open to capture the current `gitHubId` and `backendUrl`.

| Setting | Description |
|---------|-------------|
| **Workspace Path** | Directory to scan for git repos (default `~/Desktop/dev`) |
| **Jira Board URL** | Base URL for Jira ticket links (default `https://easyjet.atlassian.net/browse/`) |
| **Favorite Repo** | Picker of discovered repos — used by "See All PRs" button |
| **Personal Access Token** | Per‑user PAT for API access, stored in backend |

## Architecture

### Native app → Backend → GitHub

```
macOS App (menu bar)
    ↕ SignalR (real‑time)
    ↕ REST API
Backend (VPS)
    ↕ GitHub API
    ↕ Webhooks (from repos)
GitHub
```

### Key design decisions

- PR status is computed **server‑side** from `WorkflowRuns` + approval state, sent via API and real‑time SignalR pushes
- `ciStatus` only considers the **latest run per workflow** — historical failures ignored
- Token resolution: `User PAT > OAuth token > shared PAT`
- Session state lives in `SignalRService` (`@StateObject` at App level) — survives popover recreation
- Polling fallback (30s) as belt‑and‑suspenders for PRs
- Cancelled/superseded workflows get `"cancelled"` status — non‑punishment, no notification
- `startup_failure` treated as cancelled (no punishment)

### Backend

Already running on a VPS (alias `underlayer`). Deploy:
```bash
docker run --rm -v /tmp/blame-build/backend:/src -w /src mcr.microsoft.com/dotnet/sdk:10.0 dotnet publish -c Release -r linux-x64 --self-contained -o /src/publish
sudo rsync -az --delete /tmp/blame-build/backend/publish/ /opt/blame-the-guilty/
sudo systemctl daemon-reload && sudo systemctl restart blame-the-guilty
```

Database: `/var/lib/blame-the-guilty/blame_the_guilty.db`

## Structure

```
blame-the-guilty/
├── backend/               # ASP.NET backend
│   ├── Controllers/       # API endpoints (auth, workflows, PRs, GitHub, webhook)
│   ├── Models/            # DB models
│   ├── Services/          # GitHub API, webhook processing, SignalR hub
│   └── Program.cs         # Startup + DB migrations
├── native/
│   ├── btg.xcodeproj/
│   ├── install.sh         # Build + install + relaunch
│   ├── Models/
│   │   └── Models.swift   # Data types + helpers
│   ├── Services/
│   │   ├── SignalRService.swift      # Real-time connection
│   │   ├── OAuthService.swift        # GitHub login
│   │   ├── KeychainService.swift     # Session storage
│   │   ├── NotificationService.swift # Local notifications
│   │   └── GitService.swift          # Git operations (actor)
│   └── Views/
│       ├── ContentView.swift         # Main popover
│       ├── ActivePRsView.swift       # PR cards + detail popover
│       ├── PRDetailView.swift        # PR detail (merge, CI, etc.)
│       ├── LocalBranchesView.swift   # Branch management
│       ├── BranchDetailView.swift    # Branch popover (checkout, delete, Jira)
│       ├── WorkflowHistoryView.swift # Workflow rows + target picker
│       ├── SettingsView.swift        # Settings panel
│       ├── SettingsPanelManager.swift # NSPanel wrapper
│       ├── NotificationBannerView.swift
│       ├── EmptyNotificationView.swift
│       └── LoggedInCardView.swift    # Avatar + connected state
└── README.md
```
