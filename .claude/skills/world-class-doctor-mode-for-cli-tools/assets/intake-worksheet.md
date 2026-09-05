# Intake Worksheet

Before invoking the skill, fill in this worksheet. Hand it to the calling agent at intake. The agent will pre-fill what it can detect; the user confirms / corrects the rest.

---

## Project identity

```
project_name: <e.g., beads_rust>
project_url:  <e.g., https://github.com/Dicklesworthstone/beads_rust>
target_repo:  <absolute path on this machine; default = cwd>
target_sha:   <auto-detected; confirm>
default_branch: <auto-detected; confirm; usually `main`>
```

## Binaries the project produces

```
- name: <e.g., br>
  entry_point: <e.g., crates/br/src/main.rs (Rust) | cmd/<name>/main.go (Go) | etc.>
  install_path: <where users will have it; e.g., ~/.local/bin/br>
  tier: <primary | secondary> (only if multi-binary)
- name: <next binary if any>
  ...
```

## Existing doctor (if upgrade mode)

```
existing_doctor_subcommand: <e.g., doctor | health | verify | check | none>
existing_help_excerpt: |
  <paste the first 30 lines of `<tool> <existing-subcommand> --help` here>
known_failures_of_existing_doctor: |
  - <e.g., "panics on a corrupted .beads/issues.jsonl">
  - <e.g., "auto-mutates .gitignore without --fix">
  - <leave blank if there are none>
```

## Mode

```
mode: <add | upgrade | audit-only | re-score-only | single-failure-mode-rescore | absorb-playbook>
mode_rationale: <one line explaining why>
```

## Operating location

```
operating_location: <worktree | in-place>  (default: worktree)
worktree_branch: <default: doctor-mode-pass-<N>; can override>
worktree_base: <default: default_branch; can override>
```

## Subsystems

Tick the ones that apply to this project. Add custom subsystems at the bottom.

```
[ ] state_files          — embedded DB, JSONL, lockfiles, pidfiles
[ ] configs              — TOML/YAML/JSON config, env files, MCP configs
[ ] schemas              — DB migrations, schema drift, version mismatches
[ ] caches               — disk caches, memo files, derived indexes
[ ] sockets              — Unix sockets, named pipes, TCP listeners
[ ] hooks                — git hooks, pre-commit, IDE hooks
[ ] plugins              — plugin dirs, extension manifests
[ ] secrets              — keychain entries, env vars, credential files
[ ] permissions          — file modes, ACLs, ownership
[ ] external_artifacts   — built binaries, completion scripts, man pages
[ ] concurrency_primitives — flock files, advisory locks, mutexes
[ ] network              — DNS, TLS, vendor APIs (if any)
[ ] userland_state       — ~/.config/<tool>/, ~/.local/share/<tool>/, XDG dirs
[ ] auth_state           — token expiry, scope drift  (Pattern 9 only)
[ ] vendor_drift         — local cache vs. remote reality  (Pattern 9 only)
[ ] rate_limits          — vendor API budget  (Pattern 9 only)
[ ] daemon_state         — pidfile, socket, watchdog  (Pattern 4 only)
[ ] shared_memory        — shmctl segments  (Pattern 4 only; rare)
[ ] tui_state            — rendering caches, persisted layouts  (Pattern 6)
[ ] (custom):            — project-specific subsystem name + 1-line description
```

## Recurring failure modes the user has seen manually

For each FM the user can recall (1–10 typical):

```
- title: <e.g., "lockfile orphaned after kill -9">
  symptoms:
    - <bullet>
    - <bullet>
  manual_fix: <one-paragraph recipe the user has run before>
  frequency: <often | occasional | rare>
  blast_radius: <cosmetic | nuisance | degrades_correctness | corrupts_state | loses_data>
```

## Patterns (from the cookbook)

Tick all that apply. The skill stacks them:

```
[ ] Pattern 1 — Single-binary state-owning CLI
[ ] Pattern 2 — Multi-binary toolkit (single shared state)
[ ] Pattern 3 — Single-binary stateless / config-only CLI
[ ] Pattern 4 — Daemon / long-running process CLI
[ ] Pattern 5 — Installer / provisioner CLI
[ ] Pattern 6 — TUI-first CLI with non-interactive subset
[ ] Pattern 7 — AI-coding-agent CLI
[ ] Pattern 8 — Doctor for a tool you don't own
[ ] Pattern 9 — Distributed CLI (vendor-API client)
[ ] Pattern 10 — Absorb-playbook
[ ] Pattern 11 — Doctor for an installer-bootstrap chain
[ ] Pattern 12 — Doctor for a skill itself (meta-doctor)
[ ] Pattern 13 — Forensic mode (read-only, no fixers; for compliance / audit)
[ ] Pattern 14 — Doctor for a build system (Cargo / npm / pip — the doctor IS the build tool)
[ ] Pattern 15 — Compliance / regulated-environment doctor (with audit log + sign-off)
```

## Triangulation + CASS appetites

```
triangulation_appetite: <none | peer-claude | multi-model>
cass_mining_appetite: <skip | quick | deep>
online_appetite: <offline-only | online-allowed>
```

## Skills installed (jsm autoinstall consent)

Tick the ones the user authorizes the skill to install if missing:

```
[x] operationalizing-expertise                   (foundational; recommended)
[x] codebase-archaeology, codebase-report  (Phase 1)
[x] multi-pass-bug-hunting                      (Phase 7)
[ ] multi-model-triangulation                   (Phase 4/7; recommended)
[ ] testing-fuzzing, testing-metamorphic, testing-conformance-harnesses,
     testing-golden-artifacts, testing-real-service-e2e-no-mocks  (Phase 5 extensions)
[x] ubs                                         (Phase 7 lint)
[x] dcg                                         (universal envelope reference)
[x] agent-mail                                  (parallel coordination; required for Pair+)
[x] br, bv                                      (Phase 4 task tracking)
[x] cass                                        (Phase 0 mining)
[ ] idea-wizard                                 (Phase 10 backlog generation)
[ ] cc-hooks                                    (Phase 8 pre-commit)
[ ] gh-actions                                  (Phase 8 CI)
[ ] github                                      (Phase 1 issue mining)
```

## Must-not-touch list

```
- <file or directory the doctor must NOT modify under any circumstance>
- <e.g., src/storage/sqlite_legacy.rs (deprecated; awaiting removal)>
- <e.g., LEGAL_NOTICE.md (lawyer-controlled; never auto-edit)>
```

## Special considerations

```
- <one-paragraph note about anything unusual>
- <e.g., "this project has a DR procedure that backs up to S3; the doctor must not interfere">
- <e.g., "the project is on a private fork of an upstream tool; merging upstream regularly">
```

## Sign-off

```
worksheet_filled_at: <ISO8601>
filled_by: <user / agent>
ready_for_phase_0: <yes | no>
```

---

## After filling

Hand this worksheet to the calling agent. The agent will:

1. Read [SKILL.md](../SKILL.md), [KERNEL.md](../references/methodology/KERNEL.md), [COOKBOOK.md](../references/methodology/COOKBOOK.md).
2. Read the per-pattern recipes the worksheet ticked.
3. Confirm any auto-detection that didn't match the worksheet.
4. Send the matching kickoff prompt from [KICKOFF-PROMPTS.md](../references/methodology/KICKOFF-PROMPTS.md).
5. Begin Phase 0.
