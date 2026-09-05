# FAQ

Common questions when applying this skill. If your question isn't here, file a bead at priority 3 to add it; the FAQ grows with the user base.

---

### Q. What if my project doesn't use git?

A. The skill currently assumes git for `target_sha` derivation in run-id. For non-git projects (Mercurial, Pijul, Fossil, or plain directories), use a content-derived SHA: `find <target> -type f | sort | xargs sha256sum | sha256sum | head -c 16` as a stand-in for `target_sha`. Run-id derivation is otherwise unchanged.

---

### Q. What if my project is a monorepo with multiple binaries in subdirectories?

A. Apply Pattern 2 (multi-binary toolkit). Each binary gets its own `<binary> doctor` subcommand calling into a shared `doctor-core` library. The workspace tracks all binaries; the aggregate score is binary-weighted.

---

### Q. Can I skip the workspace and just run the skill in-place?

A. The user can choose `in-place` mode at intake (Pattern 12 footnote). The skill defaults to `worktree` because (a) workspace artifacts shouldn't pollute the target's git history, and (b) baseline snapshots in `upgrade` mode need a stable place to live. In-place loses both benefits but is faster on tight time budgets.

---

### Q. What if the doctor itself has a bug?

A. The doctor's bug is a fixture in `tests/doctor_fixtures/fm-doctor-<bug>/`. Phase 9 round-trips against this fixture, catching regressions. For the bootstrap problem ("what fixes the doctor itself when it's broken?"), Pattern 12 (meta-doctor) validates the doctor's own structure, and the manual playbook in `<workspace>/playbook.md` § "How to recover if doctor itself goes wrong" is the human-readable last resort.

---

### Q. What if my project has no failure modes worth detecting yet (greenfield)?

A. Start with Pattern 1 + the cookbook's failure-mode catalog. Even greenfield CLIs typically have:
- Stale lockfile when the user kills the process — applies to almost everyone.
- Missing config file on first run — applies to everyone.
- Permissions wrong on credential files — applies if you have credentials.

If you genuinely can't think of three FMs, the project is too small to need a doctor yet. Wait until pass-3 of normal usage produces real bugs to encode.

---

### Q. What if the project is pre-1.0 and I need to break the doctor's own contract?

A. Per AGENTS.md (Q-004), pre-1.0 projects don't carry backward-compat shims. Bump `doctor_contract_version` to 2.0; users with old `.doctor/runs/` install the 1.x binary to undo old runs (Pattern B in [VERSIONING.md](VERSIONING.md)). The CHANGELOG.md migration note tells them how.

---

### Q. How do I handle a doctor that needs to make a destructive change (like deleting a malformed file)?

A. Per AGENTS.md RULE 1 (Q-001), `doctor --fix` never deletes. Use `Op::Rename` to move the malformed file under `<run-dir>/quarantine/`. The user reviews the quarantine periodically and decides whether to delete; the fixer never makes that call. This is the rule even when "obviously" the file should go. Retention cleanup is separate: `doctor gc --before <date> --yes` prunes old run directories only after the user names the cutoff.

---

### Q. Can the doctor run in CI without a feature branch?

A. Yes — `audit-only` mode runs no Phase 4+ implementer work. CI just scores the current binary against the rubric. `re-score-only` mode is even cheaper (just Phase 6). Both produce artifacts but never commit code.

For full passes in CI, use a feature branch (`doctor-mode-pass-N`) and merge with explicit user approval. The skill never auto-merges to main.

---

### Q. How does the skill handle my project's existing pre-commit hooks?

A. Phase 8's `subagents/integration-wirer.md` ADDS to existing pre-commit hooks; it never replaces them. If `<tool> doctor --quick` adds 1.5s to commit time and that's unacceptable, the user can move the doctor check to a manual `make pre-pr` step instead.

---

### Q. What if my project uses an embedded DB I can't lock easily (e.g., LMDB)?

A. The doctor uses an *external* lock file (`.<tool>/.doctor.lock` via `fs2`/`flock`/`portalocker`/`proper-lockfile`) that's distinct from the DB's internal lock. The doctor's lock serializes doctor invocations against each other. The DB's own lock handles project-process-level serialization. They're independent.

---

### Q. The fresh-eyes loop in Phase 7 never goes quiet — is something wrong?

A. Likely yes. Symptoms:
- The agents are touching cosmetic surfaces (renames, comment polish).
- "Trivial change" definition is too loose.

Fix: tighten to "only typo / whitespace counts as trivial; rephrasing IS a change." If after 5 rounds the code is oscillating between two states, hard-stop and file as a P1 bead requiring manual triage. The skill's termination thresholds are calibrated to converge in 2–4 rounds for most projects.

---

### Q. Can I use this skill on a project I don't own?

A. Pattern 8 (doctor for a tool you don't own) covers this. You'll build a wrapper CLI rather than modifying the upstream tool's source. The contract still holds: your wrapper has its own `mutate()` for any config it rewrites, its own backups, its own undo.

---

### Q. How do I make the doctor available to other agents in my team / org?

A. Three options:
1. **Vendor the binary** — the doctor is part of the tool's release pipeline (Pattern 11).
2. **Vendor the methodology** — fork this skill into your org's skill repo, customize for your projects.
3. **Vendor the run artifacts** — share `<workspace>/scorecard.md` / `HANDOFF.md` as part of release notes; let teammates re-run from the published baseline.

The artifacts are designed to be share-friendly: schema-versioned, content-addressable, no credentials.

---

### Q. Does the doctor work offline?

A. Yes — by design (Axiom 12). All detectors and fixers run with no network. Network detectors (vendor APIs, DNS, TLS) are opt-in via `--online` and skipped silently otherwise. CI in air-gapped environments runs the doctor unmodified.

---

### Q. What's the minimum project size where this skill makes sense?

A. Roughly: 3+ subsystems × 3+ recurring failure modes per subsystem. Below that, a 50-line bash script is enough. Above that, the methodology pays off.

A solo binary with 1k LoC and zero recurring incidents probably doesn't need a doctor yet; build the doctor when the user finds themselves running the same recovery commands twice. (That's also the cass-mining trigger — when "I had to manually fix X" appears more than once in your sessions, the doctor is owed.)

---

### Q. Should I run the skill on every pass, or only when state changes?

A. The skill is designed to be re-entered idempotently (`re-score-only`, `single-failure-mode-rescore` modes). Default cadence:

- After every release of the target tool: `re-score-only` to confirm no regression.
- After adding a new failure mode: `single-failure-mode-rescore`.
- Quarterly: full `upgrade` mode pass to surface new FMs from the past quarter's incidents.
- After any P0 incident: targeted `add` pass for the incident's FM.

---

### Q. What if cass returns no findings for my tool?

A. Either the tool is new (no prior agent sessions) or `cass` is misconfigured. The cass-miner subagent records empty queries explicitly so Phase 1 doesn't expect cass-mined FMs. Mine the bug tracker + git log instead; both usually have evidence even for new tools.

---

### Q. The scorecard says my doctor scores 800/1000 — is that good?

A. Aggregate ≥ 700 is the Polish Bar floor; ≥ 850 is "production-grade"; ≥ 950 is "world-class." Most mature doctors land 800–900. Hitting 1000 typically requires meta-doctor (Pattern 12) feedback loops because rubric anchors at 1000 require evidence that's painful to produce manually.

The trend matters more than the absolute. Pass-N → pass-N+1 with +25 to +50 points means the methodology is paying off. Plateau at 850 with no regressions for 3 passes means you've hit equilibrium for the current scope; broaden the scope (more subsystems / pair fixtures) for further uplift.

---

### Q. How do I handle test fixtures that need root or sudo?

A. The doctor's fixtures must run unprivileged. If a real-world FM needs root to reproduce (e.g., file mode 0600 on a root-owned file), the fixture uses a USER-owned analog (a file in `$HOME/.config/<tool>/`) and the FM's title clarifies "applies under user-installed AND root-installed; fixture covers user-installed only."

For root-only paths, mark the FM as `manual_remediations` in capabilities — the doctor describes; root user acts.

---

### Q. Is there a way to A/B test the doctor (e.g., with vs. without `--profile-guided`)?

A. The `ab-testing` skill (also in the user's repo) covers this for SaaS metrics. For doctor performance, simpler: run `<tool> doctor health` 100 times each variant, record p50/p95 to `scorecard_history.jsonl`, compare. The doctor's own machinery (run-id, history JSONL) is the experiment harness.

---

### Q. Does the doctor handle Windows?

A. The recipes target POSIX (Linux + macOS) primarily. For Windows:
- Use `LockFileEx` instead of `flock`.
- Use `fs.copyFile` (which is atomic on NTFS) plus Windows-specific rename semantics.
- The `tempfile + rename` pattern works on Windows (`os.rename` fails if target exists; use `os.replace` or `MoveFileEx`).

`proper-lockfile` (TS), `portalocker` (Python), `fs2` (Rust) all have Windows shims. Test on Windows in CI.
