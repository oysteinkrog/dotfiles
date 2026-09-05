# Glossary

Skill-specific terms in alphabetical order.

---

**Anti-pattern** — A documented "never do this" pattern with a worked example. See ANTI-PATTERNS.md.

**Apply log** (`apply_log.tsv`) — Phase 6/7/8 record of every committed mutation: candidate id, action, new commit SHA, gates status, duration.

**Archetype** — The repo's category (single-rust-crate, polyglot-monorepo, claude-skill-repo, etc.). Detected at Phase 1; seeds protected_globs and conventional destinations.

**Audit trail** — The full set of per-mutation logs (apply_log, reference_rewrite_log, cleanup_authorization, secret_findings) that lets a future reader audit every decision the skill made.

**Backup ref** (`refs/repo-janitor-backup/<DATE>-pre-cleanup`) — Layer-1 recovery: a git ref pointing at HEAD before any cleanup commit lands. Survives gc.

**Bundle** — The persistent recovery directory at `<project-root>/.repo_janitor_workspace/recovery-bundle-<DATE>/`. Contains byte-identical copies of every candidate + provenance + reference graph + `.gitignore` snapshot. Layer-2 recovery.

**Candidate** — A file flagged by the inventory walk as matching at least one junk-smell rule. Not yet classified.

**Categorical plan** — The Phase 5 user-facing presentation that groups verdicts into A/B/C/... letter categories. The frankensqlite-style.

**Cat-C deferral** — When a category of moves is technically valid but would require updating ≥10 hardcoded path references in source code, the verdict flips to "DEFERRED" and the category is left at root. Named after the Cat-C TOML-contracts deferral in the frankensqlite Apr-27 cleanup.

**Confidence** — A [0, 1] score on each triage verdict. <0.7 forces the verdict to `surface-to-user`.

**Content fingerprint** — A signature derived from the bytes of a file (magic bytes, base64-decodability, prefix patterns). Distinct from filename rules.

**DCG** — Destructive Command Guard. A Claude Code hook that blocks commands like `rm -rf`, `git reset --hard`, `git push --force`. The skill is designed to never need bypassing DCG.

**Edit-tool rewrite** — A reference rewrite via the Edit tool with explicit (file, old_string, new_string), logged in reference_rewrite_log.tsv. Distinct from `sed -i` regex transforms (forbidden by AGENTS.md).

**Fingerprint** (also: smell-fingerprint) — The combination of filename match + content fingerprint that drives smell-tag assignment.

**Force-add bypass** — When `git add -f <file>` overrides `.gitignore`. Mitigated by `.githooks/pre-commit`. Real example: mcp_agent_mail Apr-27.

**Fresh-eyes** — Phase 9 verification using three review prompts × ≥2 rounds. Calibrated from documentation-website-for-software-project.

**Glob** — A `.gitignore`-style pattern. `temp_*` matches files; `temp/` matches directories; `**/*.json` matches at any depth.

**Handoff report** (`handoff_report.md`) — Phase 10 final output: counts, commit SHAs, recovery recipes, push commands.

**Inventory** — Phase 2 enumeration of every file matching at least one junk-smell rule.

**LFS smudge** — Materializing the actual blob content from an LFS pointer. Required before bundle copy for LFS-tracked candidates.

**Mirror backup** — `git clone --mirror` that captures every ref. Layer-4 recovery, only used in secret-leak runs.

**Per-commit gate** — Running the project's test/typecheck/lint/build commands after every Phase 6/7/8 commit (not just at the end).

**Polish bar** — The 18 dimensions that distinguish "done" from "completed successfully". See POLISH-BAR.md.

**Primary branch** — The repo's main branch. Detected via `git symbolic-ref refs/remotes/origin/HEAD`. Never assumed to be `main`.

**Protected glob** — A pattern in `protected_globs` that always classifies as `protected` regardless of smell. E.g., `Cargo.toml`, `LICENSE*`.

**Recovery branch** (`repo-janitor-<DATE>`) — The branch the skill creates for cleanup commits. Default name; user-overridable.

**Reference graph** (`reference_graph.json`) — For each candidate, the list of inbound references from the rest of the repo. Built at Phase 2; consumed by Phase 4 (verdict decisions) and Phase 6 (rewrite plans).

**Reference rewrite** — Updating a path-string in source code after a move. Always via the Edit tool, never via `sed -i`.

**Run id** (`repo-janitor-<DATE>`) — Identifier for this run, used as the Agent Mail thread id and as part of the recovery branch name.

**SHADOWING-AUDIT** — Running `git ls-files <pattern>` for every proposed `.gitignore` addition to surface any tracked files the new rule would mask.

**Smell tag** — A category label assigned to candidates: `sqlite-db`, `skill-output`, `planning-doc`, etc. See FILE-SMELLS.md.

**Surface-to-user** — A verdict that means "I'm not confident enough to auto-decide; the user must say". Default when confidence < 0.7.

**Synonym branch** — A branch that mirrors the primary (e.g., `master` ← `main` in repos that maintain `master` for legacy URL compatibility). Phase 1 detects these.

**Triage** — Phase 4 classification of candidates into verdicts. Parallel via per-batch workers.

**Verdict** — One of: `delete-and-gitignore`, `delete-no-gitignore`, `gitignore-only`, `move`, `keep-in-place`, `protected`, `surface-to-user`, `secret-leak` (Phase 2.5).

**Verbatim authorization** — User text that quotes the literal commands, recorded in `cleanup_authorization.txt`. Required before any Phase 7 or Phase 8 destructive action.

**Workspace** — `<project>/.repo_janitor_workspace/`, the in-repo transient directory holding logs, plans, and run state.
