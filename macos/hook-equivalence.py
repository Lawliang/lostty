#!/usr/bin/env python3
"""Checks that `lostty-hook` does what `lostty` does for Claude Code's hooks.

    macos/hook-equivalence.py [Lostty.app]            (default: macos/build/Debug/Lostty.app)
    macos/hook-equivalence.py --lostty BIN --hook BIN

Runs both programs over recorded hook inputs and compares, byte for byte,
what each wrote to the terminal, stdout and stderr, its exit code, and the
files it left under $HOME. The terminal is a pty this script owns, never a
real one: each run gets it as its controlling terminal (`tty`), or runs
without one under a parent that has it (`parent`), which is how Claude Code
runs a hook. $HOME is a fresh folder for every run. Exits 1 on a difference.
"""
import fcntl
import json
import os
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import termios
import threading
import time
import tty

PANE = "0F8C2A5E-1B2C-4D3E-8F90-A1B2C3D4E5F6"
OTHER_PANE = "11111111-2222-3333-4444-555555555555"
PANES = "Library/Application Support/Lostty/handoff/panes/"
SLEEPING = "Library/Application Support/Lostty/handoff/sleeping.json"
NOT_MINE = 64
TIMEOUT = 120


def event(name, **fields):
    base = {
        "session_id": "sid-self",
        "transcript_path": "/Users/me/.claude/projects/p/sid-self.jsonl",
        "cwd": "/Users/me/p",
        "hook_event_name": name,
    }
    base.update(fields)
    return json.dumps(base).encode()


def session(name, tmux, sid, cwd="/Users/me/elsewhere"):
    return json.dumps({"pid": 1, "name": name, "tmux": tmux, "sessionId": sid, "cwd": cwd}).encode()


ZONE = {
    PANES + PANE + ".zone.json": json.dumps({
        "start": "You are in zone Proj.",
        "zone": "Proj › Feat",
        "folder": "/Users/me/p",
        "members": ["sess-self", "sess-alice"],
        "features": {"sess-alice": "Feat"},
        "claim": "Say which feature you work on with lostty +zone claim.",
    }).encode(),
    ".claude/sessions/1.json": session("alice", "sess-alice:@1.%2", "sid-alice"),
    ".claude/sessions/2.json": session("bob", "sess-bob:@3.%4", "sid-bob"),
    ".claude/sessions/3.json": session("me", "sess-self:@5.%6", "sid-self"),
    ".claude/sessions/junk.json": b"not json",
    SLEEPING: json.dumps([{
        "pane": OTHER_PANE, "sessionId": "sid-carol", "name": "carol",
        "tmux": "sess-alice", "folder": "/Users/me/p",
    }]).encode(),
}
SAY = {PANES + PANE + ".say": b"Queued for Claude."}
ZONE_SAY = {PANES + PANE + ".zone.say": b"You moved to zone Proj."}
HANDOFF = {PANES + PANE + ".start": b"Carry on from the handoff."}
SUBAGENT = {"agent_id": "a1b2c3", "agent_type": "Explore"}
USAGE = json.dumps({
    "model": {"id": "claude-opus", "display_name": "Opus"},
    "context_window": {
        "context_window_size": 200000,
        "current_usage": {"input_tokens": 1000, "cache_creation_input_tokens": 3000, "cache_read_input_tokens": 80000},
    },
    "rate_limits": {
        "five_hour": {"used_percentage": 42, "resets_at": 1760000000},
        "seven_day": {"used_percentage": 17.5, "resets_at": 1760400000},
    },
}).encode()


def send(to, message="Please rebase."):
    return event("PreToolUse", tool_name="SendMessage", tool_input={"to": to, "message": message})


def case(name, args, stdin=None, files=None, says=True, speaks=False, **env):
    """`says`: writes to the terminal. `speaks`: prints for Claude on stdout."""
    return {"name": name, "args": args, "stdin": stdin, "files": files or {}, "env": env,
            "says": says, "speaks": speaks}


def state(name, arg, stdin=None, **kw):
    return case(name, ["+claude-state", arg], stdin, **kw)


CASES = [
    state("busy, no input", "busy"),
    state("busy, a typed prompt", "busy", event("UserPromptSubmit", prompt="fix the bug")),
    state("busy, finished tasks named", "busy", event(
        "UserPromptSubmit",
        prompt="<task-notification>\n<task-id>abc123</task-id>\n<task-id>bad id</task-id>\n<task-id>def456</task-id>")),
    state("busy, queued text and a zone note", "busy", event("UserPromptSubmit", prompt="go"),
          files={**ZONE, **SAY, **ZONE_SAY}, speaks=True, TMUX_PANE="%6"),
    state("busy, the claim told once", "busy", event("UserPromptSubmit", prompt="go"), files=ZONE, speaks=True),
    state("busy, the claim already told", "busy", event("UserPromptSubmit", prompt="go"),
          files={**ZONE, PANES + PANE + ".zone.told": b"sid-self"}),
    state("busy, input that is not JSON", "busy", b"{not json", files=SAY, speaks=True),
    state("busy, empty input", "busy", b""),
    state("busy, input is a terminal", "busy", "tty", files=SAY, speaks=True),
    state("idle, no input", "idle"),
    state("idle, a stop", "idle", event("Stop")),
    state("idle, a stop with a subagent working", "idle", event(
        "Stop", background_tasks=[{"id": "a1b2c3", "type": "subagent"}, {"id": "m1", "type": "monitor"}])),
    state("idle, a stop with only a monitor", "idle", event("Stop", background_tasks=[{"id": "m1", "type": "monitor"}])),
    state("idle, a stop with a transcript too long", "idle", event("Stop", transcript_path="/" + "x" * 1100)),
    state("idle, asking permission", "idle", event("Notification", notification_type="permission_prompt")),
    state("idle, an idle prompt says nothing", "idle", event("Notification", notification_type="idle_prompt"), says=False),
    state("idle, from a subagent", "idle", event("Stop", **SUBAGENT)),
    state("exit", "exit", event("SessionEnd", reason="exit")),
    state("agents", "agents"),
    state("resumed, the last subagent stops", "resumed", event(
        "SubagentStop", agent_transcript_path="/Users/me/.claude/projects/p/sid-self/subagents/agent-a1b2c3.jsonl",
        background_tasks=[{"id": "a1b2c3", "type": "subagent"}], **SUBAGENT)),
    state("resumed, another subagent still works", "resumed", event(
        "SubagentStop", agent_transcript_path="/Users/me/.claude/projects/p/sid-self/subagents/agent-a1b2c3.jsonl",
        background_tasks=[{"id": "a1b2c3", "type": "subagent"}, {"id": "zz99", "type": "subagent"}], **SUBAGENT)),
    state("resumed, no input", "resumed"),
    state("subagent starts", "subagent", event("SubagentStart", **SUBAGENT)),
    state("subagent, Claude's own internal agent", "subagent",
          event("SubagentStart", agent_id="x1", agent_type=""), says=False),
    state("subagent, no input", "subagent", says=False),
    state("tool, a shell command with a description", "tool", event(
        "PreToolUse", tool_name="Bash", tool_input={"command": "TOKEN=secret make", "description": "Build the app"})),
    state("tool, an edit", "tool", event(
        "PreToolUse", tool_name="Edit", tool_input={"file_path": "/Users/me/p/Sources/Foo.swift"})),
    state("tool, from a subagent", "tool", event(
        "PreToolUse", tool_name="Grep", tool_input={"pattern": "bar"}, **SUBAGENT)),
    state("tool, a large write", "tool", event(
        "PreToolUse", tool_name="Write", tool_input={"file_path": "/Users/me/p/big.txt", "content": "é\n" * 150000})),
    state("tool, a to-do list with nothing in progress", "tool", event(
        "PreToolUse", tool_name="TodoWrite", tool_input={"todos": [{"content": "a", "status": "pending"}]}), says=False),
    state("tool, no input", "tool", says=False),
    state("tool, a message inside the zone", "tool", send("alice"), files=ZONE),
    state("tool, a message outside the zone is denied", "tool", send("bob [3fa9c1]"), files=ZONE, speaks=True),
    state("tool, a message outside the zone allowed once", "tool", send("bob"),
          files={**ZONE, PANES + PANE + ".zone.allow": b"bob\n"}),
    state("tool, a message to a sleeping agent", "tool", send("carol"), files=ZONE, speaks=True),
    state("tool, a long message to a sleeping agent", "tool", send("carol", "word " * 2000), files=ZONE, speaks=True),
    state("tool, a message with no zone", "tool", send("bob")),
    state("done, a plain tool call", "done", event("PostToolUse", tool_name="Read", tool_input={}), says=False),
    state("done, a background shell started", "done", event(
        "PostToolUse", tool_name="Bash", tool_input={"command": "npm run dev", "description": "Start the\tdev server"},
        tool_response={"backgroundTaskId": "bg42"},
        scratchpad_dir="/private/tmp/claude-501/p/sid-self/scratchpad")),
    state("done, queued text", "done", event("PostToolUse", tool_name="Read", tool_input={}),
          files=SAY, says=False, speaks=True),
    state("done, from a subagent leaves the queue", "done", event(
        "PostToolUse", tool_name="Read", tool_input={}, **SUBAGENT), files=SAY, says=False),
    state("done, after ListAgents in a zone", "done", event("PostToolUse", tool_name="ListAgents", tool_input={}),
          files=ZONE, says=False, speaks=True),
    state("start, a new session gets the brief", "start", event("SessionStart", source="startup"),
          files={**ZONE, **ZONE_SAY}, speaks=True),
    state("start, after /clear with a handoff", "start", event("SessionStart", source="clear"),
          files={**ZONE, **HANDOFF}, speaks=True),
    state("start, after /clear with none", "start", event("SessionStart", source="clear")),
    state("start, a resume", "start", event("SessionStart", source="resume"), files={**ZONE, **HANDOFF}),
    state("start, no input", "start", says=False),
    state("an unknown state", "nope", event("Stop"), says=False),
    case("no state", ["+claude-state"], event("Stop"), says=False),
    state("outside Lostty", "idle", event("Stop"), says=False, LOSTTY_SURFACE=None),
    state("outside Lostty, queued text stays", "busy", event("UserPromptSubmit", prompt="go"),
          files=SAY, says=False, LOSTTY_SURFACE=None),
    state("a pane id Lostty never sets", "busy", event("UserPromptSubmit", prompt="go"),
          files=SAY, LOSTTY_SURFACE=PANE.lower()),
    state("in tmux, a stop", "idle", event("Stop"), TMUX="/private/tmp/tmux-501/lostty,1,0", TMUX_PANE="%6"),
    state("in tmux, a subagent stops", "resumed", event(
        "SubagentStop", agent_transcript_path="/Users/me/t.jsonl", **SUBAGENT), TMUX="/private/tmp/tmux-501/lostty,1,0"),
    state("in tmux, a denied message", "tool", send("bob"), files=ZONE, speaks=True,
          TMUX="/private/tmp/tmux-501/lostty,1,0", TMUX_PANE="%6"),
    state("sessions under CLAUDE_CONFIG_DIR", "tool", send("bob"), files=ZONE, CLAUDE_CONFIG_DIR="/nonexistent"),
    state("stdout closed, queued text", "busy", event("UserPromptSubmit", prompt="go"),
          files=SAY, stdout="closed"),
    case("usage", ["+claude-usage"], USAGE),
    case("usage, in tmux", ["+claude-usage"], USAGE, TMUX="/private/tmp/tmux-501/lostty,1,0"),
    case("usage, only a model", ["+claude-usage"], b'{"model":{"display_name":"Haiku"}}'),
    case("usage, input that is not JSON", ["+claude-usage"], b"nope", says=False),
    case("usage, empty input", ["+claude-usage"], b"", says=False),
    case("usage, no input", ["+claude-usage"], says=False),
    case("usage, outside Lostty", ["+claude-usage"], USAGE, says=False, LOSTTY_SURFACE=None),
]

# Command lines `lostty-hook` leaves to `lostty`: the hook command runs
# `lostty` when it exits non-zero.
NOT_MINE_ARGS = [[], ["busy"], ["+guard", "--agent=claude"], ["+version"], ["--version"],
                 ["+claude-state", "idle", "--help"], ["+claude-state", "+claude-usage"], ["-e", "+claude-state", "busy"]]


def stub(argv):
    """The `parent` run's parent: it holds the terminal, the hook has none."""
    code = subprocess.Popen(argv, start_new_session=True).wait()
    os._exit(code if code >= 0 else 128 - code)


def run(binary, c, via, root):
    home = os.path.join(root, "home")
    cwd = os.path.join(root, "cwd")
    for d in (home, cwd):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    for rel, data in c["files"].items():
        path = os.path.join(home, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    env = {"PATH": "/usr/bin:/bin", "HOME": home, "LOSTTY_SURFACE": PANE}
    stdout = subprocess.PIPE
    for key, value in c["env"].items():
        if key == "stdout":
            stdout = value
        elif value is None:
            env.pop(key, None)
        else:
            env[key] = value

    master, slave = pty.openpty()
    tty.setraw(slave)

    def hold_terminal():
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

    closed = None
    if stdout == "closed":
        read_end, closed = os.pipe()
        os.close(read_end)
        stdout = closed
    stdin = c["stdin"]
    argv = [binary] + c["args"]
    if via == "parent":
        argv = [sys.executable, os.path.abspath(__file__), "--stub"] + argv
    p = subprocess.Popen(
        argv, cwd=cwd, env=env, preexec_fn=hold_terminal,
        stdin=slave if stdin == "tty" else subprocess.DEVNULL if stdin is None else subprocess.PIPE,
        stdout=stdout, stderr=subprocess.PIPE)
    # The terminal is read while the hook runs: a process leaving its
    # session waits for what it wrote to be read. `slave` stays open here
    # until the last read: macOS drops what a pty holds when its last
    # writer closes.
    said = []

    def read_terminal(wait):
        while select.select([master], [], [], wait)[0]:
            try:
                data = os.read(master, 1 << 16)
            except OSError:
                data = b""
            if not data:
                # The session's leader left and took the terminal with it.
                time.sleep(wait)
                return
            said.append(data)

    done = threading.Event()
    reader = threading.Thread(target=lambda: [read_terminal(0.05) for _ in iter(done.is_set, True)])
    reader.start()
    try:
        out, err = p.communicate(stdin if isinstance(stdin, bytes) else None, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        err = (err or b"") + b"<timed out>"
    done.set()
    reader.join()
    read_terminal(0.2)
    said = b"".join(said)
    if closed is not None:
        os.close(closed)
    os.close(slave)
    os.close(master)

    left = {}
    for folder, _, names in os.walk(home):
        for name in names:
            path = os.path.join(folder, name)
            with open(path, "rb") as f:
                left[os.path.relpath(path, home)] = f.read()
    code = p.returncode if p.returncode >= 0 else 128 - p.returncode
    return {"exit": code, "terminal": said, "stdout": out or b"", "stderr": err, "files": left}


def show(value):
    text = repr(value)
    return text if len(text) <= 300 else text[:300] + "… (%d bytes)" % len(value)


def main():
    args = sys.argv[1:]
    if args[:1] == ["--stub"]:
        stub(args[1:])
    if args[:1] == ["--lostty"] and args[2:3] == ["--hook"] and len(args) == 4:
        lostty, hook = args[1], args[3]
    elif len(args) <= 1:
        app = args[0] if args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "build/Debug/Lostty.app")
        lostty, hook = (os.path.join(app, "Contents/MacOS", n) for n in ("lostty", "lostty-hook"))
    else:
        sys.exit(__doc__)
    lostty, hook = os.path.abspath(lostty), os.path.abspath(hook)
    for binary in (lostty, hook):
        if not os.access(binary, os.X_OK):
            sys.exit("No program at %s" % binary)

    root = tempfile.mkdtemp(prefix="lostty-hook-equivalence-")
    failures = 0
    runs = 0
    try:
        for c in CASES:
            for via in ("tty", "parent"):
                if via == "parent" and c["stdin"] == "tty":
                    continue
                want = run(lostty, c, via, root)
                got = run(hook, c, via, root)
                runs += 1
                problems = ["%s: lostty %s, lostty-hook %s" % (k, show(want[k]), show(got[k]))
                            for k in want if want[k] != got[k]]
                # The case must do what its name says, or equal means nothing.
                if bool(want["terminal"]) != c["says"]:
                    problems.append("lostty %s the terminal: %s" % (
                        "left alone" if c["says"] else "wrote to", show(want["terminal"])))
                if bool(want["stdout"]) != c["speaks"] and c["env"].get("stdout") != "closed":
                    problems.append("lostty printed %s" % show(want["stdout"]))
                if want["exit"] != 0 or want["stderr"]:
                    problems.append("lostty exit %d, stderr %s" % (want["exit"], show(want["stderr"])))
                print("%s  %-52s %-6s exit %d, terminal %d bytes, stdout %d bytes, %d files left" % (
                    "FAIL" if problems else "ok  ", c["name"], via, got["exit"], len(got["terminal"]),
                    len(got["stdout"]), len(got["files"])))
                for problem in problems:
                    print("        " + problem)
                failures += bool(problems)

        quiet = case("", [])
        for extra in NOT_MINE_ARGS:
            quiet["args"] = extra
            got = run(hook, quiet, "tty", root)
            runs += 1
            ok = got == {"exit": NOT_MINE, "terminal": b"", "stdout": b"", "stderr": b"", "files": {}}
            print("%s  lostty-hook %-40s exit %d, nothing written" % ("ok  " if ok else "FAIL", " ".join(extra), got["exit"]))
            if not ok:
                print("        " + show(got))
            failures += not ok
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print("%d comparisons, %d failed. lostty: %s  lostty-hook: %s" % (runs, failures, lostty, hook))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
