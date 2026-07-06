#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "${script_dir}/.." && pwd)"
tmp_root="${PHASE1_SMOKE_ROOT:-}"
if [[ -z "${tmp_root}" ]]; then
  tmp_root="$(mktemp -d -t phase1-smoke-XXXXXX)"
else
  mkdir -p "${tmp_root}"
fi
artifact_root="${tmp_root}/artifacts"
raw_dir="${artifact_root}/raw"
enriched_dir="${artifact_root}/enriched"
import_dir="${artifact_root}/import-ready"
reports_dir="${artifact_root}/reports"

mkdir -p "${raw_dir}" "${enriched_dir}" "${import_dir}/data/bulk-export-attachments" "${reports_dir}"
mkdir -p "${import_dir}/data/emoji" "${enriched_dir}/emoji/images" "${enriched_dir}/sidecar-bundle/sidecars/canvases"

(
  cd "${skill_dir}/assets/fixtures/slack-export-sample"
  zip -qr "${raw_dir}/slack-export.zip" .
)
cp "${raw_dir}/slack-export.zip" "${enriched_dir}/slack-export.enriched.zip"
cp "${skill_dir}/assets/goldens/mattermost_import.example.jsonl" "${import_dir}/mattermost_import.jsonl"
printf '<html><body><h1>Canvas</h1></body></html>\n' > "${enriched_dir}/sidecar-bundle/sidecars/canvases/project-roadmap.html"
printf '{"aliases":{"party-parrot":"sample-parrot"}}\n' > "${enriched_dir}/emoji/emoji-aliases.json"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXWQAAAAASUVORK5CYII=' | base64 -d > "${enriched_dir}/emoji/images/sample-parrot.png"
python3 - <<PY
from pathlib import Path
import hashlib
import json

image_path = Path("${enriched_dir}/emoji/images/sample-parrot.png")
manifest = {
    "schema_version": 1,
    "workspace": "smoke-phase1",
    "custom_emoji": [
        {
            "name": "sample-parrot",
            "path": str(image_path.resolve()),
            "sha256": hashlib.sha256(image_path.read_bytes()).hexdigest(),
            "bytes": image_path.stat().st_size,
            "source_url": "https://example.test/sample-parrot.png",
        }
    ],
    "alias_count": 1,
    "warnings": [],
}
Path("${enriched_dir}/emoji/emoji-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

python3 "${script_dir}/build-artifact-manifest.py" \
  --workspace smoke-phase1 \
  --stage raw \
  --source fixture \
  --output "${raw_dir}/manifest.raw.json" \
  "${raw_dir}/slack-export.zip"

python3 "${script_dir}/extract-phase1-sidecars.py" \
  --workspace smoke-phase1 \
  --raw-archive "${raw_dir}/slack-export.zip" \
  --output-dir "${enriched_dir}/sidecar-bundle" \
  --metadata-out "${enriched_dir}/sidecar-bundle/sidecar-summary.json"

python3 "${script_dir}/build-artifact-manifest.py" \
  --workspace smoke-phase1 \
  --stage enriched \
  --source fixture \
  --output "${enriched_dir}/manifest.enriched.json" \
  "${enriched_dir}/slack-export.enriched.zip" "${enriched_dir}/sidecar-bundle/sidecar-summary.json" "${enriched_dir}/emoji/emoji-manifest.json" "${enriched_dir}/emoji/emoji-aliases.json"

python3 "${script_dir}/patch-phase1-import.py" \
  --workspace smoke-phase1 \
  --jsonl "${import_dir}/mattermost_import.jsonl" \
  --attachments-root "${import_dir}/data/bulk-export-attachments" \
  --emoji-assets-dir "${import_dir}/data/emoji" \
  --emoji-manifest "${enriched_dir}/emoji/emoji-manifest.json" \
  --emoji-aliases "${enriched_dir}/emoji/emoji-aliases.json" \
  --sidecar-dir "${enriched_dir}/sidecar-bundle/sidecars" \
  --summary-out "${reports_dir}/patch-summary.json"

python3 "${script_dir}/package-phase1-import.py" \
  --workspace smoke-phase1 \
  --jsonl "${import_dir}/mattermost_import.jsonl" \
  --output-zip "${import_dir}/mattermost-bulk-import.zip" \
  --manifest-out "${import_dir}/manifest.import-ready.json" \
  --summary-out "${reports_dir}/package-summary.json" \
  --attachments-dir "${import_dir}/data/bulk-export-attachments" \
  --emoji-asset-dir "${import_dir}/data/emoji" \
  --emoji-dir "${enriched_dir}/emoji"

python3 "${script_dir}/validate-phase1-artifacts.py" --root "${artifact_root}" --output-json "${reports_dir}/artifact-validation.json"
python3 "${script_dir}/validate-phase1-jsonl.py" "${import_dir}/mattermost_import.jsonl" --output-json "${reports_dir}/jsonl-validation.json"
python3 "${script_dir}/validate-enrichment-completeness.py" --archive "${enriched_dir}/slack-export.enriched.zip" --output-json "${reports_dir}/enrichment-report.json"
python3 "${script_dir}/reconcile-phase1-counts.py" \
  --raw-archive "${raw_dir}/slack-export.zip" \
  --enriched-archive "${enriched_dir}/slack-export.enriched.zip" \
  --jsonl "${import_dir}/mattermost_import.jsonl" \
  --output-json "${reports_dir}/reconciliation.json"
python3 "${script_dir}/export-integration-inventory.py" \
  --archive "${raw_dir}/slack-export.zip" \
  --output-json "${reports_dir}/integration-inventory.json" \
  --output-md "${reports_dir}/integration-inventory.md"
python3 "${script_dir}/build-migration-evidence-pack.py" \
  --workspace smoke-phase1 \
  --output "${reports_dir}/evidence-pack.json" \
  "${raw_dir}/manifest.raw.json" "${enriched_dir}/manifest.enriched.json" "${import_dir}/manifest.import-ready.json" "${reports_dir}"
if ! python3 "${script_dir}/scan-and-redact-migration-secrets.py" \
  --report-json "${reports_dir}/secret-scan.json" \
  --output-dir "${reports_dir}/redacted" \
  "${reports_dir}"; then
  true
fi
python3 "${script_dir}/generate-phase1-handoff.py" \
  --workspace smoke-phase1 \
  --output "${reports_dir}/handoff.md" \
  --json-output "${reports_dir}/handoff.json" \
  --final-zip "${import_dir}/mattermost-bulk-import.zip" \
  --jsonl "${import_dir}/mattermost_import.jsonl" \
  --manifest "${raw_dir}/manifest.raw.json" \
  --manifest "${enriched_dir}/manifest.enriched.json" \
  --manifest "${import_dir}/manifest.import-ready.json"
python3 "${script_dir}/generate-phase1-verification.py" \
  --workspace smoke-phase1 \
  --output-md "${reports_dir}/verification.md" \
  --artifact-report "${reports_dir}/artifact-validation.json" \
  --jsonl-report "${reports_dir}/jsonl-validation.json" \
  --enrichment-report "${reports_dir}/enrichment-report.json" \
  --reconciliation-report "${reports_dir}/reconciliation.json" \
  --integration-report "${reports_dir}/integration-inventory.json" \
  --secret-scan-report "${reports_dir}/secret-scan.json" \
  --handoff-json "${reports_dir}/handoff.json"
python3 "${script_dir}/generate-unresolved-gaps.py" \
  --workspace smoke-phase1 \
  --output-md "${reports_dir}/unresolved-gaps.md" \
  --handoff-json "${reports_dir}/handoff.json" \
  --enrichment-report "${reports_dir}/enrichment-report.json" \
  --reconciliation-report "${reports_dir}/reconciliation.json" \
  --artifact-report "${reports_dir}/artifact-validation.json"
python3 "${script_dir}/split-phase1-import.py" \
  --input-zip "${import_dir}/mattermost-bulk-import.zip" \
  --output-dir "${import_dir}/batches" \
  --report-json "${reports_dir}/split-report.json"

echo "phase1 smoke test artifacts: ${tmp_root}"
