# PRE-AUDIT-CHECKS.md — Knock-Out Questions Before Phase 1

<!-- TOC: Why pre-flight | The 12 checks | When the audit isn't worth running | Auto-detection script | Tripwire pre-check -->

> Phase 1 starts with `br doctor`. Before even that, there are 12 yes/no questions that determine whether running the audit is worth the time. If the answer to any "knock-out" question is "no", abort with a clear explanation rather than producing a misleading audit.

---

## The 12 checks (in order)

### Check 1 — Project has a `.beads/` directory

```bash
[ -d "$PROJECT/.beads" ] || abort "Project does not use beads"
```

If the project doesn't use beads, this skill isn't applicable. Suggest `/reality-check-for-project` or `/codebase-audit` instead.

### Check 2 — `br` is installed and on PATH

```bash
command -v br >/dev/null || abort "br CLI not installed; install from beads_rust"
```

### Check 3 — Project's `.beads/` is git-tracked

```bash
git -C "$PROJECT" ls-files --error-unmatch ".beads/issues.jsonl" >/dev/null 2>&1 \
  || warn "issues.jsonl not git-tracked; time-machine and BISECT-verify won't work"
```

Not a knock-out, but limits later phases.

### Check 4 — Project has at least 5 closed beads

```bash
N_CLOSED=$(br --db "$PROJECT/.beads"/*.db list --status=closed --limit 0 --json | jq '.issues | length')
[ "$N_CLOSED" -lt 5 ] && abort "Only $N_CLOSED closed beads; audit overhead exceeds value"
```

For < 5 closed beads, manual review is faster than the audit.

### Check 5 — `br doctor` exits clean

```bash
br --db "$PROJECT/.beads"/*.db doctor --json > /tmp/doctor.json
[ $? -eq 0 ] || abort "br doctor failed; hand off to /fixing-beads-problems"
```

**`workspace_health: "degraded"` is NOT a blocker by default.** `bootstrap-audit.sh`
treats degraded as advisory unless one of these hard-fail signals is also present:

- explicit top-level `ok=false` or `healthy=false`
- any `checks[*].status == "fail"`
- any `reliability_audit.anomalies[*].severity == "error"`

Why this matters: long-running frankensqlite-backed bead stores routinely
accumulate harmless WARN-level conditions that flip the rolled-up label to
"degraded" without indicating any real corruption:

- preserved recovery WAL artifacts in `.br_recovery/` (created and intentionally
  retained by `br`'s integrity-recovery path; not a bug)
- "Page N: never used" SQLite integrity notes (frankensqlite emits these
  routinely for pages reserved for future writes)

If you genuinely want to gate on the rolled-up label, set `BCV_REQUIRE_HEALTHY=1`
before invoking `bootstrap-audit.sh`. To tolerate even fail-status checks (use
only after manually confirming the failures are benign), set
`BCV_ALLOW_DEGRADED_FAIL=1`. The default — fail on hard signals only — is the
right choice for daily auditing.

### Check 6 — No cycles in dependency graph

```bash
CYCLES=$(br --db "$PROJECT/.beads"/*.db dep cycles --json | jq 'length')
[ "$CYCLES" -gt 0 ] && abort "$CYCLES dependency cycle(s) detected; resolve before auditing"
```

### Check 7 — Project's `git` history is reachable

```bash
git -C "$PROJECT" rev-parse HEAD >/dev/null 2>&1 || abort "Project is not a git repo"
SHALLOW=$(git -C "$PROJECT" rev-parse --is-shallow-repository)
[ "$SHALLOW" = "true" ] && warn "Shallow git repo; BISECT-verify may fail"
```

### Check 8 — Required test runner is available (per project type)

```bash
if [ -f "$PROJECT/Cargo.toml" ]; then
  command -v cargo >/dev/null || warn "cargo not installed; Phase 4 for Rust will be MISSING"
fi
if [ -f "$PROJECT/package.json" ]; then
  command -v npm >/dev/null || command -v bun >/dev/null || command -v pnpm >/dev/null || \
    warn "no JS package manager; Phase 4 for TS/JS will be MISSING"
fi
# (similarly for Python, Go, etc.)
```

Not a knock-out, but Phase 4 verdicts will be limited.

### Check 9 — Project's working tree is clean OR audit-mode is "dirty-OK"

```bash
DIRTY=$(git -C "$PROJECT" status --porcelain | wc -l)
[ "$DIRTY" -gt 0 ] && [ "${AUDIT_ALLOW_DIRTY:-0}" = "0" ] \
  && warn "Working tree has $DIRTY uncommitted changes; audit may capture mixed state"
```

### Check 10 — User has confirmed test execution is safe

```bash
[ "${AUDIT_TEST_EXECUTION_OK:-0}" = "1" ] || abort "Set AUDIT_TEST_EXECUTION_OK=1 to confirm test runs are safe"
```

This is a defensive prompt — if Phase 4 will hit real services (Stripe, Supabase, etc.), the user must opt in. For tripwire mode, set this in the env automatically.

### Check 11 — Audit dir doesn't conflict with another audit running

```bash
LOCKFILE="$AUDIT_DIR/.audit_running.lock"
if [ -f "$LOCKFILE" ]; then
  PID=$(cat "$LOCKFILE")
  if kill -0 "$PID" 2>/dev/null; then
    abort "Another audit pass is running (PID $PID)"
  else
    warn "Stale lockfile from PID $PID; removing"
    rm -f "$LOCKFILE"
  fi
fi
echo $$ > "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT
```

### Check 12 — Disk space available

```bash
AVAIL_GB=$(df -BG "$AUDIT_DIR_PARENT" | awk 'NR==2 {gsub("G",""); print $4}')
[ "$AVAIL_GB" -lt 1 ] && abort "Less than 1GB free in $AUDIT_DIR_PARENT; audit may fail mid-pass"
```

For a 1000-bead audit, ~500MB is a reasonable floor.

---

## When the audit isn't worth running

| Symptom | Recommendation |
|---------|----------------|
| < 5 closed beads | Manual review is faster |
| All closed beads were closed in the last week (no historical drift) | Wait until there's drift to detect |
| All closed beads have empty bodies | Audit can't extract specs; fix bead authoring first |
| All closed beads were closed by a single batch-close session | Review that session, don't audit per-bead |
| Project is being deprecated | Audit is for live projects; deprecated ones tolerate drift |
| Audit dir already converged 24h ago and project SHA hasn't changed | Re-running adds zero information |
| You're not going to act on the false-closed list | Audit is graph maintenance; if no remediation will happen, skip |

The pre-flight script can detect most of these. The user must decide on "are you going to act on the results?" — that's a human judgment.

---

## Auto-detection script

`scripts/preflight.sh`:

```bash
#!/usr/bin/env bash
# preflight.sh — knock-out checks before running the audit
set -uo pipefail

PROJECT="${1:?project path}"
WARNINGS=()
ABORT_REASONS=()

abort() { ABORT_REASONS+=("$1"); }
warn() { WARNINGS+=("$1"); }

# Check 1
[ -d "$PROJECT/.beads" ] || abort "No .beads/ directory"

# Check 2
command -v br >/dev/null || abort "br CLI not installed"

# Check 4
N_CLOSED=$(br --db "$PROJECT/.beads"/*.db list --status=closed --limit 0 --json 2>/dev/null \
  | jq '.issues | length' 2>/dev/null || echo 0)
[ "${N_CLOSED:-0}" -lt 5 ] && abort "Only $N_CLOSED closed beads (need ≥ 5)"

# Check 5
br --db "$PROJECT/.beads"/*.db doctor --json >/dev/null 2>&1 || abort "br doctor failed"

# Check 6
CYCLES=$(br --db "$PROJECT/.beads"/*.db dep cycles --json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
[ "${CYCLES:-0}" -gt 0 ] && abort "$CYCLES dep cycle(s) — resolve first"

# Check 7
git -C "$PROJECT" rev-parse HEAD >/dev/null 2>&1 || abort "Not a git repo"
[ "$(git -C "$PROJECT" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] && warn "Shallow git repo"

# Check 8 — language-specific runners
if [ -f "$PROJECT/Cargo.toml" ]; then
  command -v cargo >/dev/null || warn "cargo not installed (Rust project)"
fi
if [ -f "$PROJECT/package.json" ]; then
  command -v npm >/dev/null 2>&1 || command -v bun >/dev/null 2>&1 || command -v pnpm >/dev/null 2>&1 \
    || warn "no JS package manager"
fi
if [ -f "$PROJECT/pyproject.toml" ] || [ -f "$PROJECT/requirements.txt" ]; then
  command -v python3 >/dev/null || warn "python3 not installed (Python project)"
fi
if [ -f "$PROJECT/go.mod" ]; then
  command -v go >/dev/null || warn "go not installed (Go project)"
fi

# Check 9
DIRTY=$(git -C "$PROJECT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "${DIRTY:-0}" -gt 0 ] && warn "Working tree has $DIRTY uncommitted change(s)"

# Check 12
AUDIT_DIR_PARENT="$(dirname "$(realpath "$PROJECT")")"
AVAIL_KB=$(df -k "$AUDIT_DIR_PARENT" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
[ "${AVAIL_KB:-0}" -lt 524288 ] && warn "Less than 512MB free in $AUDIT_DIR_PARENT"

# Print results
{
  echo "Pre-flight check for: $PROJECT"
  echo
  if [ "${#ABORT_REASONS[@]}" -gt 0 ]; then
    echo "ABORT REASONS:"
    printf '  ✗ %s\n' "${ABORT_REASONS[@]}"
  fi
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    echo "WARNINGS:"
    printf '  ⚠ %s\n' "${WARNINGS[@]}"
  fi
  if [ "${#ABORT_REASONS[@]}" -eq 0 ] && [ "${#WARNINGS[@]}" -eq 0 ]; then
    echo "✓ All pre-flight checks passed"
  fi
}

[ "${#ABORT_REASONS[@]}" -gt 0 ] && exit 2
exit 0
```

Add to scripts/ and chmod +x. Invoke from `bootstrap-audit.sh` first thing.

---

## Tripwire pre-check

In tripwire mode (autonomous), pre-check is silent unless ABORT — then it fails loudly:

```bash
~/.claude/skills/.../scripts/preflight.sh /path/to/project >/dev/null 2>&1
case $? in
  0) ;;  # all good; continue
  2)
    echo "::error::audit pre-flight failed"
    ~/.claude/skills/.../scripts/preflight.sh /path/to/project   # show details
    exit 1
    ;;
esac
```

---

## When to bypass pre-flight

| Bypass | Justification |
|--------|---------------|
| Onboarding mode (first audit ever) | Many checks won't pass yet; the audit IS the calibration |
| Comprehensive mode (intentional deep audit) | User has explicitly opted in |
| Time-machine mode (auditing historical state) | Pre-flight checks may not reflect historical state |

Bypass via `BYPASS_PREFLIGHT=1`.

---

## Anti-patterns

- Bypassing pre-flight to "make the audit run" when checks are failing for real reasons.
- Adding new pre-flight checks without updating the abort/warn classification.
- Pre-flight checks that themselves call the audit (recursion).
- Pre-flight checks slow enough to dominate audit cost.

Pre-flight should complete in < 5 seconds. If it takes longer, simplify.