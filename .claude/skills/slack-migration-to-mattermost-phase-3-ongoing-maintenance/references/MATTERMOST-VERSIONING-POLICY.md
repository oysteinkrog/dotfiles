# Mattermost Versioning Policy

## Release types

Mattermost uses semantic versioning: `MAJOR.MINOR.PATCH`.

- **Patch** (`10.11.1 → 10.11.2`): bug fixes, security fixes, no schema changes.
- **Minor** (`10.11 → 10.12`): new features, possible schema changes, possible plugin API changes, possible config format changes.
- **Major** (`10.x → 11.x`): breaking changes expected. Plan accordingly.

## Release cadence (as of April 2026)

- **Patch**: weekly-ish, aggregating bug + security fixes.
- **Minor**: monthly, `10.11 → 10.12 → 10.13 ...`
- **Major**: annual-ish, `10.x → 11.x ...`

Verify against current pattern at
<https://mattermost.com/releases/> — the schedule shifts.

## ESR (Extended Support Release)

Mattermost designates certain minors as ESR, meaning they receive
security patches for ~12 months beyond the normal minor cadence. ESR
minors are announced with each release; as of April 2026 the current ESR
is 10.11.

Recommendation: **track ESR for production**. Skip non-ESR minors unless
a specific feature matters. Upgrade to the next ESR when it ships (roughly
annually).

## EOL (End of Life)

- Non-ESR minors: EOL 60 days after the next minor ships.
- ESR minors: EOL 18 months after ship, approximately.

`[Q-UPG-002]` — Mattermost 10.5 ESR reached EOL in November 2025. Do not
run EOL versions in production.

## Security releases

Mattermost publishes security advisories at
<https://mattermost.com/security-updates/>. Each advisory lists:
- affected versions
- fixed versions
- severity (low / medium / high / critical)

Upgrade SLO per severity:

| Severity | Max delay |
|----------|-----------|
| Critical | 24 hours |
| High | 72 hours |
| Medium | 7 days |
| Low | with next regular upgrade |

## Version string format

`curl -fsS https://chat.acme.com/api/v4/config/client?format=old | grep Version`

Returns `"Version":"10.11.3"`. Phase 3 scripts parse this; operator can
read it in `latest-health.json`.

## Build numbers

Mattermost also exposes a build number that changes per commit, not per
release. Ignore for most purposes; use the semver version.

## Changelog convention

Each release has a changelog at:

- `https://mattermost.com/changelog/` (top-level)
- `https://docs.mattermost.com/install/self-managed-changelog.html` (detailed)
- `https://github.com/mattermost/mattermost/releases/tag/v<version>` (GitHub)

The `version-drift-auditor` subagent fetches these before recommending
an upgrade.

## Pinning strategy

Default for Phase 3:

```bash
MATTERMOST_TARGET_VERSION="10.11.3"   # pin to specific patch
```

When a new patch ships within the current ESR minor, update this to the
new patch version. When a new ESR minor ships (~annually), upgrade to
that (major-upgrade cadence).

Do NOT set:

- `MATTERMOST_TARGET_VERSION=""` (triggers skill's fallback, which today
  errors — intentionally)
- `MATTERMOST_TARGET_VERSION="latest"` (apt doesn't accept a literal
  "latest"; would fail at install time anyway)

## Skipping versions

You can skip non-ESR minors (10.12, 10.13 etc.) and stay on ESR 10.11.
Mattermost supports this; the next ESR (when it ships) will have an
upgrade path that tolerates multiple skipped versions.

You cannot skip a major cleanly; `10.x → 11.x → 12.x` in order.

## Plugin version compatibility

Each plugin lists a `minServerVersion` in its manifest. After upgrading
Mattermost, check System Console → Plugins for compatibility warnings.

## Config format drift

Minor versions may add config fields. Your existing `config.json` continues
to work (new fields default reasonably); if you regenerate config via
Phase 2's `render-config`, you pick up the new defaults explicitly.

## Database schema drift

Minor versions may change schema (add columns, indexes, backfill).
Migrations run on service startup. See
[diagnostics/UPGRADE-DIAGNOSTICS.md](diagnostics/UPGRADE-DIAGNOSTICS.md)
"Long migration hang".

## Related

- [UPGRADE-STRATEGY.md](UPGRADE-STRATEGY.md) — operator-facing upgrade rules
- [playbooks/UPGRADE-GO-NO-GO.md](playbooks/UPGRADE-GO-NO-GO.md) — per-release decision
- [workflows/MAJOR-UPGRADE-WORKFLOW.md](workflows/MAJOR-UPGRADE-WORKFLOW.md) — major cadence playbook
