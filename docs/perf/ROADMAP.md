# Performance roadmap

Goal: run as many terminals and agents at once as this Mac can hold
(M1 Pro, 10 cores, 16 GB) without crashes or heavy load.

Every decision and its evidence is a row in `decisions.tsv`.
`macos/perf-snapshot.sh <pid>` re-takes the measurements below.

## Baseline (2026-11-11, installed build, 14 terminals)

| What | Value | How |
| --- | --- | --- |
| Lostty memory footprint | 835 MB | `footprint` |
| of which terminal frame buffers (IOSurface) | 379 MB | `footprint` |
| Lostty CPU with nothing typed | about 10% | `top`, 2 samples |
| Idle wakeups | about 300 a second | `top` |
| Threads | 80 | `ps -M` |
| One hook run (`lostty +claude-state`) | 55 ms, 12 MB | 10 runs, load 84 to 120 |
| Mac load average | 61 on 10 cores | `uptime` |
| Swap used | 6.9 of 8 GB | `sysctl vm.swapusage` |

The Mac was overloaded by other work during every measurement
(builds, simulators, a Docker VM), so times are noisy. Counts of
processes, buffers and bytes are not.

## Where the cost is

1. **tmux helper processes.** Each tmux change wakes seven listeners, and
   each starts its own `tmux` to read the same list. A write then signals
   again. About 14 processes per wake, about 70% of Lostty's own CPU in
   the sample.
2. **Agent hooks.** Every tool call of every agent starts the whole
   102 MB `lostty` binary twice (before and after the tool), plus `sh`
   and two `ps`.
3. **Memory held by cards nobody sees.** Each terminal keeps three
   full-size frame buffers (about 17 MB) whether it is on screen,
   off screen or asleep.
4. **The bar under each card.** Every bar redraws when any card's
   numbers change, and reads the model list from disk while drawing.
5. **Polls.** A 1 s task-list poll per card with subagents, a 2 s shell
   script while any Claude works, a 5 s power poll while Stay Awake is on.

## Order of work

Tier 1: high impact, low risk.

| # | Unit | Section | State |
| --- | --- | --- | --- |
| 1 | One tmux read and one write for all per-session options; wakes within 0.2 s merge | tmux | see log |
| 2 | Listeners stop re-reading what a wake did not change (pane sampler, notes listing) | tmux | see log |
| 3 | Hooks skip the engine start-up; no `ps` walk; parse stdin once | hooks | see log |
| 4 | Bar: cached model list, each bar reads only its own pane | canvas | see log |
| 5 | Task list reads only new bytes; working-line watch slows down | polls | see log |

Tier 2: memory.

| # | Unit | Section | State |
| --- | --- | --- | --- |
| 6 | A sleeping card stops drawing; a split made in a hidden card starts hidden | canvas | see log |
| 7 | A hidden terminal gives back its spare frame buffers (engine patch) | engine | see log |

Tier 3: heat and power.

| # | Unit | Section | State |
| --- | --- | --- | --- |
| 8 | Lostty sheds its own work when the Mac reports heat | thermal | see log |
| 9 | Stay Awake reacts to events, not a 5 s poll; menu opens without blocking | stay awake | see log |

Skipped on purpose.

| What | Why |
| --- | --- |
| Setting fan speed | Needs a root helper and undocumented SMC keys, and fights macOS's own fan control. Lostty lowers its own heat instead (unit 8). |
| High Power Mode | This model (16-inch M1 Pro) does not have it. |
| Drawing zoomed-out cards at lower resolution | Changes the terminal grid size, which resizes tmux and reflows every agent's screen. |
| Tearing down a sleeping card's terminal | Biggest memory win left, but it risks ending sessions. Needs a prototype with the owner present. |
| Phone app animation and re-list rates | Does not touch the Mac's load. Listed in the log for a later pass. |
| Launching a test copy of the app tonight | Every copy shares the one tmux server with the 14 live terminals. Runtime checks on a live app wait for the owner. |
