# Blame the Guilty

macOS menu bar app that tracks GitHub Actions workflows, notifies you on failures, lets you rerun workflows, assign targets, track open PRs with real‑time status, and manage local/remote git branches with checkout, delete, Jira integration, and direct PR creation from the app.

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

The install script builds the project, copies it to `~/Applications/BlameTheGuilty.app`, and relaunches. If the build fails it falls back to the previous build.

## First‑time setup

### 1. Sign in with GitHub

Click the 🔥 icon → **Sign in with GitHub**. Your browser opens to authorize the app (OAuth, scopes: `read:user,repo`). Once connected, you'll see your avatar and **Connected** in green.

### 2. Configure your Personal Access Token (PAT)

Some features (create PR, rerun workflows, update branch, draft/ready toggle) require a PAT:

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens) → **Generate new token (classic)**
2. Scopes: **`repo`** (full control of private repos)
3. If your org enforces SAML SSO (e.g. `easyjet-dev`), click **Configure SSO** and authorize the token
4. Copy the token (starts with `github_pat_...`)
5. Open the app → ⚙️ **Settings** → **Personal Access Token** → paste and **Save**

### 3. Set your workspace path

The app scans a directory recursively to discover git repos for branch management.

Default: `~/Desktop/dev`. Change it in **Settings** → **Workspace Path** if your repos live elsewhere (e.g. `~/Desktop/ej`).

### 4. Configure Jira (optional)

**Settings** → **Jira Board URL** — used when clicking a Jira ticket link in the branch detail popover.

Default: `https://easyjet.atlassian.net/browse/`

### 5. Select your favorite repo

**Settings** → **Favorite Repo** — pick the repo you work on most often. The **See All PRs** button opens `https://github.com/easyjet-dev/{repo}/pulls`.

## Interface

### Popover layout (top to bottom)

| Section | Height | Description |
|---------|--------|-------------|
| **Active PRs** | 170pt | PR cards with CI status + approval state |
| **Branches** | 180pt | Local/Remote git branches |
| **Running workflows** | auto | Current in‑progress runs with rerun/target buttons |
| **Toolbar** | auto | Settings, Workflow History, Webhook Log, See All PRs, avatar |

### PR status badges

| Badge | Meaning |
|-------|---------|
| **DRAFT** | PR is a draft — not ready for review |
| **WAITING** | Open, waiting for checks/review |
| **REVIEW** | Pending human approval (CI may be green) |
| **READY** | CI passed + approved — good to merge |
| **FAIL** | Checks are failing |
| **MERGED** | PR was merged (briefly shown before disappearing) |

Click a PR card to see a detail popover with mergeable state, CI badge per workflow, behind/ahead counts, latest comment preview, links to GitHub Compare/Checks, Convert to Draft / Mark as Ready, Update Branch, and Merge PR.

### Notifications

- **Failures:** red accent, loud sound, dock bounce
- **Approvals & comments:** blue accent, gentle sound
- **Conflict alerts:** blue accent, gentle sound — when someone merges files you're also touching
- Only for important workflows (CI, account‑api, lambdas, terraform) — CodeQL, Dependency Review, etc. are silently ignored.

### Workflow History

Recent workflow runs with success/failure/in-progress icons, rerun button, target assignment for completion notifications. Completed runs show duration; in‑progress runs show relative time.

### Branch management

#### Local Branches

Shows branches where you have commits. Click a branch for:
- Jira ticket link (auto‑detected from branch name)
- **Checkout** → runs `git checkout` + `git pull --rebase` (if upstream exists), then opens **JetBrains Rider**
- **Delete** → `git branch -D` (protected: `main`/`master` cannot be deleted)
- **Create PR** → editable preview with template + Copilot-generated summary from commit messages

#### Remote Branches

Lists branches from GitHub API. Merged branches can be deleted; unmerged are read‑only.

### Predictive Conflict Detection

The app watches your workspace repos in real time. When someone merges a PR to `main`, you get a notification if:
- You have **uncommitted changes** in the same files that were just merged
- Your **current branch** touches the same files (potential merge conflict)

Notifications arrive via SignalR (instant) with a 60‑second polling fallback. Deduplicated per file for 5 minutes.

### Create PR flow

1. Ticket number auto‑extracted from branch name → prepended as `[LOY-XXX]`
2. PR template loaded from `.github/pull_request_template.md`
3. Backend calls Copilot API to generate a summary from commit messages
4. Edit title and body before confirming
5. PR is created via GitHub API

## For repo admins: webhook setup

Each repo needs a webhook pointing at the backend:

1. **Repo Settings → Webhooks → Add webhook**
2. **Payload URL:** `https://moonlike-silenced-sprung.ngrok-free.dev/api/webhook/github`
3. **Content type:** `application/json`
4. **Events:** ☑ Workflow runs, ☑ Pull requests, ☑ Check suites
5. **Active:** ✅

## Settings

| Setting | Description |
|---------|-------------|
| **Workspace Path** | Directory to scan for git repos (default `~/Desktop/dev`) |
| **Jira Board URL** | Base URL for Jira ticket links |
| **Favorite Repo** | Used by "See All PRs" button |
| **Personal Access Token** | Per‑user PAT for API access |

## Architecture

See [ARQUITECTURA.md](./ARQUITECTURA.md) for the full architecture docs.
