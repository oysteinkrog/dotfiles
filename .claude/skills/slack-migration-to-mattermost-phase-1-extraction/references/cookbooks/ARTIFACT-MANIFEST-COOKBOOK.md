# Artifact Manifest Cookbook

Use manifests to make every stage auditable.

## Quick Hash Commands

```bash
sha256sum artifacts/raw/slack-export.zip
sha256sum artifacts/raw/channel-audit.csv
```

## Minimal Shell Helper

```bash
file_size() {
  stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1"
}

artifact_json() {
  local path="$1"
  local source="$2"
  jq -n \
    --arg path "$path" \
    --arg source "$source" \
    --arg sha256 "$(sha256sum "$path" | awk '{print $1}')" \
    --arg bytes "$(file_size "$path")" \
    '{path:$path,source:$source,sha256:$sha256,bytes:($bytes|tonumber)}'
}
```

## Example Manifest Build

```bash
jq -n \
  --arg created_at "$(date -u +%FT%TZ)" \
  --arg workspace "acme-slack" \
  --argjson raw_zip "$(artifact_json artifacts/raw/slack-export.zip official-slack-export-ui)" \
  --argjson audit_csv "$(artifact_json artifacts/raw/channel-audit.csv official-slack-admin-csv)" \
  '{created_at:$created_at,workspace:$workspace,artifacts:[$raw_zip,$audit_csv],known_gaps:[]}' \
  > artifacts/raw/manifest.raw.json
```

## Manifest Discipline

- new artifact -> new hash
- new hash -> new manifest update
- every report references the manifest it was derived from
- never edit the manifest silently after handoff
