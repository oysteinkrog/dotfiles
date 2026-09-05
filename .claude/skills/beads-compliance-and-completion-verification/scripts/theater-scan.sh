#!/usr/bin/env bash
# theater-scan.sh — Phase 5: scan one bead's evidence files for stubs/mocks/theater.
#
# Usage:
#   theater-scan.sh <project-path> <pass-dir>/beads/<bead-id>
#
# Reads spec.json + evidence.json from the bead dir; scans only the cited files.
# Emits theater.json conforming to references/EVIDENCE-SCHEMAS.md.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path}"
BEAD_DIR="${2:?bead dir}"
SPEC="$BEAD_DIR/spec.json"
EVIDENCE="$BEAD_DIR/evidence.json"
OUT="$BEAD_DIR/theater.json"

bead_id() {
  local id
  id="$(jq -r '.bead_id // empty' "$EVIDENCE" 2>/dev/null || true)"
  if [ -z "$id" ]; then
    id="$(jq -r '.bead_id // empty' "$SPEC" 2>/dev/null || true)"
  fi
  if [ -z "$id" ]; then
    id="$(basename "${BEAD_DIR%/}")"
  fi
  printf '%s' "$id"
}

write_empty_theater() {
  jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$(bead_id)" \
    '{bead_id: $id, scanned_at: $now, scanner: "scripts/theater-scan.sh", scanned_files: [], findings: [], summary: {BLOCKING: 0, MAJOR: 0, MINOR: 0, NOTE: 0}}' \
    > "$OUT"
}

write_blocking_pack_finding() {
  local cat="$1" path="$2" desc="$3"
  jq -n \
    --arg id "$(bead_id)" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cat "$cat" \
    --arg path "$path" \
    --arg desc "$desc" \
    '{
      bead_id: $id,
      scanned_at: $now,
      scanner: "scripts/theater-scan.sh",
      scanned_files: [],
      findings: [{
        id: "theater.1",
        severity: "BLOCKING",
        category: $cat,
        path: $path,
        line: 1,
        snippet: "",
        description: $desc
      }],
      summary: {BLOCKING: 1, MAJOR: 0, MINOR: 0, NOTE: 0}
    }' > "$OUT"
}

# Like write_blocking_pack_finding but emits a single non-BLOCKING finding,
# parameterised on severity / category. Used for Phase-3 extraction gaps so
# downstream scoring doesn't catastrophically zero Phase 4 (Axiom 4).
write_single_pack_finding() {
  local sev="$1" cat="$2" path="$3" desc="$4"
  jq -n \
    --arg id "$(bead_id)" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sev "$sev" \
    --arg cat "$cat" \
    --arg path "$path" \
    --arg desc "$desc" \
    '{
      bead_id: $id,
      scanned_at: $now,
      scanner: "scripts/theater-scan.sh",
      scanned_files: [],
      findings: [{
        id: "theater.1",
        severity: $sev,
        category: $cat,
        path: $path,
        line: 1,
        snippet: "",
        description: $desc
      }],
      summary: {
        BLOCKING: (if $sev == "BLOCKING" then 1 else 0 end),
        MAJOR:    (if $sev == "MAJOR"    then 1 else 0 end),
        MINOR:    (if $sev == "MINOR"    then 1 else 0 end),
        NOTE:     (if $sev == "NOTE"     then 1 else 0 end)
      }
    }' > "$OUT"
}

if [ ! -f "$SPEC" ]; then
  write_blocking_pack_finding "missing_spec" "spec.json" \
    "spec.json not found; Phase 5 cannot determine whether an empty theater scan is valid"
  exit 0
fi

if [ ! -f "$EVIDENCE" ]; then
  write_blocking_pack_finding "missing_evidence" "evidence.json" \
    "evidence.json not found; Phase 5 has no cited files to verify against theater patterns"
  exit 0
fi

if ! jq -e '.checks | type == "array"' "$EVIDENCE" >/dev/null 2>&1; then
  write_blocking_pack_finding "invalid_evidence_schema" "evidence.json" \
    "evidence.json is invalid or missing checks[]; Phase 5 cannot trust an empty citation set"
  exit 0
fi

if ! SCANNABLE_SPEC_ITEMS=$(jq -r '([
    .checklist.code_artifacts[]?,
    (.checklist.tests // {} | to_entries[]? | .value[]?)
  ] | length)' "$SPEC" 2>/dev/null); then
  write_blocking_pack_finding "invalid_spec_schema" "spec.json" \
    "spec.json is invalid; Phase 5 cannot determine whether an empty theater scan is valid"
  exit 0
fi

# Did spec.json itself extract any concrete code artifacts? When the answer
# is "no" we can't tell empty-evidence from a Phase-3 extraction gap apart
# from real theater — we'll demote findings accordingly below.
SPEC_CODE_ARTIFACT_COUNT="$(jq -r '(.checklist.code_artifacts // []) | length' "$SPEC" 2>/dev/null || echo 0)"

if ! PROJECT_REAL="$(cd "$PROJECT" 2>/dev/null && pwd -P)"; then
  write_blocking_pack_finding "invalid_project_path" "$PROJECT" \
    "project path cannot be resolved; Phase 5 cannot safely scan cited files"
  exit 0
fi
PROJECT="$PROJECT_REAL"

# Collect cited files (resolved against project root).
#
# v1.2 — exclude `.beads/` and `beads_compliance_audit/` paths. `.beads/issues.jsonl`
# is the bead store, not source code; scanning it produces categorically-wrong
# theater hits ("hardcoded_return"-looking JSON values, etc.) that tanked
# multiple beads in prior runs (notably `11n3`, `149j`). The audit-dir
# exclusion prevents the audit's own artifacts from feeding back into scans
# when a future bead happens to cite a passes/<UTC>/... path.
mapfile -t FILES < <(jq -r '.checks[] | .citations[]? | .path // empty' "$EVIDENCE" \
  | grep -Ev '^\.beads/|^beads_compliance_audit/|^\.git/' \
  | sort -u)

# Build a per-cited-path map of (line_start, line_end) ranges from evidence.json.
# A bead may cite the SAME file at multiple line ranges (e.g. tests.unit at
# 100-150 and tests.integration at 800-900); we union them. When a path has at
# least one range pair, theater scans for that path are RESTRICTED to lines
# within any of the ranges. Without ranges, the entire file is scanned (legacy
# behavior). This addresses the major-bug feedback: previously, a bead citing
# `src/lib.rs:12994-15068` would have findings reported from line 8756 etc. —
# completely outside its declared scope.
#
# Format on disk: $RANGES_DIR/<sanitized-path>.txt with one "<start> <end>"
# pair per line. Sanitizing replaces / with __SLASH__ so we get exactly one
# file per cited path. Disk-backed (not bash assoc-array) so this works under
# bash 3.2 too.
RANGES_DIR="$(mktemp -d)"
trap 'rm -rf "$RANGES_DIR"' EXIT
sanitize_path() {
  printf '%s' "$1" | sed 's|/|__SLASH__|g; s|\.\./|__UPDIR__|g'
}

while IFS=$'\t' read -r path start end; do
  [ -n "$path" ] || continue
  [[ "$start" =~ ^[0-9]+$ ]] || continue
  [[ "$end"   =~ ^[0-9]+$ ]] || continue
  # Skip degenerate "1..1" ranges — those are evidence.json's default placeholder
  # for "found the file but no specific lines named"; treat as whole-file.
  [ "$start" = "1" ] && [ "$end" = "1" ] && continue
  fname="$RANGES_DIR/$(sanitize_path "$path").txt"
  printf '%s %s\n' "$start" "$end" >> "$fname"
done < <(jq -r '
  .checks[]? | .citations[]? |
  select(.path != null) |
  [.path, (.line_start // 1 | tostring), (.line_end // 1 | tostring)] |
  @tsv
' "$EVIDENCE" 2>/dev/null)

# Test whether a (path, line) pair is within any cited range for that path.
# Returns 0 (in-range, OR no ranges declared = whole-file scan) and 1 (out of range).
in_cited_range() {
  local p="$1" line="$2"
  local fname
  fname="$RANGES_DIR/$(sanitize_path "$p").txt"
  [ -f "$fname" ] || return 0     # No range declared → scan whole file (legacy).
  [[ "$line" =~ ^[0-9]+$ ]] || return 0
  while IFS=' ' read -r s e; do
    [[ "$s" =~ ^[0-9]+$ ]] || continue
    [[ "$e" =~ ^[0-9]+$ ]] || continue
    if [ "$line" -ge "$s" ] && [ "$line" -le "$e" ]; then
      return 0
    fi
  done < "$fname"
  return 1
}
if [ "${#FILES[@]}" -eq 0 ]; then
  if [ "$SCANNABLE_SPEC_ITEMS" -gt 0 ] && [ "$SPEC_CODE_ARTIFACT_COUNT" -gt 0 ]; then
    # Spec named explicit code artifacts AND evidence cites nothing. This is
    # genuine theater: the spec told us where to look, but Phase 3 found
    # nothing. Keep the BLOCKING signal (Axiom 4 will zero Phase 4).
    write_blocking_pack_finding "missing_evidence_citations" "evidence.json" \
      "spec.json names code artifacts, but evidence.json cites no files for Phase 5 to scan"
  elif [ "$SCANNABLE_SPEC_ITEMS" -gt 0 ]; then
    # Spec named test types or other items but no concrete code artifacts —
    # the description is too prose-heavy for Phase 3's heuristic baseline to
    # extract file paths. Demote to MAJOR + a distinct category so the
    # scorer attributes it to extraction gap, not to closer theater.
    # (Real theater on this surface is caught by the other patterns below
    # when files ARE cited.)
    write_single_pack_finding "MAJOR" "phase_3_extraction_gap" "evidence.json" \
      "spec.json has scannable items but no code artifacts; Phase 3's deterministic heuristic could not extract file:line citations from prose. Re-run Phase 3 with the evidence-gatherer subagent for richer extraction; this is an extraction-coverage gap, not a closer-side theater finding."
  else
    write_empty_theater
  fi
  exit 0
fi

for f in "${FILES[@]}"; do
  case "$f" in
    ""|/*|..|../*|*/../*|*/..)
      write_blocking_pack_finding "invalid_evidence_path" "$f" \
        "evidence citation paths must be relative paths inside the project root"
      exit 0
      ;;
  esac

  full="$PROJECT/$f"
  [ -f "$full" ] || continue
  if ! resolved_file="$(realpath "$full" 2>/dev/null)"; then
    write_blocking_pack_finding "invalid_evidence_path" "$f" \
      "cited file exists but cannot be resolved safely"
    exit 0
  fi
  case "$resolved_file" in
    "$PROJECT"/*|"$PROJECT")
      ;;
    *)
      write_blocking_pack_finding "invalid_evidence_path" "$f" \
        "evidence citation resolves outside the project root"
      exit 0
      ;;
  esac
done

NO_MOCKS=$(jq -r '.constraints.no_mocks // false' "$SPEC")
# `subagents/theater-detector.md` promises that `spec.constraints.allowed_mocks`
# entries demote `mock_where_forbidden` BLOCKING findings to NOTE for the
# named services. The deterministic baseline below honours the binary
# `no_mocks` flag and now also down-grades findings whose snippet matches an
# allowed-mock name. (Previously this variable was read into ALLOWED_MOCKS
# and never used — silently ignoring the documented allow-list.)
ALLOWED_MOCKS=$(jq -r '.constraints.allowed_mocks[]?' "$SPEC" 2>/dev/null)

# Findings accumulator on disk (not as a giant shell variable). For beads with
# many cited paths and many findings, the prior in-memory variant could blow
# past ARG_MAX when the final jq invocation slurped FILES inline. Disk-backed
# JSONL avoids that scaling failure (Bug 4 in v1.0).
FINDINGS_FILE="$(mktemp)"
trap 'rm -rf "$RANGES_DIR" "$FINDINGS_FILE"' EXIT
: > "$FINDINGS_FILE"

# Track total findings across all add() calls so id assignment is monotonic.
FINDING_COUNTER=0

add() {
  local sev="$1" cat="$2" path="$3" line="$4" snippet="$5" desc="$6" pattern="${7:-}"
  FINDING_COUNTER=$((FINDING_COUNTER + 1))
  jq -n \
    --arg sev "$sev" --arg cat "$cat" --arg path "$path" \
    --argjson line "$line" --arg snippet "$snippet" --arg desc "$desc" \
    --arg pattern "$pattern" --argjson n "$FINDING_COUNTER" \
    '{
      id: ("theater." + ($n | tostring)),
      severity: $sev,
      category: $cat,
      pattern: (if $pattern == "" then null else $pattern end),
      path: $path,
      line: $line,
      snippet: $snippet,
      description: $desc
    }' \
    >> "$FINDINGS_FILE"
}

# Helper: scan a pattern across cited files. ripgrep skips binary files by
# default; --no-messages silences "binary matches" / "no such file" stderr
# noise; only-matching is avoided since we want the full snippet for context.
#
# v1.1 changes:
#   * `in_cited_range "$f" "$line"` filters matches to declared line ranges
#     (Bug 2f).
#   * `pattern` arg propagated into add() so downstream consumers can
#     group/filter by detector pattern (Bug 6).
scan_pattern() {
  local pattern="$1" sev="$2" cat="$3" desc="$4"
  local f full path line snippet
  for f in "${FILES[@]}"; do
    full="$PROJECT/$f"
    [ -f "$full" ] || continue
    while IFS=: read -r path line snippet; do
      # Skip rg's own "Binary file ... matches" messages and lines without a numeric line number.
      [[ "$path" == "Binary file"* ]] && continue
      [[ "$line" =~ ^[0-9]+$ ]] || continue
      [ -n "$snippet" ] || continue
      in_cited_range "$f" "$line" || continue
      add "$sev" "$cat" "$f" "$line" "$snippet" "$desc" "$pattern"
    done < <(rg -nH --no-heading --no-messages "$pattern" "$full" 2>/dev/null || true)
  done
}

# Helper: returns 0 if line is inside a comment OR a string literal (Rust/JS/Py).
# Used to suppress false positives from regex matches that LOOK like real code
# patterns but are actually documentation prose or hardcoded examples in a
# usage message.
#
# Heuristic — by no means a parser:
#   * starts with `//`, `*`, `/*`, `<!--`, OR `#` → comment line
#     EXCEPT `#[outer_attr]` and `#![inner_attr]` (Rust attribute decorators
#     are NOT comments — they're compiled into the AST).
#   * stripped of strings, the pattern itself disappears → was inside a string
#     literal (best-effort: handles "...", '...', `...` for one-line strings).
is_in_comment_or_string() {
  local snippet="$1" pattern="$2"
  local trimmed
  trimmed="$(printf '%s' "$snippet" | sed -E 's/^[[:space:]]+//')"
  case "$trimmed" in
    "//"*|"*"*|"/*"*|"<!--"*) return 0 ;;
    "#["*|"#!["*) ;;             # Rust attribute (`#[outer]` / `#![inner]`) — NOT a comment.
    "#"*) return 0 ;;            # Otherwise `#` introduces a Python/shell/Ruby/conf comment.
  esac
  # Strip simple string literals; if the pattern no longer matches, it was
  # entirely inside a string. Best-effort regex; doesn't handle escapes.
  local stripped
  stripped="$(printf '%s' "$snippet" | python3 -c '
import re, sys
s = sys.stdin.read()
# Strip "..."  '\''...'\''  `...` — non-greedy, single-line.
s = re.sub(r"\"(?:[^\"\\]|\\.)*\"", "", s)
s = re.sub(r"'\''(?:[^'\''\\]|\\.)*'\''", "", s)
s = re.sub(r"`(?:[^`\\]|\\.)*`", "", s)
sys.stdout.write(s)
' 2>/dev/null || printf '%s' "$snippet")"
  if ! printf '%s' "$stripped" | rg -q "$pattern" 2>/dev/null; then
    return 0
  fi
  return 1
}

# Pattern 1: unimplemented / todo macros / NotImplementedError
scan_pattern 'unimplemented!\(|todo!\(|panic!\("not implemented|NotImplementedError|raise NotImplementedError' \
  "BLOCKING" "unimplemented_macro" "Explicit unimplemented placeholder in claimed implementation"

# Pattern 2: hardcoded trivial returns in implementation.
#
# IDIOMATIC RUST EXCLUSIONS (Bug 2a in v1.0): the following are valid early-
# return patterns, NOT theater:
#   * `return None;`        — Option<T> early return (legitimate when fn -> Option<_>)
#   * `return Ok(());`      — fn -> Result<()>; correct success-no-value return
#   * `return Err(...);`    — Result<_, E> early return
#   * `return false;` / `return true;` inside predicate functions — legitimate
# Therefore we use language-specific patterns:
#   * Python (.py): includes None / True / False (Python theater pattern)
#   * JS/TS (.js, .ts, .jsx, .tsx): includes null / undefined / true / false
#   * Rust (.rs): ONLY `Default::default()` (everything else is too often
#     legitimate; unimplemented_macro Pattern 1 catches the obvious Rust theater)
#   * Other (default): broadest set
hardcoded_return_pattern_py='^[[:space:]]*return[[:space:]]+(0|""|\[\]|\{\}|None|True|False)[[:space:]]*$'
hardcoded_return_pattern_js='^[[:space:]]*return[[:space:]]+(0|""|\[\]|\{\}|null|undefined|true|false)[[:space:]]*;?[[:space:]]*$'
hardcoded_return_pattern_rs='^[[:space:]]*return[[:space:]]+Default::default\(\)[[:space:]]*[;)]?[[:space:]]*$'
hardcoded_return_pattern_default='^[[:space:]]*return[[:space:]]+(Default::default\(\)|\{\}|\[\]|""|0)[[:space:]]*[;)]?[[:space:]]*$'

select_hardcoded_pattern() {
  case "$1" in
    *.py)            printf '%s' "$hardcoded_return_pattern_py" ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
                     printf '%s' "$hardcoded_return_pattern_js" ;;
    *.rs)            printf '%s' "$hardcoded_return_pattern_rs" ;;
    *)               printf '%s' "$hardcoded_return_pattern_default" ;;
  esac
}

for f in "${FILES[@]}"; do
  full="$PROJECT/$f"
  [ -f "$full" ] || continue
  hardcoded_return_pattern="$(select_hardcoded_pattern "$f")"
  while IFS=: read -r path line snippet; do
    [[ "$path" == "Binary file"* ]] && continue
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    [ -n "$snippet" ] || continue
    in_cited_range "$f" "$line" || continue
    is_in_comment_or_string "$snippet" "$hardcoded_return_pattern" && continue
    add "MAJOR" "hardcoded_return" "$f" "$line" "$snippet" \
      "Function returns a trivial constant — verify caller dependency" "$hardcoded_return_pattern"
  done < <(rg -nH --no-heading --no-messages "$hardcoded_return_pattern" "$full" 2>/dev/null || true)
done

# Pattern 3: assert true / expect(true).toBe(true) / self.assertTrue(True)
scan_pattern 'assert\s*\(?\s*true\s*\)?$|expect\(true\)\.toBe\(true\)|self\.assertTrue\(True\)|assert!\(true\)' \
  "BLOCKING" "trivial_assertion" "Test assertion is trivially true — provides no verification"

# Pattern 4: skipped tests
#
# v1.1: only flag the actual `#[ignore]` attribute decorator at the start of a
# line (i.e. real Rust attribute) — not comments referencing it. JS/TS
# `it.skip()`, `test.skip()`, `describe.skip()` patterns are still flagged
# as-is because they are real call sites.
skipped_test_pattern='it\.skip\(|test\.skip\(|describe\.skip\(|^[[:space:]]*#\[ignore\]'
for f in "${FILES[@]}"; do
  full="$PROJECT/$f"
  [ -f "$full" ] || continue
  while IFS=: read -r path line snippet; do
    [[ "$path" == "Binary file"* ]] && continue
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    [ -n "$snippet" ] || continue
    in_cited_range "$f" "$line" || continue
    # Reject lines that are clearly comments mentioning #[ignore] in prose.
    is_in_comment_or_string "$snippet" "$skipped_test_pattern" && continue
    add "MAJOR" "skipped_test" "$f" "$line" "$snippet" \
      "Test is skipped — claims to exist without verifying anything" "$skipped_test_pattern"
  done < <(rg -nH --no-heading --no-messages "$skipped_test_pattern" "$full" 2>/dev/null || true)
done

# Pattern 5: cfg(test) guards in implementation.
#
# v1.2 fixes Bug 2e — `#[cfg(test)]` is IDIOMATIC Rust, not theater. It's the
# canonical way to mark test-only code (impls, mods, helpers) so they don't
# bloat release binaries. Across the user's prior runs this single pattern
# tanked four beads (`11n3`, `2f4x`, `9yw1`, `dwec`) by flagging legitimate
# `#[cfg(test)] mod tests { ... }` blocks as production-path bypass.
#
# Resolution: split the pattern by language.
#   * Rust (.rs) — only `if cfg!(test)` (a runtime branch in production code
#     that intentionally diverges between test and release; legitimately
#     suspicious). The `#[cfg(test)]` ATTRIBUTE is excluded — it's compile-time
#     gating, not a production-path divergence.
#   * JS/TS — `process.env.NODE_ENV === 'test'` runtime branches still flagged.
#   * Other — keep the broad pattern (caller can refine per language).
cfg_test_pattern_rs='if[[:space:]]+cfg!\(test\)'
cfg_test_pattern_js='process\.env\.NODE_ENV.*===.*['"'"'"]test'
cfg_test_pattern_default='if[[:space:]]+cfg!\(test\)|#\[cfg\(test\)\]|process\.env\.NODE_ENV.*===.*['"'"'"]test'

select_cfg_test_pattern() {
  case "$1" in
    *.rs)            printf '%s' "$cfg_test_pattern_rs" ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
                     printf '%s' "$cfg_test_pattern_js" ;;
    *)               printf '%s' "$cfg_test_pattern_default" ;;
  esac
}

for f in "${FILES[@]}"; do
  full="$PROJECT/$f"
  [ -f "$full" ] || continue
  cfg_test_pattern="$(select_cfg_test_pattern "$f")"
  while IFS=: read -r path line snippet; do
    [[ "$path" == "Binary file"* ]] && continue
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    [ -n "$snippet" ] || continue
    in_cited_range "$f" "$line" || continue
    is_in_comment_or_string "$snippet" "$cfg_test_pattern" && continue
    add "MAJOR" "conditional_skip_in_test_mode" "$f" "$line" "$snippet" \
      "Code branches differently in test mode; production path may not be exercised" "$cfg_test_pattern"
  done < <(rg -nH --no-heading --no-messages "$cfg_test_pattern" "$full" 2>/dev/null || true)
done

# Pattern 6: mocks where forbidden. Allowed-mock names from
# spec.constraints.allowed_mocks demote findings whose snippet contains the
# allowed name to NOTE (per subagents/theater-detector.md's contract).
if [ "$NO_MOCKS" = "true" ]; then
  if [ -z "$ALLOWED_MOCKS" ]; then
    # Fast path: no allow-list — every mock-library hit is BLOCKING.
    scan_pattern 'jest\.mock\(|sinon\.|nock\(|httpmock|mockall|MagicMock\(|Mock\(' \
      "BLOCKING" "mock_where_forbidden" "Bead spec forbids mocks; mock library usage detected"
  else
    # Allow-list present: scan and post-process to demote rows whose snippet
    # mentions any allowed name. Implemented inline (rather than via the
    # generic scan_pattern helper) so we can inspect each match before
    # categorising. Same per-file loop shape as scan_pattern.
    mock_pattern='jest\.mock\(|sinon\.|nock\(|httpmock|mockall|MagicMock\(|Mock\('
    for f in "${FILES[@]}"; do
      full="$PROJECT/$f"
      [ -f "$full" ] || continue
      while IFS=: read -r path line snippet; do
        [[ "$path" == "Binary file"* ]] && continue
        [[ "$line" =~ ^[0-9]+$ ]] || continue
        [ -n "$snippet" ] || continue
        in_cited_range "$f" "$line" || continue
        # Demote to NOTE if any allowed-mock name is mentioned in the snippet.
        sev="BLOCKING"
        cat="mock_where_forbidden"
        desc="Bead spec forbids mocks; mock library usage detected"
        while IFS= read -r allowed; do
          [ -z "$allowed" ] && continue
          if printf '%s' "$snippet" | grep -qF "$allowed"; then
            sev="NOTE"
            cat="mock_allowlisted"
            desc="Mock allowed for service '$allowed' per spec.constraints.allowed_mocks"
            break
          fi
        done <<< "$ALLOWED_MOCKS"
        add "$sev" "$cat" "$f" "$line" "$snippet" "$desc" "$mock_pattern"
      done < <(rg -nH --no-heading --no-messages "$mock_pattern" "$full" 2>/dev/null || true)
    done
  fi
fi

# Pattern 7: sleep as fake work in production paths.
#
# v1.1 fixes Bug 2b — prior version flagged ALL sleep calls as BLOCKING, which
# made every production retry/backoff loop register as theater (~9 false
# positives per Rust bead in field testing). Tightened heuristics:
#
#   * Skip files whose path mentions `test/`, `spec/`, `fuzz/`, `bench/`.
#   * Skip lines inside comments / strings (best-effort).
#   * Require sleep duration to be >= 1000ms (1 second) OR explicit literal
#     "delay"/"wait" in the same line. Sub-second sleeps are overwhelmingly
#     legitimate retry/backoff/debounce; sleeps measured in seconds are much
#     more likely to be "fake work to make output look slower" or simulating
#     I/O the impl was supposed to do for real.
#   * Skip lines whose nearby context (3 lines before) contains
#     retry/backoff keywords — `retry`, `backoff`, `attempt`, `poll`,
#     `wait_for`, `tokio::time::interval`, `Instant::now`. These are signals
#     of legitimate use even at small durations.
#   * Severity downgraded to MAJOR (was BLOCKING) — the heuristic still
#     produces some FPs and BLOCKING zeros the dimension.
#
# The pattern itself is unchanged; we filter inside the loop.
sleep_pattern='\bsleep\(|thread::sleep|time\.sleep|setTimeout|tokio::time::sleep|asyncio\.sleep'
for f in "${FILES[@]}"; do
  case "$f" in
    *test*|*spec*|*fuzz*|*bench*) continue ;;
  esac
  full="$PROJECT/$f"
  [ -f "$full" ] || continue
  while IFS=: read -r path line snippet; do
    [[ "$path" == "Binary file"* ]] && continue
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    [ -n "$snippet" ] || continue
    in_cited_range "$f" "$line" || continue
    is_in_comment_or_string "$snippet" "$sleep_pattern" && continue

    # Reject if the snippet is plausibly part of a retry/backoff loop.
    # We pull the 3 preceding lines and grep for retry-style tokens.
    context_start=$((line - 3))
    [ "$context_start" -lt 1 ] && context_start=1
    if sed -n "${context_start},${line}p" "$full" 2>/dev/null \
        | rg -q -i 'retry|backoff|attempt|poll|wait_for|interval|debounce|throttle|jitter' 2>/dev/null; then
      continue
    fi

    # Extract duration — flag only if explicitly >= 1 second, or if there's
    # no parseable duration AND no retry context (handled above).
    #
    # Order matters: check the LONGEST plausible duration first, then shorter.
    # If a snippet contains both `from_secs(5)` AND `from_micros(10)` (unusual
    # but possible), we want the from_secs match to dominate — flagging a
    # multi-second sleep is the correct verdict even when a sub-second
    # variant is also lexically present in the same line.
    flag=1
    if [[ "$snippet" =~ Duration::from_secs\(([0-9]+)\) ]]; then
      : # always flag sleeps measured in whole seconds
    elif [[ "$snippet" =~ from_millis\(([0-9]+)\) ]]; then
      ms="${BASH_REMATCH[1]}"
      [ "$ms" -lt 1000 ] && flag=0
    elif [[ "$snippet" =~ (time|asyncio|trio|anyio)\.sleep\(([0-9]+(\.[0-9]+)?)\) ]]; then
      # Python stdlib + asyncio/trio/anyio: arg is seconds (float).
      sec="${BASH_REMATCH[2]}"
      awk -v s="$sec" 'BEGIN{exit !(s>=1)}' || flag=0
    elif [[ "$snippet" =~ setTimeout\([^,]+,[[:space:]]*([0-9]+) ]]; then
      ms="${BASH_REMATCH[1]}"
      [ "$ms" -lt 1000 ] && flag=0
    elif [[ "$snippet" =~ from_(micros|nanos)\( ]]; then
      # micros/nanos are by definition sub-second; never theater. Skip.
      # Checked LAST so a co-located from_secs (above) wins.
      flag=0
    fi
    [ "$flag" = "0" ] && continue
    add "MAJOR" "sleep_as_fake_work" "$f" "$line" "$snippet" \
      "sleep() in production code path with non-trivial duration — verify it isn't simulating real I/O" "$sleep_pattern"
  done < <(rg -nH --no-heading --no-messages "$sleep_pattern" "$full" 2>/dev/null || true)
done

# Pattern 8: 501 Not Implemented in API routes.
#
# v1.1 fixes Bug 2c — bare `\b501\b` matched SQL VALUES (501, ...) and
# Rust `Some(501)` in non-HTTP contexts. We now require HTTP-status context:
# the snippet must mention `status`, `code`, `Status`, `StatusCode`, `respond`,
# `response`, `http`, OR the literal phrase "Not Implemented".
api_501_pattern='Not Implemented|not.yet.implemented|StatusCode::NOT_IMPLEMENTED|HttpStatus\.NOT_IMPLEMENTED|status\s*[=:]\s*501\b|status_code\s*[=:]\s*501\b|\.status\(501\)|HTTP/1\.[01]\s+501\b|response.*\b501\b|respond.*\b501\b|res\.status\s*\(\s*501\s*\)'
for f in "${FILES[@]}"; do
  full="$PROJECT/$f"
  [ -f "$full" ] || continue
  while IFS=: read -r path line snippet; do
    [[ "$path" == "Binary file"* ]] && continue
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    [ -n "$snippet" ] || continue
    in_cited_range "$f" "$line" || continue
    add "MAJOR" "api_501_stub" "$f" "$line" "$snippet" \
      "Returns 501 Not Implemented or HTTP-status-501 stub — likely route stub" "$api_501_pattern"
  done < <(rg -nH --no-heading --no-messages "$api_501_pattern" "$full" 2>/dev/null || true)
done

# Pattern 9: TODO / FIXME / HACK / XXX (MINOR by default).
# Markdown / RST / AsciiDoc files often contain literal "TODO" inside fenced
# code blocks or inline backticks as part of EXAMPLE commands (e.g. a README
# showing `cass search "TODO"`). Those aren't incomplete-code markers.
# For doc-style files we strip code blocks via a small python helper before
# scanning; for code files we require a comment marker before the keyword
# so string literals like `cass search "TODO"` and CLI usage examples don't
# false-positive (Bug 2d in v1.0).
scan_pattern_codefiles_only() {
  # Same as scan_pattern but skips files with the doc-style extensions below
  # AND requires the keyword to be preceded by a comment marker (//, #, /*,
  # *, ;).
  local pattern="$1" sev="$2" cat="$3" desc="$4"
  local f full path line snippet
  for f in "${FILES[@]}"; do
    case "$f" in
      *.md|*.markdown|*.mdx|*.rst|*.adoc|*.asciidoc|*.txt) continue ;;
    esac
    full="$PROJECT/$f"
    [ -f "$full" ] || continue
    while IFS=: read -r path line snippet; do
      [[ "$path" == "Binary file"* ]] && continue
      [[ "$line" =~ ^[0-9]+$ ]] || continue
      [ -n "$snippet" ] || continue
      in_cited_range "$f" "$line" || continue
      # Require comment context: the keyword must follow a comment marker
      # (//, #, /*, *<space>, ;) — bare string literals and hardcoded
      # identifiers are NOT TODOs. This is the false-positive defense for
      # `cass search "TODO"` and similar usage examples (Bug 2d in v1.0).
      #
      # CRITICAL: wrap "$pattern" in (?:...) — caller passes
      # `TODO|FIXME|HACK|XXX` (with `|`) and `|` has the lowest regex
      # precedence, so without the non-capturing group the alternation
      # would split the WHOLE regex, leaving FIXME/HACK/XXX matching
      # anywhere without the comment-marker requirement.
      printf '%s' "$snippet" | rg -q '(^|[[:space:]])(//|#|/\*|\*[[:space:]]|;)[[:space:]]*[^"`'\'']*(?:'"$pattern"')' 2>/dev/null \
        || continue
      add "$sev" "$cat" "$f" "$line" "$snippet" "$desc" "$pattern"
    done < <(rg -nH --no-heading --no-messages "$pattern" "$full" 2>/dev/null || true)
  done
}

# Doc-style scan that strips fenced code blocks AND inline backtick spans
# before grepping for the marker words, so README / docs examples don't
# false-positive.
scan_doc_pattern() {
  local pattern="$1" sev="$2" cat="$3" desc="$4"
  local f full
  for f in "${FILES[@]}"; do
    case "$f" in
      *.md|*.markdown|*.mdx|*.rst|*.adoc|*.asciidoc|*.txt) ;;
      *) continue ;;
    esac
    full="$PROJECT/$f"
    [ -f "$full" ] || continue
    while IFS=$'\t' read -r line snippet; do
      [[ "$line" =~ ^[0-9]+$ ]] || continue
      [ -n "$snippet" ] || continue
      in_cited_range "$f" "$line" || continue
      add "$sev" "$cat" "$f" "$line" "$snippet" "$desc" "$pattern"
    done < <(python3 - "$full" "$pattern" <<'PY' 2>/dev/null || true
import re, sys
path, pattern = sys.argv[1], sys.argv[2]
try:
    text = open(path, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)
lines = text.splitlines()
in_fence = False
fence_marker = None
out_lines = []
for raw in lines:
    stripped = raw.lstrip()
    # Detect fenced code block transitions (``` or ~~~). Same marker (3+ of
    # the same char) opens and closes the block.
    m = re.match(r'^(```+|~~~+)', stripped)
    if m:
        marker = m.group(1)[0]  # ` or ~
        if not in_fence:
            in_fence = True
            fence_marker = marker
        elif fence_marker == marker:
            in_fence = False
            fence_marker = None
        out_lines.append("")
        continue
    if in_fence:
        out_lines.append("")  # mask code block contents
        continue
    # Strip inline backtick spans (greedy across single backticks).
    cleaned = re.sub(r'`[^`]*`', '', raw)
    out_lines.append(cleaned)
rx = re.compile(pattern)
for i, line in enumerate(out_lines, start=1):
    m = rx.search(line)
    if m:
        # Emit the ORIGINAL source line (so the reviewer sees full context),
        # tab-separated from the line number.
        snippet = lines[i-1].strip()[:200]
        snippet = snippet.replace("\t", " ")
        sys.stdout.write(f"{i}\t{snippet}\n")
PY
)
  done
}

scan_pattern_codefiles_only 'TODO|FIXME|HACK|XXX' \
  "MINOR" "todo_comment" "TODO/FIXME/HACK/XXX comment in claimed evidence file"
scan_doc_pattern 'TODO|FIXME|HACK|XXX' \
  "MINOR" "todo_comment" "TODO/FIXME/HACK/XXX in claimed doc file (outside code blocks / inline backticks)"

# Build the output.
#
# v1.1 — both findings AND scanned_files are now sourced from disk (FINDINGS_FILE
# and a pipe of FILES into stdin) rather than passed inline as `--argjson`. The
# inline form blew past ARG_MAX for beads citing many files (Bug 4 in v1.0,
# observed at 47 cited paths). Disk-based slurpfile / stdin scales linearly and
# costs no measurable wall time.

# Convert the JSONL findings file to a JSON array, sorted by id (which is
# already monotonic via FINDING_COUNTER). An empty FINDINGS_FILE produces [].
if [ -s "$FINDINGS_FILE" ]; then
  jq -s '.' "$FINDINGS_FILE" > "$FINDINGS_FILE.array"
else
  echo '[]' > "$FINDINGS_FILE.array"
fi

# Compute summary counts directly from the array file.
SUMMARY=$(jq '{
  BLOCKING: (map(select(.severity == "BLOCKING")) | length),
  MAJOR:    (map(select(.severity == "MAJOR"))    | length),
  MINOR:    (map(select(.severity == "MINOR"))    | length),
  NOTE:     (map(select(.severity == "NOTE"))     | length)
}' "$FINDINGS_FILE.array")

# Build the scanned_files array via stdin pipe to avoid command-line bloat.
SCANNED_FILES_FILE="$(mktemp)"
trap 'rm -rf "$RANGES_DIR" "$FINDINGS_FILE" "$FINDINGS_FILE.array" "$SCANNED_FILES_FILE"' EXIT
printf '%s\n' "${FILES[@]}" | jq -R . | jq -s . > "$SCANNED_FILES_FILE"

# Atomic write: build the output in a sibling tmp file, then mv into place.
# A jq failure here previously left $OUT half-written or empty, which then
# crashed the downstream scorer with `jq: invalid JSON text` because $OUT
# was no longer parseable. Atomic rename means $OUT either reflects the
# previous successful run OR the new complete payload — never a partial.
OUT_TMP="$(mktemp "$OUT.tmp.XXXXXX")"
trap 'rm -rf "$RANGES_DIR" "$FINDINGS_FILE" "$FINDINGS_FILE.array" "$SCANNED_FILES_FILE" "$OUT_TMP"' EXIT
if ! jq -n \
  --arg id "$(jq -r .bead_id "$EVIDENCE")" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile files "$SCANNED_FILES_FILE" \
  --slurpfile findings "$FINDINGS_FILE.array" \
  --argjson summary "$SUMMARY" \
  '{
    bead_id: $id,
    scanned_at: $now,
    scanner: "scripts/theater-scan.sh",
    scanned_files: $files[0],
    findings: $findings[0],
    summary: $summary
  }' > "$OUT_TMP"; then
  rm -f "$OUT_TMP"
  echo "ERROR: theater-scan.sh: failed to assemble theater.json (jq error)" >&2
  exit 1
fi
mv "$OUT_TMP" "$OUT"

echo "Theater scan complete: $(printf '%s' "$SUMMARY" | jq -r '. | "BLOCKING=\(.BLOCKING) MAJOR=\(.MAJOR) MINOR=\(.MINOR)"')" >&2
