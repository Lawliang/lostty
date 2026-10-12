# Branches sidebar app and sidebar auto-hide — design

Status: draft for review (2026-10-12)

Builds on the extensions sidebar on `skins`
(`macos/Sources/Features/Extensions/`): a 64pt icon strip on the right edge of
every terminal window, whose one app (Skins) opens over the terminal. The
Codebase visualizer placeholder was removed when MindControl was shelved
(`4b0f273ad`).

## Goal

From any terminal window, see the branches of the repo you're working in,
which Lostty sessions (and which agents) are on each one, and what each branch
is about — without leaving the window. Separately, let the sidebar get out of
the way when no app is open.

### Success criteria

- Clicking the Branches icon widens the sidebar into a Branches panel for the
  focused pane's repo; "‹ Apps", re-clicking the icon, or Esc (with the panel
  focused) returns to the plain strip.
- Every pane in the repo — in any window, plus tmux sessions only the phone
  shows — appears under the branch its checkout is on, with a live Claude/Codex
  badge where an agent runs.
- Clicking a session brings its pane to the front (or opens a phone-only
  session in a new tab).
- Committing, switching branches or adding a worktree in a pane updates the
  open panel within about a second.
- "Summarize" on a branch shows a 2–4 sentence summary from Claude; reopening
  the panel later shows it again without another call, marked outdated once the
  branch has moved.
- With "Automatically hide sidebar" on, the terminal uses the full window
  width, the strip slides in when the mouse reaches the right edge, and it
  never hides while an app is open.
- Opening the panel or toggling auto-hide never resizes the terminal.

## Facts this design rests on

- Each pane is a `Ghostty.SurfaceView` with `@Published pwd` (from OSC 7).
  `TerminalController.all` and each controller's `surfaceTree` enumerate panes
  across windows; `LosttyStatusItem.focusPane` already brings a pane's window
  front and focuses it.
- Each pane's shell lives in its own session on `tmux -L lostty`. Sessions no
  running Lostty shows (made on the phone) have no `SurfaceView`; tmux reports
  their directory as `#{pane_current_path}`. `SessionsUI.open` opens such a
  session in a new tab.
- `ClaudeRuntime.shared` holds per-pane agent state (working, idle, awaiting)
  for Claude Code and Codex, fed by hooks and title spinners.
- The app never runs `claude` or `git` today. `claude -p` runs headless with
  the user's Claude Code login; it accepts `--model`, `--tools ""` (no tools),
  `--no-session-persistence`, `--strict-mcp-config` and `--setting-sources`.
- Apple's `/usr/bin/git` may predate `%(ahead-behind:)` (git 2.41), so
  ahead/behind uses `rev-list --left-right --count`.
- Two panes can only be on different branches of one repo through worktrees;
  `git worktree list --porcelain` lists each worktree's path, HEAD and branch.
  A rebase in progress records its branch in
  `<gitdir>/rebase-merge/head-name` or `<gitdir>/rebase-apply/head-name`.
- Lostty preferences live in `UserDefaults.ghostty` under `Lostty*` keys. The
  Settings window (`SettingsView.swift`) is still the upstream placeholder.

## Decisions

| # | Decision |
|---|----------|
| 1 | Summaries: git facts always, plus an on-demand AI paragraph per branch. |
| 2 | The panel shows the focused pane's repo and follows focus. |
| 3 | Sessions: every pane in every window, with an agent badge; phone-only tmux sessions included, labeled "phone". |
| 4 | Local branches only. Branches with sessions first, then by last commit; untouched > 30 days collapse under "Older". |
| 5 | Each worktree is its own checkout. |
| 6 | The panel overlays the terminal (no reflow), with a shadow. |
| 7 | The icon strip stays beside the panel; opening another app replaces it. Exit: "‹ Apps", re-click icon, Esc while the panel is focused. Clicking the terminal doesn't close it. Fixed 340pt. |
| 8 | Apps declare a presentation: terminal overlay, or in-sidebar with a width. |
| 9 | Clicking a session focuses its pane; no git actions. |
| 10 | Live refresh while open (watch `.git`, debounced); nothing while closed. |
| 11 | Auto-hide: strip overlays the full-width terminal, revealed at the right edge, hides 0.5s after the mouse leaves, never while an app is open. Default off. No shortcut. |
| 12 | Row: name · ahead/behind base · relative time · session avatars. Expanded: last commit subject, dirty count, upstream status, changed files vs base, sessions, Summarize. |
| 13 | Base: `origin/HEAD`, else `main`, else `master`. The base row says "base". |
| 14 | Rebasing sessions sit under the branch being rebased, tagged "rebasing"; other detached sessions group under "Detached @ <sha>". |
| 15 | Summary input: commit messages + diff vs base, capped ~60 KB (falls back to `--stat`). Cached on disk by tip SHA; outdated when the tip moves. Never automatic. |
| 16 | Icon: git-branch glyph on a deep green gradient, no badge. Name "Branches". |
| 17 | Summaries run `claude -p --model haiku`, 60s timeout; Summarize is disabled when `claude` isn't found. |
| 18 | Agent badges show live state: pulsing (working), steady (idle), amber (waiting on you). |
| 19 | A phone-only session opens in a new tab. |
| 20 | Esc in the terminal always goes to the terminal. |
| 21 | Auto-hide lives in a real Settings window ("Sidebar" section), applies to all windows at once. |
| 22 | Branch `branches` off `skins`. |
| 23 | A small timeout-guarded `Git` runner local to this feature. MindControl is shelved, so there is nothing to reconcile now. |

## Architecture

New code lives in `macos/Sources/Features/Branches/`, with small changes to
`Features/Extensions/` and `Features/Settings/`. Units, each with one job:

```
ExtensionSidebarLayout ── strip (auto-hide) ── ExtensionSidebarView
        │                                            │ select(.branches)
        └── sidebar panel slot ──► BranchesPanel ◄── BranchesModel (per window)
                                                        │      │        │
                                     RepoReader ◄───────┘      │        └──► BranchSummarizer ──► SummaryCache
                                       │ (Git)          SessionLocator           │ (ClaudeCLI)
                                     RepoWatcher         │ panes + tmux
```

### 1. Sidebar presentation (Extensions)

`LosttyExtension` gains:

```swift
enum Presentation: Equatable { case overlay; case sidebar(width: CGFloat) }
var presentation: Presentation   // .branches → .sidebar(width: 340)
```

and a new case `branches` (title "Branches"), ordered first.

`ExtensionSidebarLayout` keeps the terminal at its width. When the active app
is `.sidebar`, it draws the app's panel in an overlay on the terminal's
trailing edge, flush against the strip, with a leading shadow, sliding in from
the right (`.move(edge: .trailing)` + opacity). `.overlay` apps behave as
today. `ExtensionContentView` gains a `.branches` case that is only shown in
the sidebar slot.

`ExtensionSidebarModel.select` is unchanged in meaning: one active app at a
time, re-click closes. It gains `close()` for the panel's back button and Esc.

The panel claims clicks it covers; clicks on the uncovered terminal go to the
terminal and leave the panel open.

### 2. Auto-hide (Extensions + Settings)

`SidebarPreferences` (`@MainActor` `ObservableObject`, shared) publishes
`autoHide: Bool`, backed by `UserDefaults.ghostty` key `LosttySidebarAutoHide`
(default false). Every window's layout observes it, so the toggle applies
immediately.

`SidebarAutoHide` is a pure state machine so it can be tested without views or
timers:

```swift
struct SidebarAutoHide {
    enum State { case hidden, shown, hiding(deadline: Date) }
    mutating func mouseEnteredEdge(now:) / mouseEnteredStrip(now:) /
                  mouseLeftStrip(now:) / tick(now:) / appOpened() / appClosed(now:)
    var isVisible: Bool
}
```

- `autoHide == false`: the layout is today's (strip beside the terminal); the
  machine is not consulted.
- `autoHide == true`: the terminal fills the window width. The strip is an
  overlay on the trailing edge, offset off-screen while hidden. A 4pt-wide
  tracking strip on the right edge (`.onHover`) reveals it; leaving the strip
  starts a 0.5s hide; re-entering cancels it. While any app is open the
  machine stays `shown`. Closing an app with the mouse outside the strip
  starts the 0.5s hide.
- The 4pt hover strip passes clicks through to the terminal.
- The Claude usage bar below is unaffected.

### 3. Git runner (Branches)

`Git.run(_ args: [String], in dir: String, timeout: 5s) -> String?` runs
`/usr/bin/git -C dir …` off the main actor with the same pattern as
`TmuxClient.run` (background read, semaphore wait, SIGKILL on timeout).
Returns nil on a non-zero exit or timeout. `GIT_OPTIONAL_LOCKS=0` is set so
reads never take `index.lock` from under a pane's own git commands.

### 4. RepoReader (Branches)

`RepoReader.read(root:) async -> RepoSnapshot?` assembles one snapshot:

```swift
struct RepoSnapshot: Equatable {
    var root: String                 // main worktree path
    var name: String
    var base: String?                // "main", resolved per decision 13
    var branches: [BranchInfo]
    var worktrees: [Worktree]
}
struct BranchInfo: Equatable {
    var name: String; var tip: String; var lastCommit: Date; var subject: String
    var upstream: Upstream           // .none / .tracking(ahead:behind:) / .gone
    var vsBase: AheadBehind?         // nil for the base itself and "Older" rows until expanded
}
struct Worktree: Equatable {
    var path: String; var head: String
    var branch: String?              // nil when detached
    var rebasing: String?            // branch named in rebase-*/head-name
    var dirtyCount: Int?             // filled lazily for expanded rows
}
```

Commands:
- `for-each-ref refs/heads --format=…` (tab-separated name, sha, committer
  date, subject, upstream, `%(upstream:track)`).
- `worktree list --porcelain`.
- `symbolic-ref refs/remotes/origin/HEAD`, else `rev-parse --verify`
  `main` / `master`.
- `rev-list --left-right --count base...branch` per non-Older branch.

Expanding a row adds `diff --name-only base...branch` (counted: changed files)
and, for checked-out branches, `status --porcelain` (dirty count). The
parsers for `for-each-ref`, `worktree list --porcelain` and `upstream:track`
are pure static functions.

The repo root for a pane: `ProjectResolver.gitRoot(of:)` finds the worktree
directory, then `rev-parse --git-common-dir` maps any worktree to the shared
repo, so all worktrees of a repo show one panel.

### 5. SessionLocator (Branches)

```swift
struct BranchSession: Identifiable, Equatable {
    enum Origin { case pane(UUID), phone(TmuxSession) }
    var origin: Origin; var title: String; var pwd: String
    var agent: AgentBadge?           // .claude / .codex with .working / .idle / .awaiting
}
```

- `collect()` gathers panes from `TerminalController.all` (title, pwd, agent
  state from `ClaudeRuntime`), plus tmux sessions with no live owner
  (`TmuxOwnership.available`) whose `#{pane_current_path}` comes from a
  `list-panes -a` call with an extended format.
- `assign(_ sessions:, to snapshot:) -> Placement` is pure: each session goes
  to the worktree whose path is the longest prefix of its pwd (case-insensitive,
  canonicalized), then to that worktree's branch, its `rebasing` branch with a
  "rebasing" tag, or a "Detached @ sha" group. Sessions outside the repo are
  dropped.

### 6. RepoWatcher (Branches)

An FSEvents stream on the repo's common git dir (refs, `HEAD`, `worktrees/`,
`packed-refs`) and each worktree's gitdir, latency 0.3s. Events trigger a
re-read. Index-only churn (`index`, `*.lock`) is ignored except for the
expanded row's dirty count. The stream exists only while the panel is open
and the repo is unchanged.

### 7. BranchesModel (per window)

Owned by `ExtensionSidebarModel` (lazily, so windows that never open Branches
pay nothing). It:

- tracks the focused pane's pwd → repo root; switches repos when focus moves
  to another repo and shows the "not in a git repo" state when it moves to a
  pane outside any repo;
- loads a snapshot on open, starts the watcher, stops both on close;
- re-runs `SessionLocator` when panes, pwds or agent state change (Combine
  on `SkinManager.panes` and `ClaudeRuntime` publishers, throttled 0.5s) and
  every 5s while open for phone-only sessions;
- holds `expanded: Set<String>` and per-branch summary state;
- builds the sections: Active, Detached, Branches, Older (collapsed).

### 8. BranchSummarizer + SummaryCache (Branches)

- `ClaudeCLI.locate()` resolves `claude` once per app run via
  `$SHELL -lic 'command -v claude'` (5s timeout), cached; nil disables
  Summarize with the tooltip "Install Claude Code to summarize".
- Input: `log --format='%s%n%b' base..branch` plus `diff base...branch`. If
  the total exceeds 60 KB, the diff is replaced by `diff --stat` and the first
  60 KB of the diff. The base branch is summarized against nothing (button
  hidden).
- Run: `claude -p --model haiku --tools "" --no-session-persistence`
  `--strict-mcp-config` with the prompt on stdin, cwd a temp directory, 60s
  timeout. User settings are not loaded so the user's Lostty hooks don't fire
  for this run (exact `--setting-sources` value confirmed in implementation).
  Prompt asks for 2–4 plain sentences on what the branch changes and why.
- `SummaryCache`: JSON at
  `~/Library/Application Support/Lostty/branch-summaries.json`, keyed by repo
  common-dir + branch → `{tip, text, createdAt}`. A cached entry with a
  different tip is shown dimmed with "Outdated — Re-summarize". Writes are
  atomic.
- States per branch: idle, running (spinner, Cancel), done, failed (message +
  Retry). One run per branch at a time.

### 9. BranchesPanel (views)

- Header: "‹ Apps" back button, repo name, base branch, refresh-in-progress
  indicator.
- Rows per decision 12. Session avatars are small circles with the pane's
  initial; agent badges overlay them per decision 18. Expanded rows list
  sessions by title; clicking one focuses the pane (`LosttyStatusItem.focusPane`
  logic, extracted to a shared helper) or opens a phone session via
  `SessionsUI.open`.
- Colors follow `model.chromeColor` like the strip; text uses the LosttyDesign
  tokens.
- Esc: `.onExitCommand` on the panel, so it only fires with the panel focused.
- Empty states: no focused pane; "This pane isn't in a git repo"; git failed
  ("Couldn't read this repo" + Retry).

### 10. Settings window

`SettingsView` becomes a `Form` with a "Sidebar" section holding
"Automatically hide sidebar" (`SidebarPreferences.autoHide`) and a caption
"Shows when you move the pointer to the right edge. Stays open while an app is
open." Below the form, the existing note that other settings live in the
config file stays. The fixed 156pt height goes; the window sizes to content.

## Error handling

- Any git command failing or timing out leaves the previous snapshot visible
  with a small "Couldn't refresh" note; a first-load failure shows the error
  state with Retry.
- A repo path that disappears (deleted worktree) drops that worktree on the
  next read; the watcher restarts on the new set.
- Summarize: claude missing (disabled), non-zero exit / timeout (failed state
  with the first line of stderr), not logged in (stderr shown as is).
- Summary cache unreadable: treated as empty and rewritten on next save.

## Testing

Swift Testing unit tests (no git process, no claude):
- `RepoReader` parsers: `for-each-ref` lines (including subjects with tabs,
  missing upstream, `[gone]`), `worktree list --porcelain` (main, linked,
  detached, prunable, bare), `upstream:track`.
- `SessionLocator.assign`: nested worktree paths, case differences, symlinked
  pwd, rebasing, detached, sessions outside the repo.
- Section building: active-first ordering, 30-day Older cutoff, base row.
- `SummaryCache`: fresh vs outdated by tip, corrupt file.
- `SidebarAutoHide`: reveal at edge, 0.5s hide, re-enter cancels, never hides
  with an app open, app close starts the hide.

One integration test runs `RepoReader` against a temporary repo made with
`git init` (branches, a worktree, a detached worktree).

Manual, in the built app: open/close the panel all three ways; panes in two
windows and a worktree appear on the right branches; commit in a pane and
watch the row update; jump to a pane; auto-hide on/off with and without an
app open. Summarize is clicked once by hand (it costs tokens; no automated
test calls `claude`).

## Out of scope

- Remote-only branches, git actions (checkout, create, delete, worktree add),
  per-repo base override, resizable panel width, a keyboard shortcut for the
  sidebar, badges on the Branches icon, the phone app.

## Risks

- **Overlay click handling.** Views over the terminal must take their own
  clicks; the shelved `mindcontrol` branch needed
  `clickLands(on:atWindowPoint:)` in `SurfaceView_AppKit.swift` for this. If
  the panel loses clicks to the surface, port that helper.
- **Auto-hide edge strip vs scrollbars.** The 4pt strip sits on the
  terminal's right edge where a scrollbar may appear; it must pass clicks and
  scrolls through and only use hover.
- **`claude -p` flags drift.** The flags above match today's `claude --help`;
  if one is rejected, Summarize shows the stderr rather than failing silently.
