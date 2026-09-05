# Failure Modes — `<subsystem>` (template)

> Replace `<subsystem>` with the real subsystem name. Each failure mode is
> a separate `# FM-fm-<id>` block. Aim for 3–10 per subsystem.

---

# FM-fm-<subsystem-slug>-<symptom-slug>

id: fm-<subsystem-slug>-<symptom-slug>
title: <one-line description>
severity: P0 | P1 | P2 | P3
subsystem: <subsystem>
symptoms:
  - <what the user / agent observes — bullet 1>
  - <bullet 2>
  - <bullet 3>
root_cause: |
  <one paragraph explaining why the broken state happens. Cite a specific
  code path / FS atomicity issue / race / library bug if known.>
observable_signals:
  - file:line — <e.g., `.beads/issues.jsonl:142` malformed UTF-8>
  - query — <e.g., `sqlite3 .beads/beads.db 'pragma integrity_check'` returns non-OK>
  - log_pattern — <e.g., regex `panic.*lock_held`>
  - hash — <e.g., `sha256(.beads/beads.db) != recorded value`>
prior_incidents:
  - git_sha:abcd1234 (commit message excerpt)
  - br-NNN  (bead title excerpt)
  - cass:source_path#line  (one-sentence excerpt)
currently_auto_detected: yes | no
currently_auto_fixed: yes | no
evidence:
  - file:line  citation supporting the FM exists
  - one or more of (cass quote / bead / git SHA)

---

# FM-fm-<subsystem-slug>-<another-symptom-slug>

... (next FM, same shape)

---

## n/a

> If this subsystem genuinely has no failure modes worth detecting, replace
> the FM blocks above with a single `## n/a` block citing:
> - what searches you ran (cass, br ready, gh issue list, git log --grep)
> - why each turned up nothing
> - your rationale for treating the subsystem as out-of-scope

The "n/a" path is acceptable for subsystems that don't apply (e.g., `network`
for an offline-only CLI). It's NOT acceptable for subsystems that simply
weren't searched.
