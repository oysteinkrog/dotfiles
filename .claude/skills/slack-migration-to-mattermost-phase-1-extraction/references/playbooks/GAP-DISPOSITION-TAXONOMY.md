# Gap Disposition Taxonomy

Every missing or transformed Slack artifact should land in exactly one disposition class.

## Classes

- `native-importable`: represented directly in Mattermost JSONL/import ZIP
- `sidecar-only`: preserved as explicit archive channel or attached artifact
- `manual-rebuild`: not importable, but a concrete rebuild backlog exists
- `unrecoverable`: cannot be recovered with the chosen plan tier or available artifacts

## Examples

- channel message history: usually `native-importable`
- canvases and lists: usually `sidecar-only`
- workflow builder automations: usually `manual-rebuild`
- expired Slack file links without downloaded binaries: often `unrecoverable`

## Requirement

The handoff must list the class, reason, and next action for every major non-native artifact family.
