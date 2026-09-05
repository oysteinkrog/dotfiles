# SKILL-FALLBACKS.md — Inline Fallbacks for Missing Skills

This skill is designed to compose with other local coding-agent skills. If any referenced skill is missing, the run still proceeds — every referenced skill has an inline fallback playbook here.

The orchestrator detects missing skills via `scripts/check-skills.sh` in Phase 0.5. For each missing skill, it picks one of:

1. **Offer `jsm install <skill-name>`** if `jsm` is installed + authenticated.
2. **Use the inline fallback** below.
3. **Mark the dependent operator as skipped** in `phase0_skill_inventory.json` with explicit rationale.

---

## Where helper skills come from

This skill (and every skill it references) is distributed via the **Jeffrey's Skills** ecosystem:

- **Registry / website** — https://jeffreys-skills.md — browses available skills, shows their docs, links to source.
- **`jsm` installer CLI** — installs / updates / removes skills. Install location depends on the `jsm`/runtime configuration; common local skill directories are `~/.claude/skills/<name>/` and `~/.codex/skills/<name>/`. Auth is one-time via `jsm login` (OAuth).
- **Skill source repos** — each skill lives in its own repo. The author publishes versions; `jsm` pulls the latest stable.
- **`jsm` itself** — installs via `curl -fsSL https://jsm.sh/install.sh | sh` (or via Homebrew if on macOS).

A skill is a directory containing at minimum a `SKILL.md` (frontmatter +
agent-facing prose). Optional package layers include `subagents/`, `scripts/`,
`assets/`, and `references/`. Consuming skills happens through the agent's local
skill loader; no private authoring skill is required at audit runtime.

For the audit's purposes, each referenced helper skill is optional. The inline
fallbacks below are the audit's degradation path. If you want the full integrated
experience, `jsm install` the missing skills.

---

## `/operationalizing-expertise` — not needed at runtime

This skill IS a Track A artifact of /operationalizing-expertise. The methodology is baked in. No runtime call.

---

## `/codebase-archaeology`

**Used in.** Phase 0.5 exemplar-miner (reads exemplar repo history).

**Inline fallback.**
```bash
# Per exemplar repo, run:
git -C <repo> log --all --grep='unsafe\|miri\|loom\|UB\|soundness' --oneline | head -20
# For each top commit:
git -C <repo> show <hash>
# Read README.md, AGENTS.md, .beads/ if present.
ast-grep run -l Rust -p 'unsafe { $$$ }' <repo>/src | head -30
```

The fallback produces a less-structured but functionally-equivalent exemplar pattern catalog. Save to `<audit-dir>/phase0_exemplar_patterns.md`.

---

## `/codebase-report`

**Used in.** Phase 1 enumeration (for understanding the project's structure before the inventory).

**Inline fallback.**
```bash
cargo metadata --format-version 1 | jq '.workspace_members'
find <project> -name "Cargo.toml" -exec dirname {} \;
tokei <project>                       # if installed; otherwise: find <project>/src -name '*.rs' | wc -l
tree -L 3 <project>/src
cargo +nightly geiger --output-format Json
```

Output to `<audit-dir>/phase0_project_structure.md`.

---

## `/extreme-software-optimization`

**Used in.** Phase 5 (B)-classified sites — for the criterion + hyperfine + flamegraph protocol.

**Inline fallback.** See [20-SIMD-AND-PERF.md § Measurement protocol](../patterns/20-SIMD-AND-PERF.md). The bench protocol is fully specified there; the skill is referenced for additional optimization patterns the audit might propose.

---

## `/multi-pass-bug-hunting`

**Used in.** Phase 7 fresh-eyes (the three verbatim review prompts come from there).

**Inline fallback.** The three prompts are pasted verbatim into [SKILL.md § Phase 7 fresh-eyes prompts](../../SKILL.md) — no skill call required. The orchestrator emits each prompt in sequence.

---

## `/multi-model-triangulation`

**Used in.** Phase 6 adversarial reclassification + Phase 7 fresh-eyes + Phase 10 maintainer-empathy on highest-risk sites.

**Inline fallback.** Run the Claude pass twice with different priming (literal-reader vs adversarial-reader vs junior-engineer-reader). It's lower-signal than true cross-model but better than nothing. See [TRIANGULATION.md § Single-model fallback](TRIANGULATION.md).

If the user has API keys for OpenAI / Gemini / xAI but `/multi-model-triangulation` is not installed, the fallback is to use those API keys directly via curl + `jq`. Documented in [TRIANGULATION.md § Manual multi-model](TRIANGULATION.md).

---

## `/idea-wizard`

**Used in.** Phase 10 — alternative refactor strategies.

**Inline fallback.** Spawn a fresh Claude agent with the prompt from [AGENT-PROMPTS.md § idea-generator](AGENT-PROMPTS.md). The prompt itself implements the /idea-wizard methodology.

---

## `/beads-workflow`

**Used in.** Phase 8 bead conversion.

**Inline fallback.** If `br` (beads_rust) is installed but the skill isn't, follow the bead shape in [PHASES.md § Phase 8](PHASES.md#phase-8--bead-conversion--commit). The skill's actual value-add is the markdown-plan-to-bead transformation patterns; the inline version is mechanical: per cluster, emit `br create` commands.

If `br` itself isn't installed:
```bash
cargo install beads_rust
```
The skill assumes `br` is available. If not, the orchestrator stops at Phase 8 and asks the user to install.

---

## `/beads-br`, `/beads-bv`

**Used in.** Phase 8 (br) + Phase 10 reading bead history (bv).

**Inline fallback.** The commands are documented in AGENTS.md § Beads (br) and § bv. No skill required to use `br create / br dep add / bv --robot-triage`.

---

## `/ubs`

**Used in.** Phase 1 enumeration (additional pattern detection).

**Inline fallback.** Skip the `ubs` row in the inventory if not installed. Note in `phase0_skill_inventory.json § skipped`.

If `ubs` binary is installed but the skill isn't, just run `ubs --only=rust src/` per crate.

---

## `/agent-mail`

**Used in.** Cross-agent coordination throughout.

**Inline fallback.** If MCP Agent Mail isn't running, fall back to a single-agent serial workflow. Skip the parallelism in Phase 1, Phase 5, Phase 6, Phase 7. The audit takes longer but produces the same output.

If `mcp-agent-mail` is installed but the skill isn't, use the MCP tools directly (the agent has access to them). Documented in AGENTS.md § MCP Agent Mail.

---

## `/cass`

**Used in.** Phase 0.5 cass-miner.

**Inline fallback.** Skip Phase 0.5 mining; rely entirely on the exemplar-miner reading source / git / beads. The audit is slightly less informed but no other phase depends on cass output.

If `cass` binary is installed but the skill isn't, use it directly per the query pack in [CASS-MINING.md](CASS-MINING.md).

---

## `/testing-real-service-e2e-no-mocks`

**Used in.** Phase 5 equivalence-prover (when the (C) rewrite is reachable from an integration test).

**Inline fallback.** Write integration tests manually using `tokio::test` (or sync `#[test]`) that exercise the rewrite end-to-end. The skill's value-add is the structured-logging + factory patterns; the inline fallback is "just write the test."

---

## `/testing-metamorphic`

**Used in.** Phase 5 equivalence-prover (metamorphic invariants).

**Inline fallback.** Use plain `proptest` with explicit transform functions. The metamorphic pattern is:

```rust
proptest! {
    #[test]
    fn metamorphic_invariant(x: i64) {
        let y = transform(x);
        prop_assert_eq!(f_safe(transform(x)), transform(f_safe(x)));
    }
}
```

Pick a non-trivial `transform` (e.g., for a sort: reverse-then-sort vs sort-then-reverse-then-reverse). The skill provides more transforms / patterns; the inline fallback covers basic cases.

---

## `/testing-fuzzing`

**Used in.** Phase 7 toolchain run.

**Inline fallback.** Use `cargo-fuzz` directly per [TOOLCHAIN-RUNBOOK.md § cargo-fuzz](TOOLCHAIN-RUNBOOK.md#cargo-fuzz). The skill provides additional patterns (structured `arbitrary` derives, dictionary inputs); the inline fallback uses raw `&[u8]` targets.

---

## `/testing-conformance-harnesses`

**Used in.** Phase 9 verify.sh harness construction.

**Inline fallback.** The verify.sh template at `assets/verify.sh.template` is fully specified. No skill call required.

---

## `/deadlock-finder-and-fixer`

**Used in.** Phase 6 adversarial when concurrency-touching (C) rewrites are under attack.

**Inline fallback.** Use `loom` directly per [TOOLCHAIN-RUNBOOK.md § loom](TOOLCHAIN-RUNBOOK.md#loom) + manual review of every `.await` + lock interaction in the rewrite. The skill provides additional checklist items; manual review covers the basics.

---

## `/extreme-software-optimization`

**Used in.** Phase 5 (B) plans — bench protocol.

**Inline fallback.** See [20-SIMD-AND-PERF.md § Measurement protocol](../patterns/20-SIMD-AND-PERF.md). Fully self-contained.

---

## `jsm` not installed at all

If the user doesn't have jsm and doesn't want it, the orchestrator skips skill installation entirely. Every referenced skill has an inline fallback above. The audit proceeds.

The orchestrator notes in `phase0_skill_inventory.json`:
```json
{
  "jsm_installed": false,
  "jsm_authenticated": false,
  "missing_skills": ["...", "..."],
  "fallback_strategy": "inline",
  "missing_skill_offer_made": false
}
```

---

## Why the inline fallbacks exist

The audit's value comes from the PROCESS — first-principles classification, polish bar, adversarial reclassification, the toolchain harness. The supporting skills are accelerators, not gates. A user without `/multi-model-triangulation` still gets a defensible audit; just one with single-model risk.

That said: where multi-model triangulation IS available, the highest-risk sites benefit enough that it's worth installing. The orchestrator's `phase0_skill_inventory.json § recommendations` flags which missing skills would have the highest marginal impact for this specific run.
