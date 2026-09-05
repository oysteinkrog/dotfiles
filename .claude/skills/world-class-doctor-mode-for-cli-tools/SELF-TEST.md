# SELF-TEST

Smoke-test the skill against a tiny throwaway CLI in a temp dir. Run this when you want to confirm the skill is structurally sound before applying it to a real project.

---

## Trigger phrases that should activate this skill

- "Add a `doctor` subcommand to this CLI"
- "Upgrade `<tool>`'s doctor command — make it world-class"
- "Build a doctor mode for this Rust/Go/Python/TS CLI"
- "Make `<tool> doctor --fix` actually fix things automatically and reversibly"
- "Convert this manual repair playbook into a `doctor` subcommand"
- "Absorb `fixing-beads-problems` into `br doctor --fix`"
- "Score this CLI's doctor against the world-class rubric"
- "Re-run the doctor build on `<tool>` and tell me what improved since pass-N"
- "Add `<tool> doctor capabilities --json` and `<tool> doctor robot-docs`"
- "Build a fixture suite for `<tool> doctor` so every fixer has a regression test"
- "Make sure `<tool> doctor --fix` is idempotent and reversible — and prove it"

If any of these appear in a user's message, the skill should be invoked.

---

## Smoke-test against a tiny throwaway CLI

This script stands up a minimal Bash CLI called `tinycli` in `/tmp/`, then runs the skill's scripts against it to confirm the harness is wired correctly. It does NOT exercise the full phase loop — that's a real application of the skill, not a self-test.

### 1. Set up the throwaway CLI

```bash
set -euo pipefail
test_root=$(mktemp -d /tmp/tinycli.XXXXXX)
cd "$test_root"

# Initialize as git so doctor's worktree work has a real .git/ to attach to.
git init -q
git config user.email "test@example.com"
git config user.name "test"

cat > tinycli <<'EOF'
#!/usr/bin/env bash
# tinycli — a stand-in CLI used to smoke-test the world-class-doctor skill.
# It's intentionally simple. The skill will (in a real run) build a doctor
# subcommand for it.

case "${1:-}" in
    --help|-h)
        echo "tinycli — a tiny CLI"
        echo "subcommands: hello, init, status, doctor"
        ;;
    hello)
        echo "hello, world"
        ;;
    init)
        mkdir -p .tinycli
        echo '{"version":1}' > .tinycli/state.json
        echo "initialized"
        ;;
    status)
        if [ -f .tinycli/state.json ]; then
            cat .tinycli/state.json
        else
            echo "not initialized" >&2
            exit 1
        fi
        ;;
    doctor)
        echo "TODO: doctor not implemented yet — that's what the skill is for"
        exit 64
        ;;
    "")
        echo "usage: tinycli [hello|init|status|doctor]" >&2
        exit 64
        ;;
    *)
        echo "tinycli: unknown subcommand '$1'" >&2
        exit 64
        ;;
esac
EOF
chmod +x tinycli
git add tinycli
git commit -q -m "tinycli: initial CLI"
echo "test repo at: $test_root"
```

### 2. Run the skill's discovery scripts

```bash
# Set SKILL to wherever this skill is checked out (override via env var if non-default).
SKILL="${SKILL:-$HOME/.claude/skills/world-class-doctor-mode-for-cli-tools}"

# Inventory referenced helper skills.
ws=$(mktemp -d /tmp/tinycli-ws.XXXXXX)
"$SKILL/scripts/check-skills.sh" "$ws"
test -f "$ws/phase0_skill_inventory.json" || { echo "FAIL: skill inventory not written"; exit 1; }

# Discover the CLI surface.
"$SKILL/scripts/discover-cli.sh" "$test_root" --probe-doctor > "$ws/phase0_cli.json"
jq -e '.binaries | length > 0' "$ws/phase0_cli.json" \
    || { echo "FAIL: discover-cli didn't find any binaries"; exit 1; }

# Scaffold the workspace (worktree mode).
"$SKILL/scripts/scaffold-workspace.sh" "$ws" "$test_root" --worktree --pass=1 \
    || { echo "FAIL: scaffold-workspace exited nonzero"; exit 1; }
test -d "$ws/analysis/failure_modes" || { echo "FAIL: workspace not scaffolded"; exit 1; }
test -d "$ws/worktree" || { echo "FAIL: worktree not created"; exit 1; }

# Validate that compute-fm-id.py works deterministically.
id_a=$("$SKILL/scripts/compute-fm-id.py" --subsystem state_files --symptom "stale lock")
id_b=$("$SKILL/scripts/compute-fm-id.py" --subsystem state_files --symptom "stale lock")
[ "$id_a" = "$id_b" ] || { echo "FAIL: compute-fm-id not deterministic"; exit 1; }
[ "$id_a" = "fm-state-files-stale-lock" ] \
    || { echo "FAIL: compute-fm-id produced unexpected slug: $id_a"; exit 1; }

# Sanity-check the validate-doctor.sh script: no doctor module yet, so it
# should report "no doctor module found" and exit 0 (not the violator path).
"$SKILL/scripts/validate-doctor.sh" "$test_root" || { echo "FAIL: validate-doctor.sh nonzero on a fresh repo"; exit 1; }

# Scorecard render with no scores: should fail cleanly with exit 2.
set +e
scorecard_out=$("$SKILL/scripts/scorecard.py" render "$ws" 2>&1)
rc=$?
set -e
[ "$rc" = "2" ] || { echo "FAIL: scorecard.py exited $rc on missing scores"; exit 1; }
printf '%s\n' "$scorecard_out" | grep -q "not found" \
    || { echo "FAIL: scorecard.py missing expected error text"; exit 1; }

# Test the DAG validator with a known-good and known-bad input.
cat > "$ws/dag_good.json" <<'EOF'
{"nodes":["fm-a","fm-b","fm-c"],"edges":[{"from":"fm-a","to":"fm-b"},{"from":"fm-b","to":"fm-c"}]}
EOF
"$SKILL/scripts/validate-dag.py" "$ws/dag_good.json" \
    || { echo "FAIL: DAG validator rejected a valid DAG"; exit 1; }

cat > "$ws/dag_bad.json" <<'EOF'
{"nodes":["fm-a","fm-b"],"edges":[{"from":"fm-a","to":"fm-b"},{"from":"fm-b","to":"fm-a"}]}
EOF
set +e
"$SKILL/scripts/validate-dag.py" "$ws/dag_bad.json"
rc=$?
set -e
[ "$rc" = "2" ] || { echo "FAIL: DAG validator accepted a cycle (rc=$rc)"; exit 1; }

echo "self-test PASS"
```

### 3. Cleanup (the OS handles it)

The smoke-test creates `/tmp/tinycli.*` and `/tmp/tinycli-ws.*` directories via `mktemp -d`. They live under `/tmp`, which the OS clears on reboot or via `systemd-tmpfiles`. Per AGENTS.md and the dcg policy this skill enforces, **none of the skill's scripts (or this self-test) will issue `rm -rf` themselves** — even for sandboxes they created. If the user genuinely wants early cleanup, they can issue the destructive command manually with full understanding of the consequences; the skill never does so on the user's behalf.

---

## What this self-test does NOT do

- Does NOT run the full phase loop. That's a real application of the skill.
- Does NOT build a real doctor subcommand for `tinycli` — `tinycli`'s doctor is a stub that exits 64.
- Does NOT exercise the four Phase 5 safety tests (no fixers exist on the throwaway CLI).
- Does NOT install jsm or any helper skill.

For an end-to-end run, point the skill at a real CLI repo and follow the intake prompt at `assets/intake-prompt.md`.

---

## Common smoke-test failures

| Symptom | Likely cause |
|---------|--------------|
| `discover-cli.sh: jq: command not found` | install jq (`apt install jq` or equivalent) |
| `scaffold-workspace.sh: git worktree: target already exists` | `$ws/worktree` left over from a prior run; pick a new mktemp |
| `compute-fm-id.py: not deterministic` | likely a bug in the skill — file an issue |
| `validate-doctor.sh: nonzero on fresh repo` | the validator's pattern set is over-aggressive; check if a `tinycli` line matched a forbidden pattern |
| `scorecard.py: missing scores didn't error` | the script's exit-code contract is broken; file an issue |
| `validate-dag.py: cycle accepted` | DAG validator bug; file an issue |

If any test fails, the skill is broken. Don't apply it to a real project until the failure is fixed.
