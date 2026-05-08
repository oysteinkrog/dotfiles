# Phase 1 Operating Model

This skill is strongest when it behaves like a migration factory, not a one-off script run.

## Mission Boundary

Phase 1 owns:
- acquisition of authoritative Slack artifacts
- enrichment of missing data
- transformation into Mattermost bulk-import artifacts
- patching for non-native Slack objects
- verification, manifests, and handoff evidence

Phase 1 does **not** own:
- provisioning the production Mattermost server
- final import execution into production
- DNS cutover, SMTP, user activation, or post-cutover ops

Those belong to `slack-migration-to-mattermost-phase-2-setup-and-import`.

## Tool Roles

| Tool | Primary Role | Never Use It For |
|------|--------------|------------------|
| Official Slack export UI | Source-of-truth export ZIP and audit CSV | Attachment recovery |
| `slack-advanced-exporter` | Add emails and file binaries to official export | Whole-workspace message extraction |
| Slack API | Enrichment, verification, emoji export, direct file recovery | Primary org-wide history acquisition |
| `slackdump` | Fallback extraction, supplement, gap-fill, Pro/Free path | Pretending you have org-wide visibility |
| Slack MCP | Exploration, verification, debugging | Primary archival pipeline |
| `mmetl` | Slack ZIP -> Mattermost JSONL transform | Preserving non-native Slack objects by itself |
| `mmctl` | Validate import ZIP, upload/process import in staging/Phase 2 | Replacing verification |

## Default Strategy

1. Prefer the official export ZIP when Business+ or Enterprise permissions allow it.
2. Add the channel-audit CSV in the same acquisition pass.
3. Enrich the official ZIP before transform.
4. Use `slackdump` only where the official export is unavailable or incomplete.
5. Preserve anything that cannot become native Mattermost data as explicit sidecars.

## Phase Gates

| Gate | Required Evidence |
|------|-------------------|
| Acquisition complete | raw ZIP, channel-audit CSV, manifest with hashes |
| Enrichment complete | enriched ZIP, emoji manifest, attachment gap report |
| Transform complete | `mattermost_import.jsonl`, attachment directory, transform log |
| Patch complete | sidecar channels/posts injected, package manifest updated |
| Verification complete | counts, sampling notes, unresolved gaps, handoff summary |

## Anti-Goals

- Do not replace the official export with a crawler when the official export is available.
- Do not overwrite intermediate artifacts in place without keeping hashes and prior outputs.
- Do not claim completeness where Slack Connect or plan-tier boundaries make completeness impossible.
- Do not ship a final ZIP without a written gap report.

## Completion Definition

Phase 1 is complete only when all of the following are true:
- the final import ZIP validates structurally
- the evidence bundle explains where each artifact came from
- unresolved limitations are explicit
- Phase 2 can import without guessing what was preserved, omitted, or approximated
