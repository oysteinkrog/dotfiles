#!/usr/bin/env bash
# maintain.sh — orchestrator for Phase 3 ongoing maintenance.
#
# Usage:
#   ./maintain.sh <stage> [options]
#
# Stages:
#   health               Run live health probes
#   update-os            Apply OS security updates
#   update-mattermost    Upgrade Mattermost to MATTERMOST_TARGET_VERSION
#   backup               Take a pg_dump and upload off-site
#   db-health            Postgres health snapshot
#   restore-drill        Restore the latest backup into SCRATCH_DB_URL
#   schedule-reboot      Schedule a reboot in the next off-hours window
#   rotate-credentials   Rotate PAT / SSH / offsite / etc. (pass --scope <name>)
#   disaster-recovery    Open the DR playbook (manual stage)
#   weekly-sweep         Combo: health + update-os + backup + db-health
#
# Exit non-zero on any red/fail. Each stage writes timestamped reports to
# ${PHASE3_WORKSPACE_ROOT}/reports/ plus a latest-<stage>.json sibling copy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${PHASE3_CONFIG:-${SCRIPT_DIR}/config.env}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
    echo "ERROR: config.env not found at ${CONFIG_PATH}" >&2
    echo "Copy config.env.example to config.env and fill in values." >&2
    exit 2
fi

# shellcheck source=/dev/null
set -a
source "${CONFIG_PATH}"
set +a

: "${WORKSPACE_NAME:?WORKSPACE_NAME is required in config.env}"
: "${PHASE3_WORKSPACE_ROOT:=./workdir-phase3}"

mkdir -p "${PHASE3_WORKSPACE_ROOT}/reports"

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { log "FATAL: $*"; exit 1; }

STAGE="${1:-}"
shift || true

if [[ -z "${STAGE}" ]]; then
    cat <<'USAGE' >&2
Usage: ./maintain.sh <stage>

Stages:
  health               Live health probes
  update-os            OS security updates
  update-mattermost    Mattermost version upgrade
  backup               pg_dump + off-site upload
  db-health            Postgres health snapshot
  restore-drill        Restore latest backup into SCRATCH_DB_URL
  schedule-reboot      Reboot in next off-hours window
  rotate-credentials   Rotate credentials (pass --scope <name>)
  disaster-recovery    Open DR playbook (manual)
  weekly-sweep         Combo: health + update-os + backup + db-health
USAGE
    exit 2
fi

TIMESTAMP="$(date -u +'%Y%m%dT%H%M%SZ')"
REPORTS_DIR="${PHASE3_WORKSPACE_ROOT}/reports"

save_latest() {
    # $1 = stage name, $2 = path to timestamped JSON; symlinks latest-<stage>.json.
    local stage_name="$1"
    local timestamped_path="$2"
    local latest_path="${REPORTS_DIR}/latest-${stage_name}.json"
    # Use a relative symlink to avoid breaking when the workdir moves.
    local rel
    rel="$(basename "${timestamped_path}")"
    ln -sfn "${rel}" "${latest_path}"
}

run_stage_script() {
    # $1 = stage name, $2 = script filename under scripts/, $3... = passthrough args
    local stage_name="$1"
    local script_name="$2"
    local script_path="${SCRIPT_DIR}/scripts/${script_name}"
    shift 2

    [[ -x "${script_path}" ]] || die "${script_name} is not executable"

    local out_json="${REPORTS_DIR}/${stage_name}-${TIMESTAMP}.json"

    log "Running ${stage_name} stage"
    # Capture exit code without triggering errexit so save_latest runs even on failure.
    local rc=0
    CONFIG_PATH="${CONFIG_PATH}" \
    PHASE3_STAGE_TIMESTAMP="${TIMESTAMP}" \
    PHASE3_STAGE_OUT_JSON="${out_json}" \
    "${script_path}" "$@" || rc=$?

    if [[ -f "${out_json}" ]]; then
        save_latest "${stage_name}" "${out_json}"
        log "Wrote ${out_json} (latest-${stage_name}.json -> same)"
    fi

    return "${rc}"
}

case "${STAGE}" in
    health)
        run_stage_script health health-check.sh "$@"
        ;;
    update-os)
        run_stage_script update-os os-update.sh "$@"
        ;;
    update-mattermost)
        run_stage_script update-mattermost mattermost-upgrade.sh "$@"
        ;;
    backup)
        run_stage_script backup db-backup.sh "$@"
        ;;
    db-health)
        run_stage_script db-health db-health.sh "$@"
        ;;
    restore-drill)
        run_stage_script restore-drill restore-drill.sh "$@"
        ;;
    schedule-reboot)
        run_stage_script schedule-reboot schedule-reboot.sh "$@"
        ;;
    rotate-credentials)
        run_stage_script rotate-credentials rotate-credentials.sh "$@"
        ;;
    disaster-recovery)
        DR_PATH="${SCRIPT_DIR}/references/DISASTER-RECOVERY.md"
        [[ -f "${DR_PATH}" ]] || die "DR playbook missing at ${DR_PATH}"
        cat "${DR_PATH}"
        log "Opened disaster-recovery playbook (this stage is manual)"
        ;;
    weekly-sweep)
        log "Starting weekly-sweep: health -> update-os -> backup -> db-health"
        run_stage_script health health-check.sh || die "health failed, aborting sweep"
        run_stage_script update-os os-update.sh || die "update-os failed, aborting sweep"
        run_stage_script backup db-backup.sh || die "backup failed, aborting sweep"
        run_stage_script db-health db-health.sh || die "db-health failed, aborting sweep"
        log "weekly-sweep complete"
        ;;
    *)
        die "Unknown stage: ${STAGE}. Run ./maintain.sh (no arg) for usage."
        ;;
esac

log "Stage ${STAGE} complete"
