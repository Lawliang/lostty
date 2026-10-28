---
name: lostty-open-terminal
description: Use when work should go to a new, separate Claude session the owner can see, for example another project, a parallel task, or a handoff to a fresh session. Opens a visible Lostty window in a folder and starts Claude there with the directive as its first message. Use it instead of background subagents or detached tmux sessions for work the owner should be able to watch.
---

# Open a Lostty terminal with a directive

The owner wants every new session in a window on their screen, never a hidden subagent or a tmux session with no
window. This skill opens one and hands it its first message.

## Steps

1. **Pick the folder.** Use the project's folder or worktree. If the work needs its own branch, make the worktree
   first (`git worktree add <repo>/.claude/worktrees/<name> -b <name>`), and never switch the branch of a folder
   another session uses.
2. **Write the directive to a file**, in your scratchpad. Make it self-contained: what to do and why, what's done
   already, where the code is, and what not to touch. The new session has none of your context.
3. **Run the script** in this skill's folder (`~/.claude/skills/lostty-open-terminal/`, or
   `~/.codex/skills/lostty-open-terminal/` under Codex):

       ~/.claude/skills/lostty-open-terminal/open-lostty.sh <folder> <directive file>

   It prints `window: <session id> <name>` once a window shows the session and Claude has started with the
   directive. `--agent none` opens the window and prints the directive instead of starting Claude.
4. **Tell the owner** a window opened, its folder, and what you asked it to do. To check on it later, read it:
   `tmux -L lostty capture-pane -p -t '<session id>'`.

## When it fails

- **Exit 3, more than one Lostty running** (often a Debug build from a Lostty worktree): both copies would open
  windows. Ask the owner, or the session that owns the extra copy, to quit it, then retry.
- **Exit 4, no window appeared:** the script has already killed any hidden session it made. Tell the owner, and
  give them the directive to paste into a terminal they open themselves. Don't fall back to a background agent.
- **"Lostty didn't answer the request":** that's fine; the script opens the folder with Lostty instead. It happens
  when Lostty's new-window requests are stuck; a Lostty restart clears it.

## Don't

- Don't start a detached tmux session or a background subagent for work the owner should see.
- Don't type into a window you didn't open with this script.
