# Agent setup: skills, MCP servers and the Orca workflow

What the AI tooling around this repo needs, and how to rebuild it on a new machine (written
2026-10-09 for the move from the laptop to an always-on desktop). Nothing here is needed to
build or run the app itself; for that see `docs/running-instructions.txt`.

## Toolchain (desktop, 2026-10-09)

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.47.7 stable | iOS Simulator via Xcode 27; the lead tests on an iPhone 17e simulator |
| Node | 25.9 (backend needs ≥ 20) | `npx` is also needed by the chrome-devtools MCP |
| Claude Code | current | settings in `~/.claude/settings.json`, model `opus` |
| Orca | 1.4.220 | CLI at `/usr/local/bin/orca`; agent hooks in `~/.orca/agent-hooks/` |
| Antigravity CLI | current | `agy`, installed in `~/.local/bin/agy` |
| graphify | current | `graphify`, installed in `~/.local/bin/graphify` |

## Skills

### Project skills (`.claude/skills/`, pinned by `skills-lock.json`)

`.claude/` is gitignored, so the skill files are not in the repo; `skills-lock.json` records
each skill's source and hash. Restore all 29 from the repo root with
`npx -y skills experimental_install -y`. It installs into `.agents/skills/` (add `.agents/` to
`.git/info/exclude`); Claude Code reads `.claude/skills/`, so link each one across:
`mkdir -p .claude/skills && for d in .agents/skills/*/; do ln -s ../../$d .claude/skills/; done`.

| Source | Skills |
|---|---|
| `flutter/skills` | dart-add-unit-test, dart-build-cli-app, dart-collect-coverage, dart-fix-runtime-errors, dart-generate-test-mocks, dart-migrate-to-checks-package, dart-resolve-package-conflicts, dart-run-static-analysis, dart-setup-ffi-assets, dart-use-doc-examples, dart-use-ffigen, dart-use-path-package, dart-use-pattern-matching, dart-use-primary-constructors, dart-write-documentation, flutter-add-integration-test, flutter-add-widget-preview, flutter-add-widget-test, flutter-apply-architecture-best-practices, flutter-build-responsive-layout, flutter-fix-layout-issues, flutter-implement-json-serialization, flutter-setup-declarative-routing, flutter-setup-localization, flutter-use-http-package |
| `mattpocock/skills` | domain-modeling, grill-with-docs, grilling |
| `vercel-labs/skills` | find-skills |

### User skills (`~/.claude/skills/`)

Most are symlinks into `~/.agents/skills/`, tracked by `~/.agents/.skill-lock.json`.
Install them with `npx skills add <repo> -g` or copy `~/.agents/` across, e.g.
`npx -y skills add stablyai/orca -g -y --skill orca-cli --skill orchestration -a claude-code`.

| Skill | Source | Used for |
|---|---|---|
| graphify | github.com/graphify-labs/graphify | Querying `graphify-out/` (the code graph); also needs the `graphify` CLI |
| orca-cli | github.com/stablyai/orca | Driving Orca worktrees and terminals from Claude |
| orchestration | github.com/stablyai/orca | Orca's multi-agent orchestration |
| find-skills | github.com/vercel-labs/skills | Finding and installing skills |
| ui-ux-pro-max | github.com/nextlevelbuilder/ui-ux-pro-max-skill | Design reference |
| push-notifications | local only (`~/.claude/skills/push-notifications/SKILL.md`) | FCM / APNs setup notes; copy the folder by hand (not yet on the desktop) |

### Plugins (`~/.claude/settings.json` → `enabledPlugins`)

| Plugin | Marketplace | Used for |
|---|---|---|
| `impeccable@impeccable` | `pbakaus/impeccable` (GitHub) | `/impeccable critique` and the other design commands; critiques are stored in `.impeccable/critique/` |
| `frontend-design@claude-plugins-official` | official | Frontend design guidance |
| `rust-analyzer-lsp@claude-plugins-official` | official | Not used by this repo |

The `anthropics/skills` marketplace is also registered. Add marketplaces with
`/plugin marketplace add <repo>`, then `/plugin install <name>@<marketplace>`.

## MCP servers

| Server | Scope | Config | Used for |
|---|---|---|---|
| `dart` | this project (local, `~/.claude.json`) | `dart mcp-server` (stdio) | Analyzer, hot reload, widget inspector, pub |
| `chrome-devtools-mcp` | this project (local) | `npx -y chrome-devtools-mcp` (stdio) | Driving the web build in Chrome |
| Claude in Chrome | browser extension | install the extension and sign in | Browser automation on the user's own Chrome |
| claude.ai Claude Docs, Google Drive | claude.ai account | come with the login | Docs; not used by the workflow |
| `rustrover` | user | `http://127.0.0.1:64522/stream` | Only works while RustRover is open; not used here |

The project servers are local-scope, so they live in `~/.claude.json` and must be re-added:

```bash
cd <repo root>
claude mcp add dart -- dart mcp-server
claude mcp add chrome-devtools-mcp -- npx -y chrome-devtools-mcp
claude mcp list   # both should say Connected
```

`claude mcp list` also shows many `plugin:productivity|design|data|engineering:*` servers
(Slack, Notion, Linear, Figma, Datadog and others) as "Needs authentication". Nothing in this
repo uses them; ignore them, or authenticate only the ones you want.

## The lead/implementer workflow (Orca)

- Claude Code is the lead, in one Orca terminal. Antigravity (`agy`, currently on Gemini 3.8
  Flash (High), picked with `/model`) implements, in a second terminal of the same worktree.
- The lead writes one ticket per change in `.lead/<id>.md`. `.lead/` is excluded through
  `.git/info/exclude`, not `.gitignore`, so it does not travel with the repo; recreate the
  exclude line on the new machine. The tickets themselves are scratch work.
- The lead sends the ticket to Antigravity:
  `orca terminal send --terminal <id> --text "Read .lead/P3-8.md and implement it" --enter`.
  Find terminal ids with `orca terminal list`; they change per machine.
- `scripts/dev/watch-antigravity.sh <terminal id> <ticket file>` runs in the background and
  exits with DONE, LIMIT, STALLED or PROMPT, which wakes the lead. Read-only and test commands
  that agy asks to run are approved in place; anything else is a PROMPT for the lead.
- **agy's own settings do not travel with the repo.** They live in
  `~/.gemini/antigravity-cli/settings.json` (`permissions.allow`, entries like
  `command(flutter test)`). Copy that file from the old machine, or agy asks before every
  command. In agy's terminal, Shift+Tab once per session turns on accept-edits mode.
- Claude Code needs two allow rules to drive agy without prompting the owner:
  `Bash(bash scripts/dev/watch-antigravity.sh:*)` and `Bash(orca terminal:*)` (`/permissions`).
- The lead reviews the diff, fixes, runs `flutter analyze && flutter test`, checks on the
  simulator, and commits one commit per ticket. Merging into main, pushing and deploying need
  the owner's OK.
- Orca injects its own `SessionStart` hook and status line into `~/.claude/settings.json`
  (scripts in `~/.orca/agent-hooks/`). Installing Orca on the new machine recreates them; don't
  copy the laptop's versions.

### Simulator runs

```bash
cd fluterFront
flutter run -d <simulator udid> --dart-define=API_BASE=https://mycarecoins.app \
  --dart-define=PURCHASES_ENABLED=false
```

This runs against production with the owner's own account, so simulator checks are
read-only. Hot restart a background run with
`kill -USR2 $(pgrep -f "flutter_tools.snapshot run")`.

On a fresh machine: accept the Xcode license (`sudo xcodebuild -license accept`, in a real
terminal), then `xcodebuild -downloadPlatform iOS` (about 8 GB). Xcode 27 has no
Simulator.app; the device window is `Xcode.app/Contents/Applications/DeviceHub.app`. The lead
taps and swipes through `idb` (`brew install facebook/fb/idb-companion`,
`pip3 install --user fb-idb`; `idb ui tap --udid <udid> X Y` in points, 390×844 on the
17e) and reads `xcrun simctl io <udid> screenshot`. Keep `fluterFront/build` symlinked out
of iCloud (`docs/deployment-and-delivery.md` §4).

## Carrying Claude's memory across

Claude Code keeps per-project memory in
`~/.claude/projects/<path with / replaced by ->/memory/`. On the laptop that is
`-Users-pablogtorres-Desktop-Projects-mycarecoins`. Copy that folder to the matching name for the
repo's path on the desktop. It holds the workflow, the no-merge/push/deploy-without-OK rule and
the Phase 2/3 progress notes.

## Running 24/7

- macOS: disable sleep (System Settings → Energy, or `caffeinate -dims` inside the Orca session).
- An always-on Claude session should still follow the rules above. Leaving it running does not
  authorise merges, pushes or deploys.
- Secrets (`backend/.env`, `firebase-credentials.json`, `scripts/deploy.env`, the SSH key used
  by `scripts/deploy.sh`) are not in git. Move them by hand, not through this repo.
