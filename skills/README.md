# Lostty skills

Skills that let Claude Code and Codex work with Lostty. Lostty installs them with its agent hooks
(Claude Integration…) into `~/.claude/skills/` and `~/.codex/skills/`, and updates or removes them with the hooks.
It only touches folders named `lostty-*`.

| Skill | What it does |
| --- | --- |
| [lostty-close-check](lostty-close-check/SKILL.md) | Lostty asks it when you close terminals from the canvas: the agent checks for unfinished work and answers `lostty +close-check done` or `pending`. Lostty closes the terminals that are done. |
| [lostty-open-terminal](lostty-open-terminal/SKILL.md) | Opens a visible Lostty window in a folder and starts Claude there with a directive, instead of a hidden subagent. |

Each skill is a folder named `lostty-<name>` with a `SKILL.md` and any scripts it runs.
