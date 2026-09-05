#!/usr/bin/env bash
# conflict-replay.sh — Resumability: replay a captured Phase 8 conflict
# resolution against fresh state.
#
# When apply-keeper.sh hits a conflict during Phase 8, the user resolves it
# manually via the Edit tool, and the resolution context is preserved at
# <workspace>/conflicts/branch_<slug>.context.md. Embedded in that markdown
# is a fenced JSON block describing the recorded Edit operations:
#
#   ```json
#   {
#     "schema": "conflict-replay/v1",
#     "branch": "<branch>",
#     "slug": "<slug>",
#     "strategy": "cherry-pick",
#     "source_sha": "<sha>",
#     "edits": [
#       {"file": "src/foo.rs", "old": "...", "new": "..."},
#       ...
#     ],
#     "post_commands": [
#       "git add src/foo.rs",
#       "git cherry-pick --continue"
#     ]
#   }
#   ```
#
# This script:
#   1. Reads the context file.
#   2. Verifies the source SHA still resolves (otherwise the upstream branch
#      moved; halt).
#   3. Re-applies the recorded edits one-by-one. Each edit is INDEPENDENT —
#      `old` must match exactly in the current file (the same fail-closed
#      guarantee as the Edit tool); on any mismatch, halt and surface.
#   4. Runs the recorded `post_commands` in sequence.
#   5. Runs the project's quality gates (test/lint/typecheck) before
#      committing.
#   6. Logs success/failure to <workspace>/conflict_replay_log.tsv.
#
# Idempotent: if the recorded source_sha is already represented as a commit
# on the rationalization branch (per apply_log.tsv), the replay is a no-op.
#
# Per AGENTS.md "No Script-Based Changes": this script does NOT regex-mutate
# source files. Each edit is a literal string-replacement bounded by the
# `old` field's exact match — which is identical to how the Edit tool works.
# The list of edits comes from the user's prior session (recorded by the
# main agent), NOT from a heuristic.
#
# Per AGENTS.md "Mandatory explicit plan": replay requires a verbatim
# authorization phrase in <workspace>/conflict_replay_authorization.txt.
#
# Exit codes:
#   0  replay complete
#   2  preflight failed (context file / workspace missing)
#   3  source SHA no longer resolvable (upstream moved)
#   4  edit `old` text not found in current file (drift)
#   5  authorization missing
#   6  post-command failed
#   7  quality gate failed

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

json_context() {
  python3 - "$CONTEXT" "$@" <<'PY'
import base64
import json
import sys

path = sys.argv[1]
mode = sys.argv[2]

capture = False
payload = []
with open(path, encoding="utf-8") as f:
    for line in f:
        if line.strip() == "```json" and not capture:
            capture = True
            continue
        if line.strip() == "```" and capture:
            break
        if capture:
            payload.append(line)

if not payload:
    raise SystemExit("context file has no fenced JSON payload")

data = json.loads("".join(payload))

def b64(value):
    if value is None:
        value = ""
    if not isinstance(value, str):
        value = str(value)
    return base64.b64encode(value.encode("utf-8")).decode("ascii")

if mode == "header":
    print(b64(data.get("branch", "")))
    print(b64(data.get("source_sha", "")))
    print(b64(data.get("strategy", "")))
elif mode == "edit_count":
    print(len(data.get("edits", [])))
elif mode == "edit":
    edit = data["edits"][int(sys.argv[3])]
    print(b64(edit.get("file", "")))
    print(b64(edit.get("old", "")))
    print(b64(edit.get("new", "")))
elif mode == "post_count":
    print(len(data.get("post_commands", [])))
elif mode == "post":
    print(b64(data["post_commands"][int(sys.argv[3])]))
else:
    raise SystemExit(f"unknown json_context mode: {mode}")
PY
}

b64_decode() {
  printf '%s' "$1" | base64 -d 2>/dev/null
}

reject_replay_path() {
  printf 'ERROR: replay path %s is outside the allowed project edit surface\n' "$1" >&2
  return 1
}

validate_replay_rel_path() {
  local rel="$1"
  if [[ -z "$rel" || "$rel" == /* ]]; then
    reject_replay_path "$rel"
    return 1
  fi
  if [[ "$rel" == *$'\n'* || "$rel" == *$'\r'* ]]; then
    reject_replay_path "$rel"
    return 1
  fi
  case "$rel" in
    .|..|../*|*/../*|.git|.git/*|"$WS_REL"|"$WS_REL"/*)
      reject_replay_path "$rel"
      return 1
      ;;
  esac
  python3 - "$PROJECT_ABS" "$rel" <<'PY' >/dev/null
import os
import sys

root = os.path.realpath(sys.argv[1])
target = os.path.realpath(os.path.join(root, sys.argv[2]))
try:
    common = os.path.commonpath([root, target])
except ValueError:
    sys.exit(1)
if common != root:
    sys.exit(1)
PY
}

resolve_existing_replay_file() {
  local rel="$1"
  validate_replay_rel_path "$rel" || return 1
  python3 - "$PROJECT_ABS" "$rel" <<'PY'
import os
import sys

root = os.path.realpath(sys.argv[1])
target = os.path.realpath(os.path.join(root, sys.argv[2]))
if not os.path.isfile(target):
    sys.exit(2)
print(target)
PY
}

split_command_tokens() {
  python3 - "$1" <<'PY'
import base64
import shlex
import sys

if "\n" in sys.argv[1] or "\r" in sys.argv[1]:
    sys.stderr.write("ERROR: refused multi-line recorded post-command\n")
    sys.exit(1)
try:
    parts = shlex.split(sys.argv[1])
except ValueError as exc:
    sys.stderr.write(f"ERROR: could not parse recorded post-command: {exc}\n")
    sys.exit(1)
for part in parts:
    print(base64.b64encode(part.encode("utf-8")).decode("ascii"))
PY
}

run_post_command() {
  local cmd="$1"
  local -a parts=()
  local -a encoded_parts=()
  local -a add_paths=()
  local encoded
  local token_lines
  local token

  if ! token_lines=$(split_command_tokens "$cmd"); then
    return 1
  fi
  if [[ -n "$token_lines" ]]; then
    mapfile -t encoded_parts <<< "$token_lines"
    for encoded in "${encoded_parts[@]}"; do
      parts+=("$(b64_decode "$encoded")")
    done
  fi
  if [[ "${#parts[@]}" -eq 0 ]]; then
    return 0
  fi
  if [[ "${parts[0]}" != "git" ]]; then
    echo "ERROR: refused recorded post-command outside the git allowlist: $cmd" >&2
    return 1
  fi

  case "${parts[1]:-}" in
    add)
      if [[ "${#parts[@]}" -lt 3 ]]; then
        echo "ERROR: refused empty git add post-command" >&2
        return 1
      fi
      for token in "${parts[@]:2}"; do
        [[ "$token" == "--" ]] && continue
        if [[ "$token" == -* ]]; then
          echo "ERROR: refused git add option in recorded post-command: $token" >&2
          return 1
        fi
        validate_replay_rel_path "$token" || return 1
        add_paths+=("$token")
      done
      if [[ "${#add_paths[@]}" -eq 0 ]]; then
        echo "ERROR: refused git add post-command with no paths" >&2
        return 1
      fi
      git -C "$PROJECT_ABS" add -- "${add_paths[@]}"
      ;;
    cherry-pick|merge|rebase)
      if [[ "${#parts[@]}" -ne 3 || "${parts[2]}" != "--continue" ]]; then
        echo "ERROR: refused non-continuation git post-command: $cmd" >&2
        return 1
      fi
      git -C "$PROJECT_ABS" "${parts[1]}" --continue
      ;;
    *)
      echo "ERROR: refused recorded git post-command outside the allowlist: $cmd" >&2
      return 1
      ;;
  esac
}

usage() {
  cat <<USAGE
Usage: conflict-replay.sh <project-path> <slug>

Replays a captured Phase 8 conflict resolution against fresh state. Reads
<workspace>/conflicts/branch_<slug>.context.md, applies the recorded edits
literally, runs post-commands, runs project gates, commits.

Authorization gate:
  <workspace>/conflict_replay_authorization.txt must contain (case-insensitive):
    yes I authorize replay of <slug>

Env:
  WORKSPACE                          Workspace dir override.
  CONFLICT_REPLAY_OVERRIDE_OK=1      Bypass authorization gate (NOT recommended).

Exit codes:
  0  replay complete
  2  preflight failed
  3  source SHA no longer resolvable
  4  edit drift (old text not found)
  5  authorization missing
  6  post-command failed
  7  quality gate failed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
SLUG="${2:-}"
[[ -z "$SLUG" ]] && { usage >&2; exit 64; }

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
CONTEXT="$WORKSPACE_DIR/conflicts/branch_${SLUG}.context.md"
AUTH_FILE="$WORKSPACE_DIR/conflict_replay_authorization.txt"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"
PROFILE="$WORKSPACE_DIR/project_profile.json"
LOG_TSV="$WORKSPACE_DIR/conflict_replay_log.tsv"
WS_REL="$(basename "$WORKSPACE_DIR")"

[[ -f "$CONTEXT" ]] || { echo "ERROR: $CONTEXT missing" >&2; exit 2; }

# Authorization gate.
AUTH_PHRASE="yes I authorize replay of $SLUG"
if [[ -z "${CONFLICT_REPLAY_OVERRIDE_OK:-}" ]]; then
  if [[ ! -s "$AUTH_FILE" ]]; then
    echo "REFUSED: $AUTH_FILE missing." >&2
    echo "Per AGENTS.md, replay requires verbatim authorization. Add this line:" >&2
    echo "  yes I authorize replay of $SLUG" >&2
    exit 5
  fi
  if ! grep -iqF "$AUTH_PHRASE" "$AUTH_FILE"; then
    echo "REFUSED: authorization phrase for slug '$SLUG' not in $AUTH_FILE." >&2
    echo "Expected (case-insensitive): yes I authorize replay of $SLUG" >&2
    exit 5
  fi
fi

# Extract the JSON payload from the markdown context file. The convention is
# a fenced ```json block.
JSON=$(awk '
  /^```json[[:space:]]*$/ {capture=1; next}
  /^```[[:space:]]*$/ && capture {capture=0; exit}
  capture {print}
' "$CONTEXT" 2>/dev/null || true)

if [[ -z "$JSON" ]]; then
  echo "ERROR: no \`\`\`json block in $CONTEXT" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required for JSON parsing" >&2
  exit 2
fi

# Initialize log if missing.
if [[ ! -f "$LOG_TSV" ]]; then
  printf 'timestamp_utc\tslug\tstatus\tnotes\n' > "$LOG_TSV"
fi
record_log() {
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$SLUG" "$1" "$2" >> "$LOG_TSV"
}

# Parse the JSON header (branch, source_sha, strategy).
mapfile -t HEADER_FIELDS < <(json_context header)
BRANCH=$(b64_decode "${HEADER_FIELDS[0]:-}")
SOURCE_SHA=$(b64_decode "${HEADER_FIELDS[1]:-}")
STRATEGY=$(b64_decode "${HEADER_FIELDS[2]:-}")

if [[ -z "$BRANCH" || -z "$STRATEGY" ]]; then
  echo "ERROR: context JSON missing required fields (branch, strategy)" >&2
  exit 2
fi

# Idempotency: if SOURCE_SHA already lands on the rationalization branch via
# apply_log.tsv, treat as already-replayed.
if [[ -n "$SOURCE_SHA" && -f "$APPLY_LOG" ]]; then
  if awk -F'\t' -v s="$SOURCE_SHA" 'NR>1 && index($0, s)>0 {found=1} END{exit !found}' "$APPLY_LOG"; then
    log "source SHA $SOURCE_SHA already represented in apply_log.tsv; replay is a no-op"
    record_log SKIP "already-replayed (source_sha=$SOURCE_SHA in apply_log)"
    exit 0
  fi
fi

# Verify source SHA still resolves.
if [[ -n "$SOURCE_SHA" ]]; then
  if ! git -C "$PROJECT_ABS" cat-file -e "${SOURCE_SHA}^{commit}" 2>/dev/null; then
    echo "ERROR: source_sha $SOURCE_SHA no longer resolvable in repo" >&2
    record_log FAIL "source_sha gone: $SOURCE_SHA"
    exit 3
  fi
fi

log "replaying conflict resolution for slug=$SLUG branch=$BRANCH strategy=$STRATEGY source_sha=$SOURCE_SHA"

# Apply the recorded edits one by one.
EDIT_COUNT=$(json_context edit_count)
log "edits to apply: $EDIT_COUNT"

i=0
while [[ "$i" -lt "$EDIT_COUNT" ]]; do
  # Pull file/old/new for this edit. Use base64 to safely transit multi-line
  # strings between python3 and bash without interpreting them.
  mapfile -t EDIT_FIELDS < <(json_context edit "$i")
  EDIT_FILE=$(b64_decode "${EDIT_FIELDS[0]:-}")
  EDIT_OLD_B64="${EDIT_FIELDS[1]:-}"
  EDIT_NEW_B64="${EDIT_FIELDS[2]:-}"

  if [[ -z "$EDIT_FILE" ]]; then
    echo "ERROR: edit $i missing file field" >&2
    record_log FAIL "edit $i missing file"
    exit 2
  fi

  if ! abs_path=$(resolve_existing_replay_file "$EDIT_FILE"); then
    echo "ERROR: edit $i target file missing or unsafe: $EDIT_FILE" >&2
    record_log FAIL "edit $i target missing: $EDIT_FILE"
    exit 4
  fi

  # Verify `old` is present exactly once. We use python for safe multi-line
  # literal matching — no regex shenanigans (per AGENTS.md "No Script-Based
  # Changes"; the Edit tool's literal-string semantic is what we replicate).
  python3 - "$abs_path" "$EDIT_OLD_B64" "$EDIT_NEW_B64" <<'PY'
import base64, sys
path = sys.argv[1]
old = base64.b64decode(sys.argv[2]).decode("utf-8")
new = base64.b64decode(sys.argv[3]).decode("utf-8")
with open(path, "r", encoding="utf-8", errors="replace") as f:
    content = f.read()
n = content.count(old)
if n == 0:
    sys.stderr.write(f"DRIFT: 'old' text not found in {path}\n")
    sys.exit(4)
if n > 1:
    sys.stderr.write(f"AMBIGUOUS: 'old' text appears {n} times in {path}; refusing to replay\n")
    sys.exit(4)
content2 = content.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(content2)
PY
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    record_log FAIL "edit $i drift on $EDIT_FILE"
    exit 4
  fi
  log "applied edit $i: $EDIT_FILE"
  i=$((i+1))
done

# Run post-commands.
POST_COUNT=$(json_context post_count)
j=0
while [[ "$j" -lt "$POST_COUNT" ]]; do
  CMD=$(b64_decode "$(json_context post "$j")")
  log "running post-command: $CMD"
  if ! run_post_command "$CMD"; then
    echo "ERROR: post-command $j failed: $CMD" >&2
    record_log FAIL "post-command $j failed: $CMD"
    exit 6
  fi
  j=$((j+1))
done

# Run project gates.
profile_value() {
  local key="$1"
  if [[ -f "$PROFILE" ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"
      return
    fi
    python3 - "$PROFILE" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f: data = json.load(f)
v = data.get(sys.argv[2], "")
if isinstance(v, bool): print("true" if v else "false")
elif v is None: print("")
else: print(v)
PY
  fi
}

GATE_FAILED=0
for gate_key in test_command lint_command typecheck_command; do
  cmd=$(profile_value "$gate_key")
  [[ -z "$cmd" ]] && continue
  log "running gate $gate_key: $cmd"
  if ! ( cd "$PROJECT_ABS" && bash -c "$cmd" ); then
    echo "ERROR: gate $gate_key failed" >&2
    GATE_FAILED=1
    record_log FAIL "gate $gate_key failed"
    break
  fi
done

if [[ "$GATE_FAILED" -eq 1 ]]; then
  exit 7
fi

record_log OK "replay completed; ${EDIT_COUNT} edit(s), ${POST_COUNT} post-command(s)"
log "replay complete for slug=$SLUG"
echo "OK $SLUG"
exit 0
