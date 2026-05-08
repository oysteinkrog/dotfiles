#!/usr/bin/env bash
# rotate-credentials.sh — agent-assisted credential rotation.
#
# This script is mostly a wrapper that captures audit trail; the actual
# rotation is manual (operator UI clicks in provider consoles).
#
# Usage:
#   ./rotate-credentials.sh --scope pat
#   ./rotate-credentials.sh --scope ssh
#   ./rotate-credentials.sh --scope postgres
#   ./rotate-credentials.sh --scope offsite
#   ./rotate-credentials.sh --scope cloudflare
#   ./rotate-credentials.sh --scope postmark

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${CONFIG_PATH:-${SCRIPT_DIR}/../config.env}"
set -a; source "${CONFIG_PATH}"; set +a

SCOPE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope) SCOPE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

[[ -n "${SCOPE}" ]] || { echo "Usage: $0 --scope pat|ssh|postgres|offsite|cloudflare|postmark"; exit 2; }

: "${ROLLBACK_OWNER:?ROLLBACK_OWNER required for credential rotation}"

OUT_JSON="${PHASE3_STAGE_OUT_JSON:-${SCRIPT_DIR}/../workdir-phase3/reports/rotate-credentials-$(date -u +%Y%m%dT%H%M%SZ).json}"
AUDIT_PATH="${SCRIPT_DIR}/../workdir-phase3/rotate-credentials-audit.json"
mkdir -p "$(dirname "${OUT_JSON}")" "$(dirname "${AUDIT_PATH}")"
[[ -f "${AUDIT_PATH}" ]] || printf '{"rotations":[]}\n' > "${AUDIT_PATH}"

echo "=== Credential rotation: ${SCOPE} ==="
echo "ROLLBACK_OWNER: ${ROLLBACK_OWNER}"
echo

case "${SCOPE}" in
    pat)
        cat <<'EOF'
Procedure:
1. Log into Mattermost System Console as current admin.
2. Profile (top-right) → Security → Personal Access Tokens → Create new.
3. Give it a name like "phase3-<YYYY-QQ>".
4. Copy the new token (shown once).
5. Test: curl -H "Authorization: Bearer NEW_TOKEN" MATTERMOST_URL/api/v4/users/me
   Expect HTTP 200.
EOF
        read -r -p "Paste the NEW PAT (will not echo): " -s NEW_PAT; echo
        [[ -n "${NEW_PAT}" ]] || { echo "No token; aborting"; exit 1; }

        # Test
        http_code=$(curl -fsS --max-time 10 -o /dev/null -w '%{http_code}' \
            -H "Authorization: Bearer ${NEW_PAT}" \
            "${MATTERMOST_URL}/api/v4/users/me" || echo "000")
        if [[ "${http_code}" != "200" ]]; then
            echo "New PAT failed validation (HTTP ${http_code}); aborting"
            exit 1
        fi

        # Update config.env atomically
        cp "${CONFIG_PATH}" "${CONFIG_PATH}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
        sed -i.sedbak "s|^MATTERMOST_ADMIN_TOKEN=.*|MATTERMOST_ADMIN_TOKEN=\"${NEW_PAT}\"|" "${CONFIG_PATH}"
        rm -f "${CONFIG_PATH}.sedbak"
        echo "config.env updated."

        echo
        echo "Next: revoke the OLD PAT in System Console → Security → Personal Access Tokens."
        read -r -p "Have you revoked the old PAT? [y/N] " confirm
        [[ "${confirm}" == "y" ]] || { echo "Rotation incomplete; old PAT still valid"; exit 1; }
        ;;

    ssh)
        cat <<'EOF'
Procedure:
1. ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_new -C "phase3-$(date +%Y)"
2. ssh-copy-id -i ~/.ssh/id_ed25519_new.pub deploy@TARGET_HOST
   (or manually append to ~deploy/.ssh/authorized_keys)
3. Test: ssh -i ~/.ssh/id_ed25519_new deploy@TARGET_HOST true
4. Update TARGET_SSH_KEY in config.env to point at the new key.
5. ssh deploy@TARGET_HOST, remove the old pubkey from authorized_keys.
6. Verify by attempting to ssh with OLD key — should fail.
EOF
        echo "This is a manual procedure; record completion when done:"
        read -r -p "Have you completed all 6 steps and verified old key is revoked? [y/N] " confirm
        [[ "${confirm}" == "y" ]] || { echo "Rotation incomplete"; exit 1; }
        ;;

    postgres|offsite|cloudflare|postmark)
        cat <<EOF
Manual rotation for ${SCOPE} — see references/playbooks/TOKEN-HANDLING.md.
Update the relevant variable in config.env when done.
EOF
        read -r -p "Have you completed the rotation and verified the new credential works? [y/N] " confirm
        [[ "${confirm}" == "y" ]] || { echo "Rotation incomplete"; exit 1; }
        ;;

    *)
        echo "Unknown scope: ${SCOPE}"
        exit 2
        ;;
esac

# Record audit entry
TS_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp=$(mktemp)
jq --arg scope "${SCOPE}" \
   --arg ts "${TS_ISO}" \
   --arg owner "${ROLLBACK_OWNER}" \
   '.rotations += [{"scope":$scope, "rotated_at":$ts, "owner":$owner}]' \
   "${AUDIT_PATH}" > "${tmp}" && mv "${tmp}" "${AUDIT_PATH}"

{
    printf '{\n'
    printf '  "generated_at": "%s",\n' "${TS_ISO}"
    printf '  "scope": "%s",\n' "${SCOPE}"
    printf '  "owner": "%s",\n' "${ROLLBACK_OWNER}"
    printf '  "status": "success"\n'
    printf '}\n'
} > "${OUT_JSON}"

echo
echo "Rotation recorded in ${AUDIT_PATH}"
echo "JSON: ${OUT_JSON}"
