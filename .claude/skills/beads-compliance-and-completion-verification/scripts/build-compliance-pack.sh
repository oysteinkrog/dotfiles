#!/usr/bin/env bash
# build-compliance-pack.sh — Bundle an audit pass into a regulator-ready zip.
#
# Usage:
#   build-compliance-pack.sh <audit-dir> <pass-utc> <framework>
#     framework: soc2 | hipaa | pci | iso27001 | generic
#
# Output: <project>__compliance__<framework>__<UTC>.zip in $OUT_DIR (default cwd).
# Optional env: COMPLIANCE_GPG_KEY=<key-id> to GPG-sign the manifest.
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

AUDIT_DIR="${1:?audit dir}"
PASS_UTC="${2:?pass UTC}"
FRAMEWORK="${3:-generic}"
OUT_DIR="${OUT_DIR:-$PWD}"

case "$FRAMEWORK" in
  soc2|hipaa|pci|iso27001|generic) ;;
  *)
    echo "ERROR: framework must be one of: soc2, hipaa, pci, iso27001, generic" >&2
    exit 3
    ;;
esac

if [[ ! "$PASS_UTC" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "ERROR: pass UTC must be a single safe path segment (allowed: A-Z a-z 0-9 . _ : -)" >&2
  exit 3
fi

artifact_tree_sha256() {
  local root="$1" rel_path="$2"
  (
    cd "$root"
    find "$rel_path" -type f -print0 \
      | sort -z \
      | xargs -0 sha256sum \
      | sha256sum \
      | awk '{print $1}'
  )
}

PASS_DIR="$AUDIT_DIR/passes/$PASS_UTC"
[ -d "$PASS_DIR" ] || { echo "ERROR: pass not found: $PASS_DIR" >&2; exit 2; }

if SYMLINK_PATH="$(find "$AUDIT_DIR" -type l -print -quit 2>/dev/null)" && [ -n "$SYMLINK_PATH" ]; then
  echo "ERROR: audit dir contains symlink: $SYMLINK_PATH" >&2
  echo "       Refusing to build a compliance pack that could dereference files outside the audit tree." >&2
  exit 3
fi

PROJECT_NAME=$(basename "$(jq -r .project_path "$AUDIT_DIR/manifest.json")")
PACK_NAME="${PROJECT_NAME}__compliance__${FRAMEWORK}__${PASS_UTC}"
# `mktemp -d` makes a staging parent directory whose entire subtree (including
# PACK_NAME and the copied audit-dir) we own. Keep it after the zip is written:
# this repo's no-deletion policy forbids agent cleanup, and the staging tree is
# useful when auditing a failed or disputed evidence pack.
PACK_PARENT="$(mktemp -d)"
PACK_DIR="${PACK_PARENT}/${PACK_NAME}"
mkdir -p "$PACK_DIR/audit_dir"

# 1. Copy audit dir. Symlinks are rejected above, so this copies only ordinary
# audit artifacts without following attacker-controlled links outside the tree.
cp -R "$AUDIT_DIR"/. "$PACK_DIR/audit_dir/"

# 2. Generate exec README
cat > "$PACK_DIR/README.md" <<EOF
# Compliance Evidence Pack — ${PROJECT_NAME}
- **Framework:** ${FRAMEWORK^^}
- **Pass attested:** ${PASS_UTC}
- **Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Generator:** beads-compliance-and-completion-verification skill v1.0.0

## What this pack proves

This pack contains the verification artifacts for $(jq '.bead_counts.closed_issues // 0' "$AUDIT_DIR/manifest.json") closed work items in the project, audited with deterministic rubric (SHA256 \`$(jq -r .rubric_sha256 "$AUDIT_DIR/manifest.json")\`).

For each closed work item, the pack includes:
- The work item's specification (spec.json).
- File:line evidence of the implementation (evidence.json).
- Re-executed test/build/check outputs (compliance.json + raw/ logs).
- Anti-theater scan results (theater.json).
- Coverage / depth measurements (test_depth.json).
- A signed scorecard (scorecard.md) attributing a 0–1000 completion score.

## Verification

To independently verify this pack:

\`\`\`bash
# 1. Verify GPG signature
gpg --verify signature.asc manifest.json

# 2. Re-compute artifact tree SHA
find audit_dir/passes/${PASS_UTC} -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum
# Compare to manifest.json#artifact_tree_sha256

# 3. Re-derive 5 random scorecards from evidence packs
# (See verification_instructions.md)
\`\`\`

## Headline

$(awk '/Executive summary/,/^## /' "$PASS_DIR/REPORT.md" | head -10)
EOF

# 3. Generate controls mapping (per framework)
case "$FRAMEWORK" in
  soc2)
    cat > "$PACK_DIR/controls_mapping.md" <<EOF
# SOC2 Controls Mapping

| Control | Audit dimension | Evidence |
|---------|-----------------|----------|
| CC8.1 (Change management) | Implementation completeness vs. spec | scorecard.md dimension 1 |
| CC7.2 (Test execution) | Required tests present and meaningfully passing | scorecard.md dimension 2 + raw/ test logs |
| CC4.1 (Monitoring) | Documentation, telemetry, migrations as required | scorecard.md dimension 5 |
| CC9.1 (Risk mitigation) | Anti-theater | scorecard.md dimension 3 + theater.json |
EOF
    ;;
  hipaa)
    cat > "$PACK_DIR/controls_mapping.md" <<EOF
# HIPAA Safeguards Mapping

| Safeguard | Audit dimension | Evidence |
|-----------|-----------------|----------|
| §164.308(a)(1) (Security management process) | Audit's existence and execution cadence | manifest.json#pass_started_at across passes |
| §164.312(c)(1) (Integrity controls) | Anti-theater + cross-bead consistency | dimensions 3 + 6 |
EOF
    ;;
  pci)
    cat > "$PACK_DIR/controls_mapping.md" <<EOF
# PCI-DSS Requirements Mapping

| Requirement | Audit dimension | Evidence |
|-------------|-----------------|----------|
| 6.3 (Security in development) | All dimensions | scorecards |
| 6.5 (Common coding vulnerabilities) | Anti-theater + security-bead playbook | dimension 3 + per-bead audits of security label |
| 11.3 (Penetration testing) | Test depth (fuzz / property) | dimension 4 |
EOF
    ;;
  iso27001)
    cat > "$PACK_DIR/controls_mapping.md" <<EOF
# ISO 27001 Annex A Mapping

| Control | Audit dimension | Evidence |
|---------|-----------------|----------|
| A.14.2.1 (Secure development policy) | Audit's existence + rubric | rubric.md, README.md |
| A.14.2.5 (Secure system engineering) | All dimensions | scorecards |
| A.14.2.8 (System security testing) | Test depth | dimension 4 |
EOF
    ;;
  *)
    cat > "$PACK_DIR/controls_mapping.md" <<EOF
# Generic Controls Mapping

The 6 audit dimensions can be mapped to any framework's "did the implementation
match the requirement" controls. See SOC2 / HIPAA / PCI / ISO27001 examples
in this skill's documentation for framework-specific mappings.
EOF
    ;;
esac

# 4. Verification instructions
cat > "$PACK_DIR/verification_instructions.md" <<EOF
# How to Independently Verify This Pack

## Cryptographic verification

\`\`\`bash
gpg --verify signature.asc manifest.json
# Expected: "Good signature from ..."
\`\`\`

## Artifact integrity

\`\`\`bash
EXPECTED=\$(jq -r .artifact_tree_sha256 manifest.json)
ACTUAL=\$(find audit_dir/passes/${PASS_UTC} -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print \$1}')
[ "\$EXPECTED" = "\$ACTUAL" ] && echo "OK" || echo "MISMATCH"
\`\`\`

## Re-derive a scorecard score

Pick any bead's scorecard. The score is computed deterministically from:
- spec.json
- evidence.json
- compliance.json
- theater.json
- test_depth.json
- The rubric in audit_dir/rubric.md

Apply the rubric formulas (in audit_dir/rubric.md). The result must match the
score line in the scorecard.

## Spot-check evidence existence

Pick any scorecard's citation (e.g., "src/parser.rs:312"). The cited file:line
must exist in the project at the SHA recorded in audit_dir/manifest.json#project_git_sha_at_pass_start.

## Re-run a Phase 4 check

The raw/ directory under each bead contains the actual test runner output. To
re-derive: check out the project at the recorded SHA, run the same command,
compare output (modulo timestamps).
EOF

# 5. Compute pack manifest
ARTIFACT_SHA="$(artifact_tree_sha256 "$PACK_DIR" "audit_dir/passes/$PASS_UTC")"

cat > "$PACK_DIR/manifest.json" <<EOF
{
  "pack_name": "${PACK_NAME}",
  "framework": "${FRAMEWORK}",
  "project_name": "${PROJECT_NAME}",
  "pass_utc": "${PASS_UTC}",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "generator": "beads-compliance-and-completion-verification v1.0.0",
  "artifact_tree_sha256": "${ARTIFACT_SHA}",
  "skill_version": "1.0.0",
  "rubric_sha256": "$(jq -r .rubric_sha256 "$AUDIT_DIR/manifest.json")"
}
EOF

# 6. Sign manifest (if GPG key available)
if command -v gpg >/dev/null && [ -n "${COMPLIANCE_GPG_KEY:-}" ]; then
  gpg --armor --detach-sign --local-user "$COMPLIANCE_GPG_KEY" \
      --output "$PACK_DIR/signature.asc" "$PACK_DIR/manifest.json"
  echo "Signed with $COMPLIANCE_GPG_KEY" >&2
else
  echo "WARNING: no GPG signing (set COMPLIANCE_GPG_KEY)" >&2
fi

# 7. Zip
ZIP_OUT="$OUT_DIR/${PACK_NAME}.zip"
cd "$(dirname "$PACK_DIR")"
zip -qr "$ZIP_OUT" "$PACK_NAME"
echo "Pack ready: $ZIP_OUT" >&2
echo "Staging tree retained: $PACK_PARENT" >&2
echo "$ZIP_OUT"
