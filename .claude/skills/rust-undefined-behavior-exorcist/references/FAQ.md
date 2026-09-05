# FAQ — Common Questions

For "is this the same as `/rust-unsafe-code-exorcist`?" see [BOUNDARIES.md](BOUNDARIES.md). For "how do I compose with `/X`?" see [INTEGRATIONS.md](INTEGRATIONS.md). For "what does <term> mean?" see [JARGON.md](JARGON.md).

---

## Q: My project has zero `unsafe`. Should I still run this skill?

**A:** Yes, if any of these apply:
- Your project has safe-code invariant drift (`Hash`, `Eq`, `Ord`, `Iterator::size_hint`) near unsafe code or public APIs. These are usually logic bugs by themselves, not UB, but they can become soundness issues when unsafe code assumes the invariant.
- Your project implements unsafe traits or exposes types consumed by unsafe code in dependencies.
- Your project uses tokio or any async runtime and has a `Drop` impl that calls into a blocking API (usually liveness/cancellation risk, UB only if it violates an unsafe contract).
- Your project depends on a crate with `unsafe` whose API surface is reachable from yours.

A `#![forbid(unsafe_code)]` crate can still participate in a UB chain through unsafe dependencies or unsafe trait contracts. Run Quick mode (Phases 1–4) for an initial triage; pure safe-code invariant bugs should be reported as correctness findings unless an unsafe boundary depends on them.

## Q: My project has Miri CI already. Do I need this skill?

**A:** Miri CI catches what Miri catches — typically a subset of UB. This skill adds:
- The MIRIFLAGS matrix (default / tree-borrows / strict-provenance / symbolic-alignment), not just one config
- Sanitizers (ASan / TSan / MSan / LSan) that catch native + FFI cases Miri can't run
- Loom + shuttle for concurrent code where Miri's interleaving coverage is shallow
- Project-shaped UB techniques via `/idea-wizard` Phase 6
- Unsafe trait and library-contract invariants, plus safe-code invariant drift (`Hash`/`Eq`, `size_hint`) that may deserve remediation even when it is not UB

If your CI is already running the full matrix + sanitizers + loom + fuzz, run W4 (Already-Mature Crate) workflow — it's a ¼-day re-audit focused on the *new* surface since the last audit.

## Q: How long does a Standard-mode run actually take?

**A:** Wall-time breakdown for a moderate-complexity project (e.g., 10 crates, ~50K LOC, some FFI):

| Phase | Wall time | Notes |
|---|---|---|
| 0 Bootstrap | 10–20 min | Includes toolchain detection + user confirmations |
| 1 RECON | 20–40 min | Parallel per module |
| 2 STATIC | 30–60 min | Parallel per bucket; some buckets N/A |
| 3 DYNAMIC | 1–3 h | Parallel per tool; Miri matrix is the bottleneck |
| 4 SYNTHESIS | 30–45 min | Single agent |
| 5 EXPERIMENTS | 30–90 min | Parallel per OPEN experiment |
| 6 IDEA-WIZARD | 20–30 min | /idea-wizard runtime |
| 7 ITERATE | 6–10 rounds × 30–45 min each | The bulk |
| 8 REMEDIATION | 30–60 min | Includes triangulation for high-stakes |
| 9 BEADS | 60–120 min | Polish-heavy |
| 10 FRESH EYES | 45–90 min | The three prompts, twice each |
| **Total** | **~half day** | Roughly 6–8 hours wall time |

For Exhaustive mode, add Phase 11 soak (1–3 days, dispatched via `rch`). Quick mode finishes in 1–2 hours but only covers Phases 1–4.

## Q: I got a Miri error. Where do I start?

**A:** Skip to operator `✦ ISOLATE`. The Miri error already gives you a confirmed UB site. Then:
1. Copy the Miri reproducer from the error trace into `experiments/EXP-001/repro.rs`
2. Reduce it (operator `✦ ISOLATE` again)
3. Confirm under all four MIRIFLAGS configs (operator `⬡ INSTRUMENT`)
4. Design the remediation (operator `⊕ REWRITE`)

This is the [W6 Incident Response](WORKFLOWS.md#w6--incident-response) workflow. Total time: 4–8 hours.

## Q: My team doesn't have anyone who understands `Pin`. Is this skill still usable?

**A:** Yes. The skill's job is to find the UB, prove it empirically, and design the remediation. The bead graph is then handed off to your team. If `Pin` understanding is the bottleneck for a specific finding:
- Add `/multi-model-triangulation` (operator `⚠ ESCALATE`) for that finding
- Use Kani / Prusti / Creusot directly for formal verification (operator `⊢ PROVE`)
- The chosen remediation may sidestep `Pin` entirely (e.g., arena + index instead of self-ref)

The skill doesn't *require* the team to understand the Rustonomicon — it documents the invariants in the SAFETY comments per [INVARIANT-CATALOG.md](INVARIANT-CATALOG.md).

## Q: How do I run just the static sweep without the dynamic phase?

**A:** Run Quick mode (Phases 1–4 only). Phase 3 dynamic sweep can be skipped if you don't have nightly Rust installed; Phase 4 synthesis will note `phase3_dynamic_findings.md = SKIPPED` and proceed. The output is a triage-grade report — useful but not audit-grade.

Or directly: `scripts/ast-grep-ub-patterns.sh <source>` runs just the static sweep.

## Q: Can this skill audit code I don't own (a transitive dependency)?

**A:** Yes — see [BOUNDARIES.md §With dependency-soundness mode](BOUNDARIES.md). Run the soundness-surface analysis: which dep-unsafe is reachable from *your* public API? You can't fix the dep, but you can:
- Document the soundness risk
- File an upstream issue
- Wrap the dep's unsafe surface in a typed boundary
- Pin the dep at a version with known-good soundness posture

## Q: Does this skill work for `no_std` projects?

**A:** Yes. See [PROJECT-TYPES.md §P4 Embedded `no_std`](PROJECT-TYPES.md). Miri runs on `no_std` code as long as the test harness compiles (you may need a `panic_handler` for tests). Sanitizers are Linux-x86_64 only; for embedded targets, `qemu-system-*` testing complements but doesn't replace the audit.

## Q: How do I migrate findings from a previous audit?

**A:** If you ran this skill before and have `phase4_unified_findings.md` from a prior run, Phase 1 of the new run reads it as the baseline. Findings that persist get re-checked; findings that were CONFIRMED_UB and are no longer reachable get marked as `RESOLVED` (a new verdict added in this case). The convergence loop only counts net-new findings.

## Q: Can I run this skill against a git URL directly?

**A:** Yes. Phase 0 accepts a URL; the orchestrator clones into `/tmp/<basename>` first. The workspace is created inside that temporary clone at `/tmp/<basename>/.ub-exorcism/<run-id>/` unless you override to another in-project path.

## Q: What if the audit finds CVE-grade UB in a public crate?

**A:** Follow [DISCLOSURE.md](DISCLOSURE.md) — coordinate disclosure via RustSec, file with the crate's maintainer first, then advisory. This skill produces the technical reproducer; the disclosure process is human-led.

## Q: How does this skill handle macro-generated unsafe?

**A:** Phase 1's `unsafe-surface-mapper` runs `cargo expand` and re-scans the expanded output for unsafe blocks not present in the source. Macro-generated unsafe is tagged `MACRO_GENERATED` and routed to Phase 2's normal bucket sweepers, plus a "macro origin" cross-reference.

## Q: What about `proc-macro` crates themselves?

**A:** Treat them as P2 Binary CLI — they're code that runs at compile time. Their unsafe (if any) executes in `rustc`'s process. Audit the same way; the consequences of UB are different but the bucket analysis is the same.

## Q: My CI doesn't have `rch` workers. Can I still do Exhaustive mode?

**A:** Yes, but you'll need a long-running machine of your own. Phase 11 soak campaigns can run locally; you just lose the offload benefits. Set up a dedicated machine for the campaigns and treat it like rch.

## Q: How do I stop the loop early if I'm confident the project is clean?

**A:** The convergence floor is **archetype-aware** (see [CONVERGENCE.md §Archetype-aware round floor](CONVERGENCE.md#archetype-aware-round-floor)):

- **Unsafe-touching crate, Standard or Exhaustive:** floor = 10 rounds. Non-negotiable. The floor exists because early termination correlates with missed findings.
- **Pure-safe (`#![forbid(unsafe_code)]`) crate, Standard:** floor = 3 rounds. The lower floor is justified because 19 of 25 UB-taxonomy buckets are structurally inapplicable.
- **Pure-safe crate, Exhaustive:** floor = 5 rounds (3 idea-wizard lenses + 2 confirm-clean).
- **Quick mode (any archetype):** Phase 7 is not run.

The archetype is declared in `phase0_run.json` at the start of the run and gets upgraded if Phase 1 discovers any `unsafe` in code that was claimed forbid-unsafe.

If you want an even faster pass, use Quick mode (phases 1-4 only). Total wall time for an unsafe-touching project at floor=10 is typically 6-8 hours; for a pure-safe project at floor=3 it's typically 1-2 hours.

## Q: Where do I put per-project priors (e.g., "skip the `legacy/` subdir")?

**A:** Add a `.ub-exorcism.toml` at the project root:

```toml
[scope]
exclude = ["legacy/**", "vendor/**"]
include_paths = ["src/**", "crates/*/src/**"]

[priors]
archetype = "P3+P7"  # workspace + FFI; pre-loads those bucket priors
mode = "Standard"
offload = "rch"

[soak]
fuzz_targets_24h = ["fuzz_parse", "fuzz_codec"]
miri_full_matrix = true
loom_iters = 100000
```

Phase 0 reads this file and embeds it into `phase0_run.json`.

## Q: How does this skill handle the "other agents working concurrently" situation?

**A:** Per AGENTS.md, other agents' untracked files are treated as if you made them — never disturbed. The skill creates files only inside `<source>/.ub-exorcism/<run-id>/` and only modifies `.beads/` in the source repo with explicit user permission. No other source file is touched without authorization.

The MCP Agent Mail reservations (`tool://miri/<config>`, `tool://loom`, etc.) coordinate with peer agents who may also be running the skill in parallel against different sections of the workspace.

## Q: What if I disagree with the chosen remediation?

**A:** Phase 8 records ≥2 candidates with rubric scores. The "chosen" one is just the highest-scored. The runner-up section preserves the alternative + tradeoffs. You can:
- Edit `phase8_remediation_plan.md` to swap chosen ↔ runner-up
- Adjust the rubric scores (with rationale) to reflect your priorities
- Add a third candidate the skill didn't enumerate

Phase 9 then converts whatever's chosen into beads. The audit trail (runner-ups + rubric) is preserved so future maintainers see the alternatives.

## Q: How do I keep the skill itself up-to-date as Rust evolves?

**A:** The Track-A corpus is the version-locked source of truth. As Rust changes:
- New UB shapes → add a bucket in [UB-TAXONOMY.md](UB-TAXONOMY.md)
- New tools (e.g., a hypothetical `cargo-miri-cuda`) → add to [TOOLING.md](TOOLING.md)
- New `MIRIFLAGS` → add to the matrix in `scripts/run-miri-matrix.sh`
- New stable APIs that obsolete unsafe (e.g., `AtomicU64::from_ptr` in Rust 1.84) → add to [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md)

The Kernel ([corpus/specs/triangulated_kernel.md](../corpus/specs/triangulated_kernel.md)) is intentionally stable; major Rust changes might trigger an invariant revision.

## Q: How does this skill differ from `cargo-careful`?

**A:** `cargo-careful` is one tool the skill uses — it builds + runs the test suite with extra runtime safety checks (assert on raw-pointer alignment etc.). It's a *runtime-debug-mode* helper. This skill is a *full audit methodology* that uses `cargo-careful` as one of many detectors.

## Q: Can the skill actually FIX the bugs it finds, or does it just report them?

**A:** Both, but fixing is opt-in. By default the skill stops at Phase 12 with `FINAL_UB_REPORT.md` + `UB_RUNBOOK.md` + a polished bead graph — that's the diagnostic deliverable. At the close of Phase 12 the agent asks you explicitly: "Do you want me to execute the remediation plan I just designed?" If you answer yes, Phase 13 (`remediation-executor` subagent per ready bead) walks through `br ready` and:

1. Implements each bead's chosen remediation from `phase8_remediation_plan.md`
2. Runs the regression test for that bead (must transition pre-FAIL → post-PASS)
3. Runs the gates (`cargo check`, `cargo clippy -D warnings`, `cargo fmt --check`, the project's Miri config from `UB_RUNBOOK.md`)
4. If everything passes, closes the bead and commits a focused diff
5. If anything fails, tries the runner-up remediation; on second failure leaves the bead `in_progress` with `phase13-needs-human-review`

Phase 13 explicitly does NOT push to remote, does not bypass hooks, does not delete files, does not run destructive git. See [PHASES.md §Phase 13](PHASES.md#phase-13-optional-auto-remediation--execute-the-plan) for the full rule list, and [VALIDATION.md §Phase 13](VALIDATION.md#phase-13--auto-remediation-gates-opt-in-skip-if-phase-13-was-not-run) for the exit gates.

If you'd rather hand off to humans, just answer "no" to the prompt — the polished bead graph is ready for `br ready` and your team picks up from there.

## Q: Can the skill auto-install missing toolchain pieces?

**A:** Yes — Phase 0 explicitly offers it. After running `install-toolchain.sh --inventory-only`, the agent presents three choices: (a) auto-install everything missing via `--yes`, (b) interactive per-tool TTY prompt, or (c) skip and degrade. The default is (b), but if you've already said "install whatever you need" or similar, the agent picks (a). The script runs a per-tool smoke test (`cargo +nightly miri --version`, etc.) after every install and flags any "installed but broken" tools so a successful `cargo install` doesn't mask a broken component.

## Q: Can I use this skill to audit OSS crates I depend on, before pulling them in?

**A:** Yes. Clone the crate, run Quick mode (Phases 1–4) for a triage in 1–2 hours. The output tells you:
- How much `unsafe` surface
- What buckets are present
- Whether the maintainer documents SAFETY contracts
- Whether the crate has Miri CI / loom / fuzz

Use this as input to dependency selection.
