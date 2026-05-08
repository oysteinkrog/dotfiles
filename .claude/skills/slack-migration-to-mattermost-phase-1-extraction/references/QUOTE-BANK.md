# Phase 1 Quote Bank

Load-bearing rules in this skill trace back to specific anchors in the source
research doc and in Mattermost / Slack documentation. When a rule here gets
questioned, check the anchor; if the anchor is stale, update this bank and the
affected references in the same commit.

Anchors are given as `[tag] short-title :: source :: gist`. Operators in
[OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) and rules in [SKILL.md](../SKILL.md)
cite these tags.

---

## Export Scope & Plan Tier

- `[Q-TIER-001]` *Free/Pro exports are public-only* :: source doc §"Exporting Everything from Slack" :: "Admins of Free and Pro Slack accounts can only export data from public workspace channels. Business+ and Enterprise Grid users can export a complete copy of public, private, and direct messages."
- `[Q-TIER-002]` *Pro workspaces can apply for full export under limited legal circumstances* :: source doc §"Important caveats" :: "Under limited circumstances, Workspace Owners may contact Slack and apply to export content from all channels and conversations. Slack will reject applications unless Workspace Owners show valid legal process, consent of members, or a requirement under applicable laws."
- `[Q-TIER-003]` *Official export = links, not files* :: source doc §"Important caveats" :: "Data exports include links to files, but not the files themselves. You'll need to download those separately before they expire."

## Acquisition & Slackdump

- `[Q-ACQ-001]` *Slackdump sees everything the authenticated account sees* :: source doc §"Alternative approach — Slackdump" :: "Slackdump can export all channels and conversations you have access to, including attachments, and it has an export format specifically suited for Mattermost import."
- `[Q-ACQ-002]` *No public API to trigger workspace exports* :: inferred from Slack docs (no published endpoint); cross-referenced in [BROWSER-AUTOMATION.md](BROWSER-AUTOMATION.md).
- `[Q-ACQ-003]` *Channel audit CSV is a first-class artifact* :: `specs/OPERATING-MODEL.md` :: counts reconciliation fails without it.

## Enrichment & Transform

- `[Q-ENR-001]` *Enrich before transform* :: Mattermost migration docs :: "Data exports include links to files, but not the files themselves" → `slack-advanced-exporter fetch-emails` then `fetch-attachments` is required before `mmetl`.
- `[Q-ENR-002]` *Fetch order matters* :: `cookbooks/SLACK-ADVANCED-EXPORTER-COOKBOOK.md` :: emails before attachments; mutating a ZIP in place is wasteful and breaks evidence.
- `[Q-XFORM-001]` *mmetl is Linux/macOS only* :: Mattermost migration docs :: running on Windows corrupts the JSONL.
- `[Q-XFORM-002]` *MaxPostSize default 4000 truncates Slack posts* :: source doc §"Practical tips from people who've done it" :: Slack allows 40 000 chars; `MaxPostSize=16383` is the canonical patch.

## Packaging & Handoff

- `[Q-PKG-001]` *Mattermost import is idempotent* :: source doc §"Practical tips" :: "Mattermost works well with multiple smaller imports as long as usernames and emails don't change between imports." → re-imports don't duplicate, which is why baseline+delta works.
- `[Q-PKG-002]` *Per-year batches for >10 GB* :: source doc §"For large exports" :: "For large exports, break them into smaller date ranges (e.g., one year per file) rather than importing everything at once."
- `[Q-HAND-001]` *Sidecars must be named, not implied* :: `specs/CROSS-PHASE-INTAKE-CONTRACT.md` :: `sidecar_channels` array must list each one; Phase 2's intake validator will reject implicit entries.
- `[Q-HAND-002]` *Final ZIP sha256 is non-optional* :: `specs/HANDOFF-CONTRACT.md` :: Phase 2 refuses intake without it unless explicitly overridden.

## Credentials

- `[Q-CRED-001]` *Token families do not interchange* :: [AUTHENTICATION.md](AUTHENTICATION.md) :: `xoxc-`/`xoxd-` for slackdump, `xoxp-` for slack-advanced-exporter + emoji, `xoxb-` for Anthropic MCP.
- `[Q-CRED-002]` *`config.env` must never be committed* :: `playbooks/TOKEN-HANDLING.md` :: second line of defense is `scripts/scan-and-redact-migration-secrets.py`.

## Verification

- `[Q-VER-001]` *Silent data loss is the modal failure* :: source doc §"verify that channel and user data imported correctly" :: reconciliation must be explicit (counts + samples), never "it looked right".
- `[Q-VER-002]` *Classify every nonzero delta* :: [VERIFICATION-COOKBOOK.md](VERIFICATION-COOKBOOK.md) :: legitimate vs. suspicious, never "within tolerance".

## Gaps & Known Losses

- `[Q-GAP-001]` *Non-native artifacts become explicit sidecars, not silent drops* :: `playbooks/GAP-DISPOSITION-TAXONOMY.md` :: four classes — native-importable, sidecar-only, manual-rebuild, unrecoverable.
- `[Q-GAP-002]` *Slack Connect messages from the other org are not migratable* :: source doc / Slack Connect design :: "Your messages only; external org controls theirs."

## Using the Bank

When adding a new rule, cite its `[Q-*]` tag. When removing a rule, remove the
corresponding entry here so stale entries do not accumulate. Agents should
treat the quote bank as authoritative over ad-hoc reasoning; if the anchor
disappears, `† Theory-Kill` the rule until a new anchor is found.
