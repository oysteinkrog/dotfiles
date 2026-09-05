# Source Coverage Map

**Source axiom:** Axiom 22. Every artifact in the workspace carries a provenance header. Every Anti-Pattern, Failure Mode, Operator card, and Smell Tag in this skill traces back to a source — a real session, a sibling skill, an AGENTS.md rule, or a verified git-internals quirk.

This reference is the master provenance index. When extending the skill (adding a new pattern), the new pattern must trace back to a source documented here.

---

## Provenance header (artifact-level invariant)

Every file in `.repo_janitor_workspace/` opens with:

```yaml
---
produced_at: 2026-05-08T17:00:00Z
produced_by: triage-merger
source_phase: 5
confidence: 0.92
inputs_hash: sha256:abc123...
---
```

The header makes "stale artifact mistaken for authoritative" impossible. A fresh agent re-entering the workspace knows exactly what produced what, when, and from what inputs.

---

## Source corpus (master index)

Every pattern in this skill traces to one or more of these sources:

### Sessions (cass-mined)

| Tag | Source | Date | Patterns contributed |
|-----|--------|------|---------------------|
| `apr-27-frankensqlite` | cass session 900368e8...:594-808 | 2026-04-27 | Cat-letter plan format, Cat-C TOML deferral, multi-LLM PLAN clusters, dual-format-asset rule, force-add bypass, 109→45 worked example |
| `apr-27-cass-cleanup` | same session, lines 832-888 | 2026-04-27 | nohup.out smell, .skill-loop-progress.md smell, README inline reference rewrite, docs/reference/ destination |
| `apr-27-pi-agent-rust` | same session, lines 890-970 | 2026-04-27 | optzst ELF binary, findings.jsonl/ubs_*.jsonl smells, storage.sqlite3 dev DB, dual-format `.png`/`.webp`, `verify` script false-positive |
| `apr-27-ntm` | same session, lines 972-1004 | 2026-04-27 | ntm_toon_rust.patch (mailbox-format-patch), .golangci.bck.yml editor backup, command_palette.md runtime fixture, .apr/workflows/ YAML reference rewrite |
| `apr-27-beads-viewer` | same session, lines 1006-1028 | 2026-04-27 | bv_profile/bv_test ELF binaries, coverage_report.txt smell, GOLANG_BEST_PRACTICES.md AGENTS.md inline ref |
| `apr-27-mcp-agent-mail` | same session, lines 1030-1226 | 2026-04-27 | The Ed25519 secret-leak incident; the shallow-clone filter-repo trap; force-add bypass mitigation via .githooks/pre-commit; 793-vs-199 commit history mismatch; force-with-lease push; mirror backup pattern |
| `feb-9-frankensqlite-bd` | cass session 16d6227e...:179 | 2026-02-15 | The "ephemeral detritus" prompt origin; multi-repo cleanup wisdom; disk-pressure pre-flight (49GB /tmp); sqlmodel_rust legacy bd hook bypass; branch-policy registry per-repo; asupersync external-primary-dev rule |
| `feb-21-multi-repo-batch` | cass session 0d0fea77...:96 | 2026-02-21 | 20-repo batch run pattern; commit-skipping logic; concurrent-agent commit races; submodule rewind/dirty/-dirty handling for /data/projects/rust |
| `feb-19-frankenfs-baselines` | cass session 02a0eb47...:1 | 2026-02-19 | Curated artifact directory false-positive (frankenfs/baselines/); dated benchmark snapshots are NOT junk |
| `feb-13-frankenredis-phase2c` | cass session 3c105d10...:1 | 2026-02-13 | Versioned validation framework as artifact directory; distinguishing "artifact" the noun (junk) from "artifact" the noun (curated test fixture) |
| `feb-13-mcp-agent-mail-junk-list` | cass session 03ef995f...:1 | 2026-02-13 | Numerically-named files (`18`, `42`, `7`) and colon-prefixed shell-escape names (`GoldHawk:`) as accidental shell redirections |
| `feb-9-mcp-agent-mail-perf-data` | cass session 26ee0729...:44 | 2026-02-09 | perf.data.old (2.6 GB) at root; nonexistent_path_xyz.db (0-byte SQLite from invalid --db path); _scratch/run_*/archive submodule subdirectories |
| `feb-10-frankentui-prompt` | cass session 1d7879eb...:1 | 2026-02-10 | Comprehensive smell list including target-local/, _scratch/ dirs |
| `feb-8-historical-soldiers-vercel` | cass session 3478dbbc...:1 | 2026-02-08 | Vercel deployment failure due to `vercel-ignore-build.sh` referenced in `vercel.json` after move (proof that move-without-ref-rewrite breaks deployments) |
| `apr-27-frankenterm-phantom` | cass sessions 4f24d3e7...:agent-a71d4204... and agent-a38de5a0... | 2026-04-27 | Phantom-deletion incident: 1,527 missing files NOT staged for deletion; root cause = agent ran extension test that rm-rf'd 5 crate subdirs |

### Sibling skills

| Tag | Source | Patterns inherited |
|-----|--------|---------------------|
| `git-stash-janitor` | sibling skill SKILL.md + 28 references | Phase loop structure; recovery-bundle discipline; byte-equality verification; verbatim-authorization gates; orchestration tiers; polish bar; operator-library form; modes-of-reasoning composition; AGENT-PROMPTS.md template; KEY-INSIGHTS quote pattern |
| `documentation-website-for-software-project` | sibling skill | Multi-phase parallel-subagent pipeline; codebase-archaeology Brennerian opener; three-prompt fresh-eyes loop; resumability discipline; CONTENT-TEMPLATES P1-P8 polish-bar-with-literal-lints |
| `wills-and-estate-planning-skill` | sibling skill | Verification-first overlay (volatile vs evergreen); irreversible-action discipline; recovery-bundle mindset; pre-existing state audit; mode router with 9 modes; tier triage with complexity overlay; CONFIDENCE-SCORING 4-dimension lowest-caps; `phase0_scope_decision.md` pattern; intake INTERVIEW-FLOW; ARCHETYPE-START-PACKS pattern |
| `saas-billing-patterns-for-stripe-and-paypal` | sibling skill | Dry-run/preview-before-mutate ergonomics; idempotent re-runnability; structured triage rubric over noisy real-world data; per-phase artifact manifest with templates; conditional bundle activation table; OPERATING-MODES with mode-handoff template; blast-radius escalator; KICKOFF-PROMPTS per mode; POLISH-BAR with literal verification queries; per-phase Forbidden actions |
| `operationalizing-expertise` | sibling skill | Operator card spec (Definition / Triggers / Failure Modes / Prompt Module / Quote-bank anchors / Sources); operator categorization (Discovery / Testing / Hygiene / Discovery / System); CORPUS.md §n quote-bank format; KICKOFF.md typed contract; CASE-STUDY worked-end-to-end example; FORMATS.md canonical markers; VALIDATION.md gate enumeration; marker-bounded kernel `<!-- KERNEL_START v1.0 -->` |
| `agent-ergonomics-and-intuitiveness-maximization-for-cli-tools` | sibling skill | Description-first triggering; top-5 mistakes table; progressive disclosure with explicit cap (500-2000 token SKILL.md body); SELF-TEST trigger phrases pattern |
| `git-worktree-branch-rationalization` | sibling skill | Skip-list-first principle for multi-target operations; branch-policy registry; force-with-lease over force; per-target health-check (git-doctor) before any mutation |

### AGENTS.md (the user's permanent rules)

| Tag | Source | Patterns |
|-----|--------|----------|
| `agents-rule-0` | AGENTS.md "RULE 0 — THE FUNDAMENTAL OVERRIDE PREROGATIVE" | User authority over skill defaults |
| `agents-rule-1` | AGENTS.md "RULE NUMBER 1: NO FILE DELETION" | Bundle-lifecycle rule (Axiom 13); the "skill never deletes" principle |
| `agents-irreversible` | AGENTS.md "Irreversible Git & Filesystem Actions" | Verbatim authorization gates (Axiom 9); restate command + record auth text rule |
| `agents-no-script-changes` | AGENTS.md "No Script-Based Changes" | Edit-tool-only reference-rewrite policy (Axiom 12; ↪ REWRITE-REFERENCES) |
| `agents-no-file-proliferation` | AGENTS.md "No File Proliferation" | "Edit existing files in place; new files only for genuinely new functionality" applied to the skill's own structure |
| `agents-codex-note` | AGENTS.md "Note for Codex/GPT-5.5" | Working-tree-drift discipline (Axiom 8); "treat concurrent agents' changes as committed-by-self" |
| `agents-landing-the-plane` | AGENTS.md "Landing the Plane" | Push instructions in the handoff; user-owned deployment (Axiom 13) |

### Git internals and tool documentation

| Tag | Source | Patterns |
|-----|--------|----------|
| `pro-git-§2` | Pro Git book §2 (gitignore semantics) | Axiom 6 (`.gitignore` doesn't shadow tracked files); SHADOWING-AUDIT operator |
| `git-mv-rename-detection` | git-mv(1) man page + git-diff(1) rename detection internals | Axiom 5 (move ≠ delete + add); MOVE-WITH-RENAME operator; `diff.renames` config |
| `git-filter-repo-docs` | git-filter-repo project README | Step 4 of secret-leak playbook; shallow-clone caveat (Axiom 16); `--invert-paths --path` syntax |
| `git-lfs-spec` | git-lfs(1) + LFS pointer spec | LFS smudge rule in BUNDLE; pointer-vs-blob distinction |
| `git-submodule-docs` | git-submodule(1) | SUBMODULE-HANDLING.md classification; (rewind) and -dirty marker semantics |

### Built-in operator inheritance

| Operator | Inherited from | Adapted for |
|----------|----------------|-------------|
| `★ INVENTORY` | git-stash-janitor (same glyph) | File-walk + smell-tagging instead of stash listing |
| `🔍 CLASSIFY-PURPOSE` | git-stash-janitor `🔍 FINGERPRINT` (renamed) | Per-file purpose detection vs. per-stash symbol fingerprint |
| `📍 LOCATE-PROPER-HOME` | new (not in stash-janitor) | Inspired by saas-billing's `phase0_scope_decision.md` mode-routing |
| `💎 ASSESS-VALUE` | new | Mirrors wills-and-estate-planning's "is this asset core or vulnerable?" decision |
| `🔗 REFERENCE-GREP` | new (closest analog: stash-janitor `◐ VERIFY-ON-MAIN`) | Adapted for file references rather than stash-symbol presence |
| `🧮 PATTERN-EXTRACT` | new | Inspired by saas-billing's conditional bundle activation table |
| `🛡 SHADOWING-AUDIT` | new (specific to .gitignore mechanics) | Pro Git §2 + cass-mined `*.json` shadowing incident |
| `⬡ BUNDLE` | git-stash-janitor (same glyph, same purpose) | File copies vs. stash diffs |
| `⚠ CONFIRM` | git-stash-janitor (same glyph, same purpose) | AGENTS.md "Mandatory explicit plan" |
| `✦ MOVE-WITH-RENAME` | new | git-mv documentation |
| `↪ REWRITE-REFERENCES` | new | AGENTS.md "No Script-Based Changes" |
| `⊟ REMOVE-WITH-RM` | new (analog: git-stash-janitor `⊙ DROP`) | git-rm semantics |
| `⊕ GATE-RUN` | git-stash-janitor (same glyph, same purpose) | Project's actual quality gates |
| `↺ WORKING-TREE-DRIFT` | git-stash-janitor (same glyph, same purpose) | AGENTS.md "Note for Codex/GPT-5.5" |
| `⌘ HANDOFF` | git-stash-janitor (same glyph, same purpose) | Mode-handoff template addition |
| `◑ VERIFY-LIVE` | wills-and-estate-planning's verification-first overlay | Volatile git behavior |
| `⌖ FALSE-POSITIVE-CHECK` | new | Apr-27 `test_ptr` matching `test_ptrmap_*` incident |
| `⊞ COVERAGE-MATRIX` | saas-billing's `phase2_coverage_matrix.md` | Smell-rule × candidate matrix |
| `⊠ NEGATIVE-DECISION` | wills `OVERLAY-RESOLVER.md` "explicit negative decisions" | Cat C deferral case |
| `⧗ TIME-BOXED-PIVOT` | wills `☍ Disclaimer Window` (the 9-month window) | Phase 9 rollback window |
| `⩚ VULNERABLE-FILE-FILTER` | wills `⩚ Vulnerable-Beneficiary Filter` | Secrets, test fixtures get a different playbook |
| `⟳ CROSS-ARCHETYPE-CHECK` | wills `⟳ Cross-State Domicile` | Multi-archetype repo handling |
| `✸ PIN-THE-CONTRACT` | saas-billing `🧪 PIN-THE-CONTRACT` | Per-fix regression tests |
| `⊙ PROVENANCE-WRAP` | saas-billing `🪟 PROVENANCE` | Artifact headers |
| `⊕ LAYERED-DEFENSE` | saas-billing `⊕ LAYERED-DEFENSE` | Three recovery paths per destructive verdict |

---

## Adding new patterns

When the skill is extended (a new pattern is observed, a new failure mode discovered):

1. **Identify the source.** Was it a real session (cass-mined)? A sibling skill? An AGENTS.md rule? A git-internals quirk?
2. **Cite the source** in the pattern's documentation (operator card, smell rule, anti-pattern, etc.).
3. **Add the source** to this map (under Sessions / Sibling skills / AGENTS.md / Git internals as appropriate).
4. **Add to the QUOTE-BANK** with a §n anchor.

A new pattern without a documented source is a speculative addition; the skill maintainer marks it as such and validates against future runs before promoting.

---

## Why provenance matters

1. **Auditability**. A reader can trace every recommendation to its origin.
2. **Stability**. When a source pattern shifts (e.g., a sibling skill's operator name changes), the impact is traceable.
3. **Calibration**. When a pattern fails in practice, knowing its source helps the maintainer decide whether to soften the rule, find a stronger source, or remove it.
4. **Skill quality**. Patterns with strong provenance (multiple independent sources confirming the same lesson) are more reliable than single-source patterns. The QUOTE-BANK §n entries that have anchors in 3+ sources are the most load-bearing.

---

## Stale source detection

When a source becomes stale (e.g., a sibling skill is removed or substantially refactored, an AGENTS.md rule changes), the maintainer:

1. Marks affected entries with `[STALE — see updated reference]`.
2. Doesn't delete the original (audit trail).
3. Adds a new entry citing the updated source.
4. Updates dependent operators / patterns / axioms to cite the new entry.

The QUOTE-BANK has the same stale-detection convention.

---

## When to add to this map

Every reference file's "Source:" or "Sources:" line should ultimately point to an entry here. If a reference cites a source not in this map, either:

- The source is too informal (a single conversation; a guess) — strengthen with a real reference, OR
- The source is real but not yet documented — add it here.

This is the contract: every "Source: X" line in the skill points to a verifiable line in this file.
