# Scope Decision

Phase 0.5 emits `phase0_scope_decision.md`: an explicit declaration of what's required, what's conditional-included, what's conditional-skipped, and what's not-doing for this run. It's the guardrail against silent scope expansion ("this was supposed to be a 30-minute cleanup, but it turned into a 4-hour CI rewrite").

Source: saas-billing's SCOPE-TRIAGE.md.

---

## Format

```markdown
## Phase 0 Scope Decision — repo-janitor-2026-05-08 on `<repo>`

**Mode:** `<mode>`
**Tier:** T3 (4,200 tracked files) + 2 complexity points (LFS, submodules) → T4 effective
**Run intent:** "<one-line user description>"

### REQUIRED (will run)
- [ ] Phase 0 — confirm inputs
- [ ] Phase 1 — project profile + archetype
- [ ] Phase 2 — candidate inventory + reference graph
- [ ] Phase 2.5 — secret scan (NON-NEGOTIABLE)
- [ ] Phase 3 — recovery bundle
- [ ] Phase 4 — triage with verdicts
- [ ] Phase 5 — categorized plan + user confirm

### CONDITIONAL (will run if applicable)
- [ ] Phase 6 — moves (only if move plan non-empty)
- [ ] Phase 7 — deletes (only if delete plan non-empty AND verbatim auth received)
- [ ] Phase 8 — gitignore (only if gitignore plan non-empty)

### CONDITIONAL-SKIPPED (might apply but won't run)
- [ ] Phase 9 fresh-eyes round 3 (T2 default; user can opt in)

### NOT DOING (out of scope this run)
- [ ] Phase 11 user-lens review (skipped unless user explicitly asks)
- [ ] Cat C TOML moves (deferred per `references/TRIAGE-RUBRIC.md § Cat-C deferral` rule; refs too pervasive)
- [ ] Cleanup of submodule subtrees (require separate skill instances)
- [ ] Any work on `legacy/` subdir (user said it's a frozen archive)
- [ ] Any push to remote (user pushes manually after review)

### CONDITIONAL BUNDLES (which smell-rule clusters apply for this archetype)
- [x] core_smells (always)
- [x] sqlite_smells (archetype: rust-with-data-fixtures)
- [x] secret_smells (always; Phase 2.5)
- [x] planning_doc_smells (archetype suggests likely)
- [ ] python_cache_smells (archetype: no Python detected)
- [ ] node_modules_smells (archetype: no Node detected)
- [x] go_test_artifact_smells (archetype: Go-cli polyglot member)

### ESTIMATED SCOPE
- Wall time: 3–4 hours
- Candidates: ~80 (preview run)
- Recovery commits: ~6
- Reference rewrites: ~12 across 4 files
- User attention required: 3 gates (Phase 5 plan confirm, Phase 7 verbatim auth, Phase 8 verbatim auth if shadowing)

### ESCALATION POSSIBILITIES
This run COULD escalate to:
- `harden-secret-leak` (if Phase 2.5 finds a real secret)
- `triage-only` (if Phase 4 finds 200+ broken refs in move plan)
- `recover-from-bad-cleanup` (if Phase 6 build breaks repeatedly)

If any escalation triggers, I will halt and ask before proceeding.
```

The user reads this at Phase 0; if anything is wrong (Cat C should NOT be deferred; user wants pythoon_cache_smells included even though no Python is at root), the user adjusts. The file is then committed (not literally — saved to workspace) before Phase 1 starts.

---

## Conditional bundle activation table

The skill organizes smell rules into bundles. Each archetype activates a default subset; users can adjust.

| Bundle | Activate when | Keep dormant when |
|--------|---------------|-------------------|
| `core_smells` | Always | Never (these are universal) |
| `sqlite_smells` | Project has `*.sqlite*` files OR sqlite-rs/sqlite3 dep | Project explicitly excludes (`MEMORY.md` says "tests use postgres only") |
| `secret_smells` | Always (Phase 2.5 mandatory) | Never |
| `planning_doc_smells` | Project root has 5+ `*.md` files matching capitalized patterns | Project's docs are already in `docs/` (already organized) |
| `progress_report_smells` | Project root has `progress*.md` or `bd-*.md` files | Project doesn't use beads |
| `multi_llm_plan_smells` | Project has `*__GPT.md` or similar variants | Single-LLM workflow project |
| `python_cache_smells` | Project has `pyproject.toml` OR `requirements.txt` OR `*.py` at root | No Python detected |
| `node_modules_smells` | Project has `package.json` | No Node detected |
| `rust_artifact_smells` | Project has `Cargo.toml` | No Rust detected |
| `go_test_artifact_smells` | Project has `go.mod` | No Go detected |
| `nextjs_smells` | Project has `next.config.*` | Not a Next.js app |
| `nohup_log_smells` | Project root has `nohup.out` OR `*.log` | None at root |
| `editor_backup_smells` | Always (low-cost check) | Never |
| `os_detritus_smells` | Always (low-cost check) | Never |
| `lfs_smells` | Project uses `git-lfs` | LFS not in use |
| `submodule_smells` | Project has `.gitmodules` | No submodules |
| `agent_tooling_smells` | Project has `.beads/`, `.rch/`, `.repo_janitor_workspace/` parent indicators | No agent-tooling state |
| `multi_repo_skip_list` | Multi-repo run (BATCH-MODE) | Single-repo run |

The activation logic runs at Phase 0.5; results live in `phase0_scope_decision.md` and inform `coverage_matrix.md`.

---

## Activation rules per archetype

| Archetype | Auto-activate | Auto-dormant |
|-----------|---------------|---------------|
| `single-rust-crate` | core, secret, rust_artifact, planning_doc, lfs | python_cache, node_modules, nextjs, go_test |
| `polyglot-monorepo` | core, secret, planning_doc + per-language detected | (per-subtree) |
| `claude-skill-repo` | core, secret, planning_doc, agent_tooling, progress_report | python_cache, node_modules, nextjs, rust_artifact |
| `nextjs-saas` | core, secret, node_modules, nextjs, planning_doc | python_cache, rust_artifact, go_test |
| `python-package` | core, secret, python_cache, planning_doc | node_modules, nextjs, rust_artifact, go_test |
| `go-cli` | core, secret, go_test_artifact, planning_doc | python_cache, node_modules, nextjs, rust_artifact |

Users can override per run.

---

## Negative-decision recording

Every "NOT DOING" entry in the scope decision is a negative decision. The skill records why each one was excluded so that Phase 11 review (or future maintenance-review runs) can see what was deferred.

```markdown
### Negative decisions (why we're not doing it)

1. **Cat C TOML moves** — DEFERRED
   - Trigger: 15 TOML files at root with reference count >10 each, hardcoded paths in Rust source
   - Why deferred: moving requires updating 30+ source files; high risk of breaking gates; not in this run's time budget
   - When to revisit: when the user has time for the larger refactor; or when the TOML reference structure changes

2. **`legacy/` subdir excluded** — USER SAID FROZEN ARCHIVE
   - Trigger: user MEMORY.md mentions "legacy/ is a frozen archive; never touch"
   - Why excluded: explicit user policy
   - When to revisit: never (user must override explicitly)

3. **Phase 11 user-lens review** — SKIPPED PER DEFAULT
   - Trigger: user didn't ask for it
   - Why skipped: optional phase; off by default
   - When to revisit: user can ask after the run completes
```

These three records survive into the handoff report and into `cass` for next time.

---

## Blast-radius escalator

Mid-run, if the actual scope exceeds the planned scope by >2x (e.g., Phase 4 found 8x more candidates than the preview suggested, OR Phase 5 plan reveals 30x more reference rewrites than estimated), the skill halts and asks for re-scoping:

```
ESCALATION TRIGGERED:
- Original estimate: 80 candidates, 12 reference rewrites
- Actual: 167 candidates, 89 reference rewrites
- Blast-radius factor: 6.4x

Should I:
(a) Continue with the expanded scope (will take 8+ hours instead of 3)
(b) Pause and let you review the new estimate
(c) Halt and write the partial state to handoff for resume later
```

The user picks. The skill records the escalation in `mode_escalation_decision.md`.

---

## Why this matters

Without scope decision:
- The agent silently expands scope; the user runs out of patience mid-Phase 6
- Negative decisions are forgotten; future runs re-litigate them
- "What did we agree to do?" gets ambiguous after several handoffs

With scope decision:
- Every run starts with explicit boundaries
- Re-runs (`maintenance-review`) compare to the previous scope decision
- The audit trail makes it impossible to silently drift

This is one of the highest-leverage patterns in the saas-billing-patterns skill; it transforms ad-hoc "let me know what you find" into a contract.
