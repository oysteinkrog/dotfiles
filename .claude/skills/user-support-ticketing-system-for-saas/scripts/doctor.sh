#!/usr/bin/env bash
# doctor.sh — green/red readiness check for the ticketing-system skill.
#
# Run this before invoking any of the EXACT PROMPTS. Exits 0 only when the
# host project has the prerequisites the skill assumes; otherwise exits 1
# with a per-check report.
#
# Usage:
#   ./scripts/doctor.sh                 # human-readable
#   ./scripts/doctor.sh --json          # machine-readable for piping into a planner
#   ./scripts/doctor.sh --portable      # invariant-first check for non-default stacks
#   ./scripts/doctor.sh --strict        # fail on any optional check too
#
# Exit codes:
#   0 — all required checks passed
#   1 — at least one required check failed
#   2 — bad invocation

set -uo pipefail

JSON=0
STRICT=0
PROFILE="default"
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --strict) STRICT=1 ;;
    --portable) PROFILE="portable" ;;
    --profile=default) PROFILE="default" ;;
    --profile=portable) PROFILE="portable" ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "doctor.sh: unknown arg '$arg'" >&2; exit 2 ;;
  esac
done

# Each check appends to these arrays.
declare -a NAMES STATUSES MESSAGES SEVERITIES

check() {
  local name="$1" severity="$2" status="$3" message="$4"
  NAMES+=("$name"); STATUSES+=("$status"); MESSAGES+=("$message"); SEVERITIES+=("$severity")
}

default_stack_severity() {
  if [[ "$PROFILE" == "portable" ]]; then
    printf 'info'
  else
    printf 'required'
  fi
}

default_stack_missing_status() {
  if [[ "$PROFILE" == "portable" ]]; then
    printf 'warn'
  else
    printf 'fail'
  fi
}

check "doctor-profile" info pass "Profile=$PROFILE"

# ---- universal checks (failure → exit 1 in every profile) ----

if [[ -f package.json || -f pyproject.toml || -f requirements.txt || -f Gemfile || -f go.mod || -f Cargo.toml || -f composer.json || -f mix.exs || -d .git ]]; then
  check "project-root" required pass "Recognized project root"
else
  check "project-root" required fail "No recognizable project marker found; run from the target project root"
fi

# ---- required checks (failure → exit 1) ----

default_severity="$(default_stack_severity)"
missing_status="$(default_stack_missing_status)"

if [[ -f drizzle.config.ts || -f drizzle.config.mts || -f drizzle.config.js ]]; then
  check "drizzle-config" "$default_severity" pass "Drizzle config found"
else
  check "drizzle-config" "$default_severity" "$missing_status" "Drizzle not found; use FRAMEWORK-PORTABILITY.md if the host stack uses another persistence layer"
fi

if [[ -d src/lib/services ]]; then
  check "service-layer-dir" "$default_severity" pass "src/lib/services/ exists"
else
  check "service-layer-dir" "$default_severity" "$missing_status" "Default service-layer dir missing; map the equivalent service boundary before coding"
fi

if [[ -d src/app/api/admin ]]; then
  check "admin-api-dir" "$default_severity" pass "Admin API tree present"
else
  check "admin-api-dir" "$default_severity" "$missing_status" "Default admin API tree missing; map the equivalent admin controller/API surface"
fi

if [[ -f package.json ]] && grep -q '"resend"' package.json; then
  check "resend-sdk" "$default_severity" pass "Resend SDK installed"
else
  check "resend-sdk" "$default_severity" "$missing_status" "Resend SDK not detected; choose the host project's email provider boundary"
fi

if [[ -f .env.local || -f .env ]]; then
  if grep -hqE '^RESEND_API_KEY=.+' .env.local .env 2>/dev/null; then
    check "resend-env" "$default_severity" pass "RESEND_API_KEY set"
  else
    check "resend-env" "$default_severity" "$missing_status" "RESEND_API_KEY missing; document the actual provider env vars in the handoff"
  fi
else
  check "resend-env" "$default_severity" "$missing_status" "No .env or .env.local found; document how the host project manages secrets"
fi

# ---- informational checks (failure → message but exit still 0 unless --strict) ----

if [[ -f src/lib/services/support-tickets.ts ]]; then
  check "support-service-exists" info warn "support-tickets.ts ALREADY exists — use Prompt 2 (audit/expand), not Prompt 1 (build)"
else
  check "support-service-exists" info pass "Greenfield: Prompt 1 (build) is appropriate"
fi

if [[ -f src/app/api/cron/sla-alerts/route.ts ]]; then
  check "sla-cron" info pass "SLA cron route present"
else
  check "sla-cron" info warn "SLA cron not yet wired (expected for Phase 5)"
fi

if [[ "$PROFILE" == "portable" ]]; then
  check "background-side-effects" info warn "Map the host queue/outbox/background-job primitive; Next.js after() is only the default-stack example"
elif grep -rqE '(^|[^[:alnum:]_])after[[:space:]]*\(' src/app 2>/dev/null; then
  check "after-helper" info pass "next/server after() likely used (non-blocking email path)"
else
  check "after-helper" info warn "next/server after() not yet used — needed for non-blocking email"
fi

if [[ "$PROFILE" == "portable" ]]; then
  check "scheduled-jobs" info warn "Map the host scheduler/worker for SLA alerts; Vercel cron is only the default-stack example"
elif [[ -f vercel.json ]] && grep -q '"crons"' vercel.json; then
  check "vercel-cron-config" info pass "Vercel cron schedule registered"
else
  check "vercel-cron-config" info warn "No Vercel cron schedule (or non-Vercel host)"
fi

# ---- companion skills (de-slopify is a Hard Invariant — required) ----

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SEARCH_PATHS=(
  "${CLAUDE_SKILLS_PATH:-}"
  "$HOME/.claude/skills"
  ".claude/skills"
)

found_de_slopify=""
for base in "${SKILL_SEARCH_PATHS[@]}"; do
  [[ -z "$base" ]] && continue
  if [[ -f "$base/de-slopify/SKILL.md" ]]; then
    found_de_slopify="$base/de-slopify"
    break
  fi
done

if [[ -n "$found_de_slopify" ]]; then
  check "de-slopify-installed" required pass "/de-slopify present at $found_de_slopify"
else
  check "de-slopify-installed" required fail "/de-slopify missing — run '$SCRIPT_DIR/install-companion-skills.sh' (uses jsm). Every customer-visible reply MUST pipe through /de-slopify."
fi

# Run a non-mutating inventory pass for the optional companions.
if [[ -x "$SCRIPT_DIR/check-companion-skills.sh" ]]; then
  inv_dir="$(mktemp -d)"
  if "$SCRIPT_DIR/check-companion-skills.sh" "$inv_dir" >/dev/null 2>&1 \
       && [[ -f "$inv_dir/skill_inventory.json" ]]; then
    # grep -c counts matches (returns 0 with count 0 when no match), avoiding
    # both the trailing-whitespace pitfall of `wc -l` and pipefail noise.
    optional_missing=$(grep -cE '"name": "[^"]+", "status": "missing", "requirement": "optional"' \
                          "$inv_dir/skill_inventory.json" || echo 0)
    if [[ "$optional_missing" -eq 0 ]]; then
      check "companion-skills" info pass "All optional companion skills installed"
    else
      check "companion-skills" info warn "${optional_missing} optional companion skill(s) missing — run install-companion-skills.sh"
    fi
  fi
  rm -rf "$inv_dir"
fi

# ---- emit report ----

failed_required=0
failed_optional=0
for i in "${!NAMES[@]}"; do
  if [[ "${STATUSES[$i]}" != "pass" ]]; then
    if [[ "${SEVERITIES[$i]}" == "required" ]]; then
      failed_required=$((failed_required + 1))
    else
      failed_optional=$((failed_optional + 1))
    fi
  fi
done
overall_ok=true
if [[ $failed_required -gt 0 || ( $STRICT -eq 1 && $failed_optional -gt 0 ) ]]; then
  overall_ok=false
fi

if [[ $JSON -eq 1 ]]; then
  printf '{\n  "ok": %s,\n  "profile": "%s",\n  "checks": [\n' "$overall_ok" "$PROFILE"
  for i in "${!NAMES[@]}"; do
    sep=$([[ $i -eq $((${#NAMES[@]} - 1)) ]] && echo '' || echo ',')
    # Escape double quotes in messages.
    msg_escaped=${MESSAGES[$i]//\"/\\\"}
    printf '    {"name":"%s","severity":"%s","status":"%s","message":"%s"}%s\n' \
      "${NAMES[$i]}" "${SEVERITIES[$i]}" "${STATUSES[$i]}" "$msg_escaped" "$sep"
  done
  printf '  ]\n}\n'
else
  echo "── ticketing-system doctor ($PROFILE) ───────────────────"
  for i in "${!NAMES[@]}"; do
    case "${STATUSES[$i]}" in
      pass) icon="✅" ;;
      warn) icon="⚠️ " ;;
      fail) icon="❌" ;;
      *)    icon="? " ;;
    esac
    printf "%s [%s] %-26s %s\n" "$icon" "${SEVERITIES[$i]:0:3}" "${NAMES[$i]}" "${MESSAGES[$i]}"
  done
  echo "─────────────────────────────────────────────────────────"
  if [[ $failed_required -eq 0 ]]; then
    if [[ $failed_optional -gt 0 && $STRICT -eq 1 ]]; then
      echo "FAIL (strict mode): $failed_optional optional checks failed"
    else
      echo "OK — host project meets the prerequisites this skill assumes."
    fi
  else
    echo "FAIL: $failed_required required check(s) failed. Fix before running EXACT PROMPTS."
  fi
fi

if [[ $failed_required -gt 0 ]]; then exit 1; fi
if [[ $STRICT -eq 1 && $failed_optional -gt 0 ]]; then exit 1; fi
exit 0
