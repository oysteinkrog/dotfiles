# MIGRATION.md — Audit Dir Migration

<!-- TOC: When to migrate | The migrate-audit-dir.sh script | What it preserves | What it can't migrate | Worked examples -->

> Projects move (rename, relocate, get split, get merged). The audit dir lives **inside** the project at `<project>/beads_compliance_audit/`, so a simple `mv` of the project takes it along — but `manifest.json#project_path` still points at the old location and must be rewritten. `migrate-audit-dir.sh` does the mechanical work; this file explains when and how.

---

## When to migrate

| Scenario | Migrate? |
|----------|:--------:|
| Project renamed (e.g., `myproj` → `my-cool-project`) | ✓ |
| Project relocated to a new parent dir | ✓ |
| Project moved between developer machines | ✓ (with audit dir) |
| Project split into N sibling projects | Migrate audit dir to one; bootstrap fresh audits for others |
| Project merged from N siblings | Bootstrap fresh; can't merge audit dirs cleanly |
| Project's bead-id prefix changed | Migrate (audit dir tolerates new prefix per round-2 fixes) |
| Major rubric tuning (1.x → 2.0) | Don't migrate; bootstrap fresh per [CHANGELOG.md](CHANGELOG.md) |

---

## The migrate-audit-dir.sh script

```bash
~/.claude/skills/beads-compliance-and-completion-verification/scripts/migrate-audit-dir.sh \
  /old/path/myproj/beads_compliance_audit \
  /new/parent/my-cool-project
```

The script:

1. **Validates** that `/new/parent/my-cool-project/.beads` exists.
2. **Computes** the target audit dir as `/new/parent/my-cool-project/beads_compliance_audit`.
3. **Refuses** to overwrite an existing audit dir at the target.
4. **Moves** the audit dir to its new home inside the new project.
5. **Updates** `manifest.json#project_path` in the top-level + every pass's manifest.
6. **Records** the migration in `MIGRATION_LOG.md` (committed).
7. **Verifies** rubric_sha256 still matches; warns if not.
8. **Commits** if audit dir is git-tracked.

---

## What the migration preserves

- All `passes/<UTC>/` history.
- All scorecards, evidence packs, raw logs.
- All trends.md trajectories.
- All synthesis.md cross-bead findings.
- The audit dir's git history.
- The rubric.md (incl. its SHA — re-verified post-migration).
- Convergence trajectories across passes.

---

## What migration can't preserve

| Lost in migration | Why |
|-------------------|-----|
| External cross-references | If another audit dir referenced this one's path, the reference breaks |
| Symlinks pointing into the audit dir | OS-level paths change |
| CI hardcoded paths | GitHub Actions / cron / systemd paths need manual update |
| Cached subagent state (if any) | Per-pass; not migration-relevant |
| Local environment variables (`AUDIT_GPG_KEY`, etc.) | Per-machine; not in audit dir |

After migration, manually update:

- `.github/workflows/*.yml` — hardcoded audit dir paths.
- `cron / systemd timers` — paths to `run-pass.sh` arguments.
- `metrics-export.sh` cron jobs — output paths and source dirs.
- Any portfolio-audit.sh scripts referencing the old project location.

---

## Worked example: project rename

```bash
# Before: /data/projects/oldname/ + /data/projects/oldname/beads_compliance_audit/
# Want: /data/projects/newname/ + /data/projects/newname/beads_compliance_audit/

# 1. Rename the project
mv /data/projects/oldname /data/projects/newname

# 2. Migrate the audit dir
~/.claude/skills/.../scripts/migrate-audit-dir.sh \
  /data/projects/oldname/beads_compliance_audit \
  /data/projects/newname

# 3. Verify
jq '.project_path' /data/projects/newname/beads_compliance_audit/manifest.json
# Should print: "/data/projects/newname"

# 4. Update CI / cron
sed -i 's|oldname|newname|g' .github/workflows/beads-tripwire.yml

# 5. Run a pass on the renamed project to confirm everything still works
~/.claude/skills/.../scripts/run-pass.sh /data/projects/newname --threshold 700 --policy report-only
```

---

## Worked example: developer machine handoff

Developer A is leaving the team; Developer B inherits the project + audit dir.

```bash
# Developer A: archive
cd /data/projects
tar czf myproj-bundle.tar.gz myproj/ myproj/beads_compliance_audit/
# Transfer myproj-bundle.tar.gz to Developer B

# Developer B: extract
tar xzf myproj-bundle.tar.gz -C /home/devB/projects/
# Audit dir still references Developer A's path; migrate to fix
~/.claude/skills/.../scripts/migrate-audit-dir.sh \
  /home/devB/projects/myproj/beads_compliance_audit \
  /home/devB/projects/myproj

# Verify
~/.claude/skills/.../scripts/run-pass.sh /home/devB/projects/myproj \
  --threshold 700 --policy report-only
# Should produce a passing audit on the new machine
```

---

## Worked example: project split

Project `monolith` is split into `monolith-core` and `monolith-extras`.

```bash
# 1. Decide which split inherits the audit dir
# Usually: the one with more closed beads + more historical state.
# Let's say monolith-core inherits.

# 2. Migrate the audit dir
~/.claude/skills/.../scripts/migrate-audit-dir.sh \
  /data/projects/monolith/beads_compliance_audit \
  /data/projects/monolith-core

# 3. Bootstrap a fresh audit for monolith-extras
~/.claude/skills/.../scripts/bootstrap-audit.sh \
  /data/projects/monolith-extras 700 onboarding completion-debt

# 4. Note the split in monolith-core's audit MIGRATION_LOG
echo "Split from monolith on $(date -u +%Y-%m-%dT%H:%M:%SZ); monolith-extras forked." \
  >> /data/projects/monolith-core/beads_compliance_audit/MIGRATION_LOG.md
```

---

## Worked example: portfolio reorg

Portfolio of 5 projects gets reorganized — old layout `/data/projects/*` flattens to `/data/projects/team/projectname`.

```bash
for proj in projA projB projC projD projE; do
  mkdir -p /data/projects/team
  mv /data/projects/$proj /data/projects/team/$proj
  ~/.claude/skills/.../scripts/migrate-audit-dir.sh \
    /data/projects/${proj}/beads_compliance_audit \
    /data/projects/team/$proj
done

# Update portfolio-audit.sh's --parent
~/.claude/skills/.../scripts/portfolio-audit.sh /data/projects/team
```

---

## Manual migration (if the script doesn't fit)

For unusual layouts, do it manually:

```bash
# 1. Move
mv /old/audit-dir /new/audit-dir

# 2. Update top-level manifest
jq --arg p "/new/project/path" '.project_path = $p' \
  /new/audit-dir/manifest.json > /tmp/m.json
mv /tmp/m.json /new/audit-dir/manifest.json

# 3. Update each pass's manifest
for m in /new/audit-dir/passes/*/manifest.json; do
  jq --arg p "/new/project/path" '.project_path = $p' "$m" > /tmp/m.json
  mv /tmp/m.json "$m"
done

# 4. Append to MIGRATION_LOG
{
  echo "## Manual migration $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Old: /old/audit-dir"
  echo "- New: /new/audit-dir"
  echo "- New project: /new/project/path"
} >> /new/audit-dir/MIGRATION_LOG.md

# 5. Commit if git-tracked
git -C /new/audit-dir add -A
git -C /new/audit-dir commit -m "audit: manual migration"
```

---

## Verifying a migration succeeded

```bash
# 1. manifest.json#project_path matches the new location
jq '.project_path' /new/audit-dir/manifest.json
# Should match new location

# 2. Every pass's manifest matches
for m in /new/audit-dir/passes/*/manifest.json; do
  pp=$(jq -r .project_path "$m")
  if [ "$pp" != "/new/project/path" ]; then
    echo "MISMATCH: $m has $pp"
  fi
done

# 3. rubric_sha256 still matches
ON_DISK=$(sha256sum /new/audit-dir/rubric.md | awk '{print $1}')
RECORDED=$(jq -r .rubric_sha256 /new/audit-dir/manifest.json)
[ "$ON_DISK" = "$RECORDED" ] && echo "rubric SHA OK" || echo "rubric SHA MISMATCH"

# 4. A fresh pass still works
~/.claude/skills/.../scripts/run-pass.sh /new/project/path --threshold 700 --policy report-only
```

If all 4 pass, the migration is good.

---

## Anti-patterns

- **Migrating without committing first.** If the migration goes wrong, you've lost history.
- **Migrating across major skill versions.** Bootstrap fresh per CHANGELOG.md instead.
- **Not updating CI / cron** after migration. The next scheduled run fails.
- **Migrating in-place** (using `--in-place` flags or whatever). Always create the new path first; don't overwrite.
- **Trusting the script blindly** — review `MIGRATION_LOG.md` after every migration.
