# COMPLIANCE-EVIDENCE-PACK.md — Bundle An Audit Pass For Regulators

<!-- TOC: When to bundle | Pack contents | Bundle script | Signed delivery | Per-framework hints (SOC2/HIPAA/PCI/ISO27001) | What auditors actually read -->

> External auditors / regulators want a **single artifact** — usually a zip or tarball with a signed manifest — proving you did the work. The audit dir's `passes/<UTC>/` is already structured for this; we just need the bundling and signing.

---

## When to bundle

| Trigger | Frequency |
|---------|-----------|
| SOC2 Type II audit | Annually, plus quarterly evidence collection |
| HIPAA compliance review | Annually |
| PCI-DSS attestation | Annually |
| ISO 27001 certification / surveillance | Annually / triannually |
| Customer security questionnaire | Per request |
| Internal security review (board / audit committee) | Quarterly |
| Insurance underwriting | Per renewal |
| Acquisition due-diligence | Per event |

---

## Pack contents

A standard compliance evidence pack contains:

```
<project>__compliance_evidence__<UTC>.zip
├── README.md                    # 1-page exec summary for the auditor
├── audit_summary.pdf            # Polished version of REPORT.md (optional)
├── manifest.json                # Pack metadata: project, dates, signer, hashes
├── signature.asc                # GPG signature of manifest.json
├── verification_instructions.md # How to independently verify the pack
├── audit_dir/                   # Symbolic link OR copy of the audit dir
│   ├── manifest.json
│   ├── rubric.md
│   ├── REPORT.md
│   ├── synthesis.md
│   ├── remediation.md
│   ├── trends.md
│   └── passes/
│       └── <UTC>/               # The pass being attested
│           ├── ... (full evidence pack per bead)
├── controls_mapping.md          # Maps each audit dimension to compliance control
└── auditor_notes.md             # Any human notes for the external auditor
```

---

## Bundle script

`scripts/build-compliance-pack.sh`:

```bash
#!/usr/bin/env bash
# build-compliance-pack.sh — Bundle an audit pass into a regulator-ready zip.
#
# Usage:
#   build-compliance-pack.sh <audit-dir> <pass-utc> <framework>
#     framework: soc2 | hipaa | pci | iso27001 | generic
set -euo pipefail

AUDIT_DIR="${1:?audit dir}"
PASS_UTC="${2:?pass UTC}"
FRAMEWORK="${3:-generic}"
OUT_DIR="${OUT_DIR:-$PWD}"

PASS_DIR="$AUDIT_DIR/passes/$PASS_UTC"
[ -d "$PASS_DIR" ] || { echo "ERROR: pass not found: $PASS_DIR" >&2; exit 2; }

PROJECT_NAME=$(basename "$(jq -r .project_path "$AUDIT_DIR/manifest.json")")
PACK_NAME="${PROJECT_NAME}__compliance__${FRAMEWORK}__${PASS_UTC}"
PACK_DIR="$(mktemp -d)/${PACK_NAME}"
mkdir -p "$PACK_DIR/audit_dir"

# 1. Copy audit dir (symlinks resolved)
cp -rL "$AUDIT_DIR" "$PACK_DIR/audit_dir/"

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
find audit_dir/passes/${PASS_UTC} -type f | sort | xargs sha256sum | sha256sum
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
ACTUAL=\$(find audit_dir/passes/${PASS_UTC} -type f | sort | xargs sha256sum | sha256sum | awk '{print \$1}')
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
cd "$(dirname "$PACK_DIR")"
ARTIFACT_SHA=$(find "$PACK_NAME/audit_dir/passes/$PASS_UTC" -type f | sort | xargs sha256sum | sha256sum | awk '{print $1}')

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
echo "$ZIP_OUT"
```

Add to scripts/ and chmod +x.

---

## Per-framework hints

### SOC2

- Auditors care about **continuous monitoring**. Show them tripwire mode running daily.
- Map each audit dimension to a Trust Services Criteria.
- Show **change management evidence**: every false-closed → completion-debt → close → re-pass.

### HIPAA

- Focus on **integrity controls** (dimension 3 + 6).
- Show that PHI-handling beads (label `hipaa` or `phi`) have stricter thresholds.
- Maintain an audit log of who accessed the audit dir.

### PCI-DSS

- Focus on **secure development lifecycle** (all dimensions, all passes).
- Beads with label `pci` get 800+ threshold.
- Show **fuzz coverage** (dimension 4) for any input-handling code.

### ISO 27001

- Provide the audit dir as evidence of A.14 (System acquisition, development).
- Show **risk assessments** (synthesis.md cross-bead findings = risk identification).

---

## What auditors actually read

In a 1-hour external audit meeting, the external auditor will read:

1. **README.md** — 30 seconds.
2. **manifest.json** — 30 seconds.
3. **REPORT.md exec summary** — 1 minute.
4. **3-5 random scorecards** — 5 minutes (sample auditing).
5. **Verification command output** (run themselves) — 5 minutes.
6. **controls_mapping.md** — 1 minute.

The other artifacts are *available for deep-dive* but rarely consumed unless something looks wrong. So the bundling priority is: make the top 6 readable, polished, and mutually consistent.

---

## Don't include

| Exclude | Why |
|---------|-----|
| Raw test output containing secrets | Even though scrubbed at audit time, double-check pack |
| `.beads/*.db` (SQLite) | The JSONL export is sufficient and human-readable |
| Internal Slack messages / cass mining outputs | Not regulator-relevant; potential PII |
| Other projects' audit dirs | Scope to one project per pack |

---

## Storage and retention

| Framework | Retention |
|-----------|-----------|
| SOC2 | 5 years |
| HIPAA | 6 years |
| PCI-DSS | 1 year |
| ISO 27001 | 3 years |
| Internal | Per company policy (commonly 7 years) |

Store packs in immutable storage (S3 with object lock, Glacier deep archive). Attach the GPG signing key's fingerprint to the storage location's metadata.

---

## Worked example

```bash
# Quarterly SOC2 evidence collection
QUARTER=$(date -u +"%Y-Q$(( (10#$(date -u +%m) - 1) / 3 + 1 ))")
LATEST_PASS=$(ls -1d <audit-dir>/passes/*/ | sort | tail -1 | xargs basename)

COMPLIANCE_GPG_KEY=audit@example.com \
  ~/.claude/skills/.../scripts/build-compliance-pack.sh \
  <audit-dir> "$LATEST_PASS" soc2

# Output: <project>__compliance__soc2__<UTC>.zip

# Upload to immutable storage
aws s3 cp <project>__compliance__soc2__<UTC>.zip \
  s3://compliance-evidence-bucket/${QUARTER}/ \
  --object-lock-mode COMPLIANCE \
  --object-lock-retain-until-date "$(date -u -d '+5 years' --iso-8601=seconds)"
```

The pack is delivered to the SOC2 auditor via a secure file share or in-meeting USB.