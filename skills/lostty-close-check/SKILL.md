---
name: lostty-close-check
description: Lostty runs this when the owner closes terminals from the canvas and asks whether the work in them is done. Checks this session for unfinished work, then answers Lostty with `lostty +close-check done` (close the terminal) or `pending` (keep it open). Use only when Lostty asks.
allowed-tools: Bash(lostty +close-check done), Bash(lostty +close-check pending), Bash(git status:*), Bash(git log:*), Bash(git stash list:*)
---

# Can this terminal close?

The owner selected this terminal on Lostty's canvas and pressed the trash button. Lostty closes it only if you say
the work here is done. Closing ends this session, so when in doubt, keep it open.

## Steps

1. **Check for unfinished work.** It's pending if any of these is true:
   - The working folder has uncommitted changes, or commits not pushed or merged anywhere (`git status`,
     `git log @{upstream}..` or against the branch it came from).
   - A background task, shell or subagent you started is still running.
   - Your to-do list has items not done.
   - You asked the owner a question they haven't answered.
   - You said you would do something you haven't done.
2. **Answer Lostty** with exactly one of:

       lostty +close-check done
       lostty +close-check pending

3. **Say why in one line**, such as "Done: all work is committed and merged." or "Pending: 2 files not
   committed."

## Don't

- Don't commit, push, stash, merge or clean anything up to make the answer `done`. Only report.
- Don't start new work. If something is unfinished, answer `pending` and stop.
- Don't run `+close-check` unless Lostty asked; it's ignored then anyway.
