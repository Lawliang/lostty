---
name: lostty-close-check
description: Checks whether the work in this terminal is done. Looks for unfinished work (uncommitted or unmerged changes, running tasks, open to-dos, unanswered questions), then answers with `lostty +close-check done`, so Lostty closes the terminal, or replies with what's left. Use when Lostty asks, by typing "/lostty-close-check" or "Use the lostty-close-check skill." after the owner trashes cards on the canvas, or when the owner asks this terminal whether its work is done or whether it can close. Don't use it to decide on your own whether work is finished. To hand work to a new session the owner can watch, use lostty-open-terminal.
allowed-tools: Bash(lostty +close-check done), Bash(lostty +close-check pending), Bash(git status:*), Bash(git log:*), Bash(git stash list:*), Bash(git branch:*), Bash(git rev-parse:*)
---

# Is the work here done?

Two ways this starts:

- **Lostty asks.** The owner trashed this terminal's card on the canvas, and Lostty typed the skill's name.
- **The owner asks.** They typed something like "is your work done?" or "can you close?".

Either way, a `done` answer closes this terminal and ends this session. When in doubt, it's pending.

## Steps

1. **Look at what was done.** Read this session's work and the branch's history: `git log` of the branch
   since it left the branch it came from (often `main`), and `git status`.
2. **Check for unfinished work.** It's pending if any of these is true:
   - The working folder has uncommitted changes, or commits not pushed or merged anywhere (`git status`,
     `git log @{upstream}..` or against the branch it came from).
   - A background task, shell or subagent you started is still running.
   - Your to-do list has items not done.
   - You asked the owner a question they haven't answered.
   - You said you would do something you haven't done.
3. **If it's done:** say in one line what was finished, then run, as your last step:

       lostty +close-check done

4. **If it's pending:** if Lostty asked, run `lostty +close-check pending`. Then reply with a short summary:
   - **Done:** what this session finished, in a few plain lines.
   - **Left:** each thing still open, one line each, such as "3 files not committed" or "waiting on your
     answer about the menu name".
   - **Next:** the one step that would finish it.

## Don't

- Don't commit, push, stash, merge or clean anything up to make the answer `done`. Only report.
- Don't start new work. If something is unfinished, report it and stop.
- Don't run `+close-check` unless Lostty or the owner asked.
