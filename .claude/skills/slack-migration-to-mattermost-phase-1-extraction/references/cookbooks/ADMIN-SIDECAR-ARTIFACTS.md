# Admin Sidecar Artifacts

Not everything useful for migration lives inside the main Slack export ZIP. This cookbook covers the extra admin artifacts worth capturing and preserving beside the main export.

## Why These Matter

- They improve reconciliation and identity matching.
- They preserve operational context that Mattermost will not recreate.
- They make the migration more auditable for admins after cutover.

## 1. Channel Audit CSV

Slack's export UI exposes a **channel audit report** for migration planning on Business+ and Enterprise exports. Capture it during the same run as the main export ZIP and store it under `artifacts/raw/`.

Use it for:
- channel count reconciliation
- private/public/shared channel classification
- member-count spot checks
- identifying externally shared channels and high-risk Slack Connect gaps

## 2. Full Member List CSV

Slack lets owners and admins export a full member list CSV on all plans.

Capture it because it helps with:
- username/email reconciliation
- deactivated-user audit trails
- guest/user-role review
- identifying email mismatches before `mmetl`

Store it as:

```text
artifacts/raw/member-list-YYYY-MM-DD.csv
```

## 3. Workflow Builder JSON Exports

Slack supports exporting individual workflows as JSON files, but there is an important limitation:

- workflows containing **custom steps**
- **custom triggers**
- or **connector steps**

cannot currently be exported.

That means the migration operator should:
1. export every supported workflow JSON that matters
2. create manual notes for unsupported workflows
3. treat workflows as sidecar operational artifacts, not native import content

Store them as:

```text
artifacts/enriched/workflows/
├── onboarding-request.json
├── incident-intake.json
└── WORKFLOW-NOTES.md
```

## 4. Admin Audit Artifacts

Preserve these when available:
- `integration_logs.json`
- `content_flags.json`
- Enterprise audit-log CSV extracts
- workflow notes
- change logs for channels or permissions relevant to migration

These do not become native Mattermost collaboration objects, but they are valuable post-migration reference data.

## Preservation Pattern

- keep raw admin exports untouched
- hash them into the stage manifest
- mention them in the handoff report
- if they are not importable, route them into `slack-export-admin` sidecar archive posts

## Operator Checklist

- [ ] Channel audit CSV captured
- [ ] Member list CSV captured
- [ ] Supported workflow JSON exports captured
- [ ] Unsupported workflows noted in Markdown
- [ ] Admin audit artifacts preserved
- [ ] All sidecars added to manifests and handoff summary
