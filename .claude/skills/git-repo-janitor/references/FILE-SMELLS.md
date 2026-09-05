# File Smells — Taxonomy of Repo Junk

Every smell tag below was earned in a real cleanup run (most from the Apr-27 multi-repo session: frankensqlite, CASS, pi_agent_rust, ntm, beads_viewer, mcp_agent_mail). Each tag has filename rules, content fingerprints, default verdict, and override cases.

A candidate gets multiple tags; the union of evidence drives Phase 4's verdict.

---

## Tag glossary

| Tag | Default verdict | Notes |
|-----|-----------------|-------|
| `sqlite-db` | delete-and-gitignore | Plus `*-wal`, `*-shm`, `*-journal` siblings |
| `sqlite-wal-shm` | delete-and-gitignore | Always tied to a sqlite-db; same fate |
| `binary-elf` | delete | Stray compiled binary; reproducible from source |
| `compiled-out` | delete | Output of `gcc -o foo`, `cargo build --bin foo` left at root |
| `nohup-leak` | delete-and-gitignore | `nohup.out` from `nohup <cmd> &` |
| `scratch-script` | delete (after refgrep) | One-off `*.py`/`*.sh`/`*.js` at root |
| `skill-output` | delete-and-gitignore | Intermediate output of a slash-skill |
| `progress-report` | move (`docs/progress/`) + gitignore | Per-bead progress markdown |
| `planning-doc` | move (`docs/planning/`) | Long-form architecture/spec/plan markdown |
| `multi-llm-plan-cluster` | move (`docs/planning/`) | `*__GPT.md`, `*__OPUS.md`, `*__GEMINI.md` siblings |
| `agent-output` | move OR delete | E.g., `*_REPORT.md`, `*_AUDIT.md`; check uniqueness |
| `audit-report` | move (`docs/audits/`) or delete | E.g., `BEAD_AUDIT_REPORT.md` |
| `dual-format-asset` | delete (the unused format) | E.g., `.png` superseded by `.webp` |
| `format-patch-blob` | delete | `*.patch` from `git format-patch` left in tree |
| `editor-backup` | delete-and-gitignore | `*.bak`, `*~`, `*.swp`, `*.swo`, `*.orig` |
| `os-detritus` | delete-and-gitignore | `.DS_Store`, `Thumbs.db`, `Desktop.ini` |
| `coverage-output` | delete-and-gitignore | `coverage*.txt`, `coverage*.json`, `lcov.info`, `*.profraw` |
| `secret-suspect` | surface-to-user / halt | See [§ Secret leakage](#secret-leakage); Phase 2.5 |
| `random-json-artifact` | delete (after content check) | Tool output, not config |
| `random-jsonl-artifact` | delete (after content check) | Often `findings.jsonl`, `ubs_*.jsonl` |
| `txt-architecture-summary` | move (`docs/reference/`) | E.g., `<NAME>_ARCHITECTURE_SUMMARY.txt` |
| `runbook-or-recovery` | move (`docs/operations/`) | `RECOVERY_RUNBOOK.md`, `OPERATIONS.md` |
| `ad-hoc-test-fixture-stub` | check refs first; usually delete | `test_*.c`, `test_*.js`, `test_*.py` at root |
| `dot-pre-skill-state` | delete-and-gitignore | `.skill-loop-progress.md`, `.<skill>-state.json` |
| `archetype-protected` | keep-in-place | Listed in `protected_globs` |
| `referenced-by-build` | keep-in-place | Mentioned in `package.json` build script, etc. |
| `referenced-by-tests` | keep-in-place | Mentioned in tests/* via grep |
| `0-byte-stub` | delete | Empty file that's tracked (e.g., `wrangler_version.txt` 0 bytes) |
| `mailbox-format-patch` | delete | First-line matches `From <sha> Mon Sep 17 00:00:00 2001` |

---

## Filename pattern rules

```
# SQLite + dev DBs
*.sqlite, *.sqlite3, *.db, *.db3
*.sqlite-wal, *.sqlite-shm, *.sqlite-journal
*.sqlite3-wal, *.sqlite3-shm, *.sqlite3-journal
*.db-wal, *.db-shm
storage*, storage.sqlite3*, dev.sqlite, test.db

# Editor / OS detritus
*.bak, *~, *.swp, *.swo, *.orig, *.rej, *.bck.*, .#*
.DS_Store, Thumbs.db, Desktop.ini, .Spotlight-V100/, .Trashes/

# Compiled / build leakage
a.out, *.o, *.so, *.dylib, *.dll, *.exe, *.pyc, *.class
__pycache__/, *.pyo, *.egg-info/

# Tool outputs
nohup.out, perf.data, perf.data.old
*.profraw, *.profdata, lcov.info
*.snap.new, *.snap.tmp
.coverage, .coverage.*, coverage_report.*, coverage*.txt, coverage*.json
findings.jsonl, ubs_*.jsonl, ubs_crit.jsonl
rustc-ice-*.txt
.skill-loop-progress.md, .skill-*-progress.md
.bd-*.md, bd-*.md (when paired with `progress_bd-` siblings)

# Multi-LLM plan clusters (a single class of file)
PLAN_*__GPT.md, PLAN_*__OPUS.md, PLAN_*__GEMINI.md
PROPOSED_*__CODEX.md, PROPOSED_*__OPUS.md
*_ROUND_1__GPT.md, *_ROUND_1__OPUS.md, *_ROUND_2__*.md
*__CLAUDE_WEB.md, *__GPT_PRO.md

# Capitalized planning / spec docs
COMPREHENSIVE_*.md, COMPREHENSIVE_SPEC_*.md
PROPOSED_ARCHITECTURE*.md, PROPOSED_*_SPEC*.md
PLAN_TO_*.md, PLAN_FOR_*.md
EXISTING_*_STRUCTURE*.md
*_SPECIFICATION.md, MVCC_SPECIFICATION.md (etc.)
PERFORMANCE_*.md, BENCHMARK*.md, BENCHMARK_COMPARISON_*.md
UPGRADE_LOG.md, CHANGELOG_AGENT_FRIENDLY.md
RICH_INTEGRATION_PLAN.md, *_INTEGRATION_BRIEF.md
TODO.md, tasks.md, ROADMAP.md (if there's also a more authoritative one)
PROPOSED_HYPERSYNC_SPEC*.md (etc.)
COVERAGE.md (when distinct from `docs/COVERAGE_POLICY.md`)
E2E_SCENARIO_MATRIX.md, E2E_SCENARIO_TRACEABILITY.md
UNIT_INVARIANT_MATRIX.md, OPPORTUNITY_MATRIX.md, FEATURE_PARITY.md
RESEARCH_FINDINGS.md, AGENT_FRIENDLINESS_REPORT.md
SUGGESTED_IMPROVEMENTS_*.md
SECURITY_REVIEW_*.md, REVIEW_FINDINGS_*.md, CROSS_REVIEW_*.md, SDK_DROP_IN_DECISION.md
GOLANG_BEST_PRACTICES.md, RUST_CLI_TOOLS.md (when not pointed at by AGENTS.md)
CASS_INDEXING_HISTORICAL_BENCHMARK_RESULTS.md
TOON_INTEGRATION_BRIEF.md
SYNC_STRATEGY.md, RECOVERY_RUNBOOK.md, RECOVERY.md (overlapping with docs/)

# Per-bead progress (frankensqlite + multi-bd-keyed pattern)
progress.md (when paired with `progress_bd-*.md` siblings)
progress_bd-*.md
bd-*.md (e.g., `bd-1cs00.1.md`)

# Architecture summary text dumps
*_ARCHITECTURE_SUMMARY.txt, CASS_ARCHITECTURE_SUMMARY.txt
*_REFERENCE_INDEX.md, SEARCH_PATTERNS_INDEX.md, QUICK_REFERENCE.md

# Auditing reports
*_AUDIT_REPORT.md, BEAD_AUDIT_REPORT.md
ANALYSIS_OF_*.md (e.g., ANALYSIS_OF_SPEC_DOC_DIFFS.md)
STATE_OF_THE_*.md, STATE_OF_THE_CODEBASE_AND_NEXT_STEPS.md

# Scratch + ad-hoc tools (typically Python or shell at repo root)
check_db.py, find_task.py, fix_*.py, refactor_*.py, enhance_*.py
finalize_*.py, restore_*.py, reapply_*.py, debug_*.py
fix_beads.sh, script_to_fix_*.sh, deploy_fix.sh
test.js, test_qjs.js, test_hash.js, test_sqlite_*.c, test_*.c at root
test_runner.rs (when src/ has a proper crate)
wrangler_version.txt, *_version.txt (when 0-byte stubs)

# Visualization pipeline (frankensqlite cluster pattern)
*_viz.py, *_visualization.py, debug_viz.py, enhance_viz*.py
finalize_viz.py, fix_viz_errors.py, reapply_enhancements.py
refactor_viz.py, restore_full_viz.py

# Format-patch blobs
*.patch (when first line matches `^From [0-9a-f]{40} Mon Sep 17 00:00:00 2001$`)

# Stray dual-format assets
<NAME>.png AND <NAME>.webp BOTH at root, only one referenced
<NAME>.svg AND <NAME>.png BOTH at root, only one referenced
```

---

## Content fingerprints

For each filename match, run a quick content sniff to confirm:

| Tag | First-bytes / pattern | Confidence boost |
|-----|----------------------|-------------------|
| `binary-elf` | `\x7fELF` (or `file <path>` says ELF) | 1.0 |
| `binary-pe` | `MZ` (Windows) | 1.0 |
| `binary-mach-o` | `\xfe\xed\xfa\xce` or `\xfe\xed\xfa\xcf` | 1.0 |
| `compiled-wasm` | `\x00asm` | 0.95 — keep if archetype = web |
| `mailbox-format-patch` | `^From [0-9a-f]+ Mon Sep` | 1.0 |
| `sqlite-db` | `SQLite format 3\x00` (16 bytes) | 1.0 |
| `sqlite-wal` | `\x37\x7f\x06\x82` or `\x37\x7f\x06\x83` (WAL magic) | 1.0 |
| `nohup-leak` | filename = `nohup.out` AND first line matches typical stdout pattern | 0.95 |
| `coverage-output` | filename matches AND first line has `:line` style coverage marker | 0.85 |
| `mailbox-format-patch` | first line matches | 0.99 |
| `0-byte-stub` | size == 0 bytes | 0.95 (still flag for inspection) |

---

## Reference-graph signals

Pure filename / content matches are not sufficient. Always combine with:

| Signal | Effect |
|--------|--------|
| ≥1 inbound reference from `*.rs`, `*.toml`, `*.go`, `*.py`, `*.ts`, `*.js`, `Makefile`, `Dockerfile`, `package.json`, `*.yaml`, `*.yml` | Force `surface-to-user` or `keep-in-place` |
| Reference is in a `tests/` directory | Likely a real test fixture; force `keep-in-place` unless explicitly overridden |
| Reference is in a markdown link `](X.md)` | Eligible for auto-rewrite; verdict can be `move` |
| Reference is in a path constant `const X_PATH: &str = "X.md"` | Eligible for surgical Edit-tool rewrite; verdict can be `move` (track in reference_rewrite_log) |
| Reference is only in another candidate that's also being deleted | Doesn't block the delete; both go in the same commit batch |
| Self-reference (file references its own basename) | Ignore — false positive |

---

## Archetype-protected globs

These are ALWAYS `protected` regardless of smell. The archetype profile (`REPO-ARCHETYPES.md`) seeds the list; users can add but not remove.

```
# Universal
README.md, LICENSE, LICENSE.md, COPYING, NOTICE
.gitignore, .gitattributes, .gitmodules
AGENTS.md, CLAUDE.md, GEMINI.md, .cursor/rules/*, .github/copilot-instructions.md
CHANGELOG.md, CHANGES.md
.editorconfig, .pre-commit-config.yaml, .lefthook.yml

# Rust
Cargo.toml, Cargo.lock, rust-toolchain.toml, rust-toolchain
deny.toml, .ubsignore, .rchignore, build.rs

# Node / TS / JS
package.json, package-lock.json, pnpm-lock.yaml, yarn.lock, bun.lockb
tsconfig.json, tsconfig.base.json, jsconfig.json
.npmrc.example  (NOT .npmrc)
.eslintrc*, .prettierrc*, vite.config.*, next.config.*, playwright.config.*

# Python
pyproject.toml, setup.cfg, setup.py, requirements*.txt, Pipfile, Pipfile.lock
poetry.lock, uv.lock, hatch.toml, MANIFEST.in
.python-version

# Go
go.mod, go.sum, .golangci.yml, .goreleaser.yaml

# Cloudflare / web
_headers, _routes.json, wrangler.toml
manifest.json, robots.txt, sitemap.xml

# Build / CI
Makefile, Dockerfile, docker-compose.yml, compose.yaml
.dockerignore, .envrc, flake.nix, flake.lock

# Installer + release infra
install.sh, install.ps1, *.spec (when matching pyproject use)
codecov.yml, lighthouse-budget.json
```

---

## Secret leakage

Phase 2.5 runs every time. Real-secret detection requires **both** a filename match and a content fingerprint.

### Filename rules (high-priority — always trip Phase 2.5)

```
# Asymmetric private keys
signing-*.key, *-signing.key
id_rsa, id_rsa.pub  (the .pub is fine BUT the lack of `id_rsa` private alongside is a red flag)
id_ed25519, id_ecdsa, id_dsa
*.pem, *.p12, *.pfx, *.jks, *.keystore
private*.key, *_private.pem

# Cloud credentials
*credentials*.json (excluding .example/.template variants)
service-account*.json, gcp-key*.json
.aws/credentials, aws_credentials*

# .env files (excluding templates)
.env  (NOT .env.example, .env.template, .env.sample, .env.test)
*.env  (when content has K=V values, not placeholders)

# Generic secret-named files
*_secret*, *-secret-*, secret_*
*.token, *_token.txt
.npmrc  (when content has `_authToken=`)
.pypirc  (when content has `password = `)
config.json (when path is at repo root and content has typical cloud token patterns)
```

### Content fingerprints (raise confidence)

A filename hit alone surfaces as `secret-suspect` — surface to user at Phase 5. A filename hit *plus* a content fingerprint match upgrades to `secret-leak` and HALTS the run.

| Fingerprint | Pattern |
|-------------|---------|
| Ed25519 raw seed | exactly 32 bytes, no line terminators, not all printable-ASCII |
| Ed25519 expanded | exactly 64 bytes, similar |
| RSA private | first line `-----BEGIN (RSA )?PRIVATE KEY-----` |
| OpenSSH private | first line `-----BEGIN OPENSSH PRIVATE KEY-----` |
| AWS access key | `AKIA[0-9A-Z]{16}` somewhere in file |
| AWS secret key | `[A-Za-z0-9/+=]{40}` and the file is named `*credentials*` |
| GitHub token | `ghp_[A-Za-z0-9]{36}` or `github_pat_[A-Za-z0-9_]{80,}` |
| Slack token | `xox[baprs]-[A-Za-z0-9-]{10,}` |
| OpenAI API key | `sk-[A-Za-z0-9]{40,}` or `sk-proj-[A-Za-z0-9_-]{40,}` |
| Anthropic API key | `sk-ant-[A-Za-z0-9_-]{40,}` |
| Google API key | `AIza[0-9A-Za-z_-]{35}` |
| GCP service account | JSON with `"type": "service_account"` AND `"private_key": "-----BEGIN`|
| Stripe key | `sk_live_[0-9a-zA-Z]{24}` or `pk_live_[0-9a-zA-Z]{24}` |
| `.npmrc` token | regex `_authToken=[^"\s]{20,}` |

### What's safe (suppress the alarm)

| Pattern | Why safe |
|---------|----------|
| Filename ends `.example`, `.template`, `.sample`, `.test`, `.dist`, `.placeholder` | Template; `YOUR_TOKEN_HERE` content is normal |
| `.mcp.json` with `"Bearer YOUR_BEARER_TOKEN"` | Documented placeholder (mcp_agent_mail pattern) |
| `*.pub` ending with no matching `.key` | Public key alone is safe to publish |
| File is 0 bytes | Stub; not a real secret |
| Content contains only `<placeholder>`, `<your-...>`, `xxxxxxx`, `REPLACE_ME`, `TODO`, `FIXME` | Documented placeholder |
| File is in `tests/fixtures/` and content is clearly a fake (e.g., `signing-test-fake.key` with all-ASCII content like `"test-key-content"`) | Test fixture; flag for confirm but not halt |

### When Phase 2.5 halts

Switch to [INCIDENT-PLAYBOOK.md § Secret Leak](INCIDENT-PLAYBOOK.md#secret-leak-recovery). The playbook covers:

1. Mirror backup
2. User key rotation (skill never auto-rotates; user must do it)
3. `git filter-repo` with the Axiom 16 shallow-clone guard
4. Force-with-lease push to ALL synonym branches (main + master if applicable)
5. `.gitignore` broadening (the leak may have happened despite a pre-existing rule via `git add -f`)
6. `.githooks/pre-commit` install
7. Smoke-test the hook by staging a fake key and confirming the commit is blocked
8. AGENTS.md documentation of the new pre-commit guard

---

## Per-archetype smell adjustments

See [REPO-ARCHETYPES.md](REPO-ARCHETYPES.md) for the full per-archetype protected-globs and "expected" file inventories. Quick examples:

- **Claude skill repo**: `SKILL.md` is *required* at the skill root; `references/`, `subagents/`, `assets/`, `scripts/` directories are normal.
- **Single Rust crate**: `Cargo.toml` + `Cargo.lock` + `rust-toolchain.toml` + `src/` + `tests/` at root.
- **Polyglot monorepo**: `Cargo.toml` AND `package.json` AND `pyproject.toml` may all coexist; treat each subtree by its own archetype rules.
- **Next.js SaaS**: `next.config.js`, `next.config.ts`, `tailwind.config.*`, `postcss.config.js`, `middleware.ts`, `vercel.json` are protected.
- **Cloudflare Pages site**: `_headers`, `_routes.json`, `wrangler.toml` are protected.

---

## "Looks like junk but isn't" — known false-positive patterns

| Filename pattern | Why it might NOT be junk |
|------------------|--------------------------|
| `data/seed.db` (SQLite at non-root) | Often a hand-curated seed for a CLI's first-run experience |
| `tests/fixtures/sample.log` | Regression input |
| `seed/*.json` | Seed data |
| Root-level SQLite that's referenced by a `package.json` build script | Genuine asset (e.g., frankensqlite's `spec_evolution_v1.sqlite3`) |
| `verify` (no extension) at root | Convention for verification entrypoints; reference-grep finds tests + README |
| `*.toml` policy/contract files at root with hardcoded paths in source | Load-bearing config; moving them is a multi-file refactor |
| `<PROJECT>_diagram.webp`, `<PROJECT>_illustration.webp` | Hero images for README; intentional |
| `_headers`, `_routes.json` | Cloudflare Pages routing config |
| `levenshtein_bytes.wasm` (or any `*.wasm` referenced by a build script) | Compiled artifact deliberately tracked |
| `.envrc` | direnv config (NOT a secret; just env var hints) |
| Multiple `*.mcp.json` files at root | Per-tool MCP server configs (Claude / Cline / Codex / Cursor / Gemini / Windsurf) — keep all |
| `gh_og_share_image.png` | OpenGraph share image pinned in `.gitignore` with `!` exception |
| `lighthouse-budget.json` | Performance budget, intentional |
| `codecov.yml` | CI config |

When in doubt, the verdict is `surface-to-user` — never `delete` or `move` based on filename alone.

---

## Additional smells from cass mining (Feb-Apr 2026 sessions)

### Cargo target with custom suffix

| Smell | Examples | Action |
|-------|----------|--------|
| `target-with-custom-suffix` | `target-rch-release/`, `target_mistylark/`, `target-local/`, `target_release/` | delete-and-gitignore + glob `/target-*/`, `/target_*/` |

The standard `/target/` `.gitignore` rule misses these custom-suffixed variants. Source: cass `0d0fea77:96`, `16d6227e:179`, `1d7879eb:agent-aeeea15:1`.

### Profiling artefacts

| Smell | Examples | Action |
|-------|----------|--------|
| `profiling-artifact` | `perf.data` (often huge), `perf.data.old` (cass session F: 2.6 GB), `lcov.info`, `flamegraph.svg`, `--graph-root.svg`, `*.svg` if at root and large | delete-and-gitignore |

Source: cass `26ee0729:agent-a4895f7:44`, `1d7879eb:agent-aeeea15:1`, `03ef995f:agent-aee254f:1`.

### Agent-tooling state

| Smell | Examples | Action |
|-------|----------|--------|
| `agent-tooling-state` | `.br_recovery/`, `.rch/`, `archived_mailbox_states/`, `ci-artifacts/`, `proptest-regressions/`, `test_meminfo` | delete-and-gitignore |

`.br_recovery/` is beads_rust recovery dir; `.rch/` is rch (remote compilation helper) state. Both are agent-tooling ephemera. Source: cass `4f24d3e7:agent-a12c73174cdbfda52:1`, `16d6227e:179`.

### LLM scratch notes

| Smell | Examples | Action |
|-------|----------|--------|
| `llm-scratch-note` | `GEMINI_FIXES_8.md`, `GEMINI_FIXES_9.md`, `<MODEL>_NOTES_<N>.md` | delete-no-gitignore (one-offs) |

LLM-driven research notes that should have been moved to `docs/planning/` if kept; usually not worth keeping. Source: cass `0d0fea77:96`.

### Test-bench DBs

| Smell | Examples | Action |
|-------|----------|--------|
| `test-bench-db` | `bench_*.db`, `bench_*.sqlite3`, `nonexistent_path_xyz.db` (0-byte from invalid CLI flag), `*-test.db` | delete-and-gitignore |

Source: cass `0d0fea77:32`, `26ee0729:agent-a4895f7:44`.

### Compile output at root

| Smell | Examples | Action |
|-------|----------|--------|
| `compile-output-at-root` | `a.out`, `<binary-name>` (matches Cargo bin name; ELF magic), `<binary-name>_test` | delete-no-gitignore |

`a.out` is the classic GCC default output. Source: cass `0d0fea77:96`.

### Numeric-or-shell-escape names

| Smell | Examples | Action |
|-------|----------|--------|
| `numeric-or-shell-escape-name` | `18`, `42`, `7`, `GoldHawk:`, `SilverFox:`, files with `:` in the name | delete-no-gitignore (one-offs) |

These are accidental shell redirections. Files matching `^[0-9]+$` or containing `:` are almost always junk. Source: cass `03ef995f:agent-aee254f:1`.

### Submodule scratch

| Smell | Examples | Action |
|-------|----------|--------|
| `submodule-scratch` | `crates/<name>/python_reference/_scratch/run_*/archive/` and similar | submodule-skip; out of scope |

Submodule subtrees with internal scratch dirs. The skill doesn't traverse INTO submodules. Source: cass `26ee0729:agent-a4895f7:44`.

### Test fixtures stranded at root

| Smell | Examples | Action |
|-------|----------|--------|
| `test-fixture-stranded` | `test_relativize.rs`, `test_hash.rs`, `fs_verification.log` at root | move (to `tests/`) OR delete-no-gitignore (one-off) |

Test files that should be under `tests/` but ended up at root. Source: cass `0d0fea77:32`.

### Editor backup files (extended patterns)

| Smell | Examples | Action |
|-------|----------|--------|
| `editor-backup-extended` | `*.bck.*` (rather than `*.bak`), `.golangci.bck.yml`, `.config.bck.toml`, `*.tmp.<ext>` | delete-and-gitignore + glob `*.bck.*` |

Source: cass `16d6227e:179`.

### Format-patch blobs

| Smell | Examples | Action |
|-------|----------|--------|
| `mailbox-format-patch` | `<repo>_toon_rust.patch`, `*.patch` with mbox magic | delete-no-gitignore |

`git format-patch` outputs left at root. First-line check: `^From [0-9a-f]+ Mon Sep 17 00:00:00 2001$`. Source: cass session D (ntm).

### Phase 2.5 secret-leak — extended categories

Beyond what's in [LEAK-TAXONOMY.md](LEAK-TAXONOMY.md), specific filenames mining sessions surfaced:

| Filename | Note |
|---------|------|
| `signing-*.key` (32-byte raw) | Ed25519 private (the mcp_agent_mail incident pattern) |
| `id_rsa`, `id_ed25519`, etc. without `.pub` companion | SSH private |
| `.env` (without `.example`) | Plain-text env secrets |
| `*credentials*.json` | Cloud creds |
| Files with content matching `BEGIN PRIVATE KEY`, `xoxb-`, `sk-`, `ghp_`, `AKIA[A-Z]{16}`, `AIza[A-Za-z0-9_-]{35}` | Cloud / API tokens |

Even `0-byte placeholder` files matching these patterns are flagged as `secret-suspect` (filename-only) rather than `secret-leak` (filename + content).

---

## Severity column

For prioritization in Phase 5 plan, smells get a severity:

| Severity | Smells |
|----------|--------|
| **Block-the-run** | secret-leak (real secret with content fingerprint), force-add bypass detected |
| **Surface prominently** | secret-suspect (filename-only), phantom-deletion, submodule rewind/dirty, dual-format-asset, vulnerable-file-filter triggered |
| **Standard review** | sqlite-db, planning-doc, multi-llm-plan-cluster, dual-format-asset, scratch-script, runbook-or-recovery |
| **Bulk-confirm** | nohup-leak, skill-output, editor-backup, os-detritus, coverage-output, target-leakage, python-cache, node-modules-leakage, agent-tooling-state, profiling-artifact |
| **Informational** | LLM scratch notes, deprecated-symbol references in docs, format-patch blobs |

The triage-merger uses severity to prioritize Phase 5 review.

---

## Conditional-bundle membership

Each smell rule belongs to one or more conditional bundles per SCOPE-DECISION.md. The bundle is auto-activated based on archetype detection.

| Smell rule | Bundles |
|-----------|---------|
| sqlite-db, sqlite-wal-shm | sqlite_smells |
| skill-output, dot-pre-skill-state | core_smells |
| progress-report, multi-llm-plan-cluster | progress_report_smells, multi_llm_plan_smells |
| planning-doc | planning_doc_smells |
| binary-elf, compile-output-at-root | core_smells |
| python-cache, *.pyc | python_cache_smells |
| node-modules-leakage | node_modules_smells |
| target-leakage, *.rs.bk | rust_artifact_smells |
| *.test (Go), *.out (Go) | go_test_artifact_smells |
| .next/leakage | nextjs_smells |
| nohup-leak, *.log at root | nohup_log_smells |
| editor-backup | editor_backup_smells (always) |
| os-detritus | os_detritus_smells (always) |
| LFS-pointer-mismatch | lfs_smells |
| submodule-rewind, submodule-dirty | submodule_smells |
| .br_recovery/, .rch/ | agent_tooling_smells |
| secret-suspect, secret-leak | secret_smells (always; Phase 2.5) |
| (cross-cutting) | core_smells (always) |
