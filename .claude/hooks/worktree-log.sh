#!/usr/bin/env bash
# PostToolUse hook on Bash. When a command ran a raw `git worktree add` or
# `git worktree remove` (outside grove), append one line to grove's event log,
# $XDG_STATE_HOME/grove/events.jsonl, with "source":"hook" and the session that
# ran it. `grove who` reads the same log.
#
# Never blocks and prints nothing: every failure exits 0 silently. The fast
# path is a bash substring test, so most Bash calls cost no Python at all.
# Command parsing reuses grove-worktree-detect.py (quotes, heredocs, git -C).
input=$(cat)
[[ $input == *worktree* && $input == *git* ]] || exit 0
printf '%s' "$input" | HOOK_DIR="${BASH_SOURCE[0]%/*}" python3 -c '
import importlib.util, json, os, shlex, sys, datetime, glob
spec = importlib.util.spec_from_file_location("det", os.path.join(os.environ["HOOK_DIR"], "grove-worktree-detect.py"))
det = importlib.util.module_from_spec(spec); spec.loader.exec_module(det)
p = json.load(sys.stdin)
cmd = (p.get("tool_input") or {}).get("command") or ""
base_cwd = p.get("cwd") or None
sid = p.get("session_id")
home = os.path.expanduser("~")

def worktree_ops(cmd):
    for seg in det.split_segments(cmd, det.blank_data_regions(cmd)):
        try: toks = det.strip_wrappers(shlex.split(seg))
        except ValueError: continue
        if not toks or toks[0] != "git": continue
        i, cwd = 1, base_cwd
        while i + 1 < len(toks) and toks[i] == "-C":
            cwd = det.resolve_dir(os.path.expanduser(toks[i + 1]), cwd); i += 2
        if toks[i:i + 1] != ["worktree"] or i + 1 >= len(toks): continue
        sub, args = toks[i + 1], toks[i + 2:]
        if sub == "add":
            path = det.worktree_add_path(args)
            branch = next((args[j + 1] for j, a in enumerate(args[:-1]) if a in ("-b", "-B")), None)
        elif sub == "remove":
            path, branch = next((a for a in args if not a.startswith("-")), None), None
        else: continue
        path = det.resolve_dir(os.path.expanduser(path), cwd) if path else None
        if path: yield sub, path, branch, cwd

def owner():
    o = {"session_id": sid}
    for f in glob.glob(os.path.join(home, ".claude/sessions/*.json")):
        try: s = json.load(open(f))
        except Exception: continue
        if s.get("sessionId") == sid:
            o.update(session_name=s.get("name"), claude_pid=s.get("pid"), proc_start=str(s.get("procStart")))
            break
    try: o["agent_name"] = json.load(open(os.path.join(home, f".claude/agent-mail/identity-{sid}.json")))["name"]
    except Exception: pass
    return {k: v for k, v in o.items() if v is not None}

ops = list(worktree_ops(cmd))
if not ops: sys.exit(0)
state = os.environ.get("XDG_STATE_HOME") or os.path.join(home, ".local/state")
log = os.environ.get("GROVE_EVENT_LOG") or os.path.join(state, "grove/events.jsonl")
os.makedirs(os.path.dirname(log), exist_ok=True)
who = owner()
ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
for sub, path, branch, cwd in ops:
    # Log only what actually happened: an add left a directory, a remove did not.
    if os.path.isdir(path) != (sub == "add"): continue
    ev = {"ts": ts, "op": sub, "source": "hook", "path": path, "branch": branch, "cwd": cwd, "ppid": os.getppid(), **who}
    line = (json.dumps({k: v for k, v in ev.items() if v is not None}) + "\n").encode()
    fd = os.open(log, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try: os.write(fd, line)
    finally: os.close(fd)
' >/dev/null 2>&1
exit 0
