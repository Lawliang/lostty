#!/bin/sh
# Measures one running Lostty: memory by kind, CPU, wakeups, threads, and
# which of its own code starts processes or reads files while idle.
# Read-only: it samples the process and changes nothing.
#
#   macos/perf-snapshot.sh [pid] [seconds]
#
# Without a pid, the installed app's (/Applications/Lostty.app).
set -eu
pid=${1:-$(pgrep -f '^/Applications/Lostty.app/Contents/MacOS/lostty$' | head -n 1)}
seconds=${2:-5}
[ -n "$pid" ] || { echo "no Lostty running" >&2; exit 1; }
out=$(mktemp -d)

echo "pid $pid  $(uptime | sed 's/.*load averages*: /load /')"
echo "terminals $(pgrep -P "$pid" login | wc -l | tr -d ' ')  threads $(($(ps -M "$pid" | wc -l) - 1))"
footprint "$pid" | awk '/Footprint:/ {print "footprint", $5, $6} /IOSurface|Malloc Small|IOAccelerator \(graphics\)|CoreAnimation/ {print "  " $0}'
top -l 2 -pid "$pid" -stats cpu,idlew | tail -n 1 | awk '{print "cpu " $1 "%  idle wakeups " $2 "/s"}'

sample "$pid" "$seconds" 1 -mayDie -file "$out/sample.txt" >/dev/null 2>&1
python3 - "$out/sample.txt" "$seconds" <<'PY'
import collections, re, sys
stack, hits = [], collections.Counter()
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"^([ +!:|]*)(\d+) (.*?)  \(in (.*?)\)", line)
    if not m:
        continue
    depth, count, frame, lib = len(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
    while stack and stack[-1][0] >= depth:
        stack.pop()
    stack.append((depth, frame, lib))
    if frame in ("__posix_spawn", "__open", "stat", "__proc_info"):
        own = [f for _, f, l in stack if l == "lostty"]
        hits[(frame, own[-2] if len(own) > 1 else (own[-1] if own else "?"))] += count
print(f"samples in {sys.argv[2]} s (1 ms each), by Lostty caller:")
print(f"  process starts total {sum(n for (f, _), n in hits.items() if f == '__posix_spawn')}")
for (frame, caller), n in hits.most_common(12):
    print(f"  {n:5d} {frame:14s} {caller[:90]}")
PY
rm -rf "$out"
