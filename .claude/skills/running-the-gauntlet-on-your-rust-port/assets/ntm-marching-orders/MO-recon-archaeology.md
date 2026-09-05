# MO-recon-archaeology.md — Phase 1 Surface Archaeologist (Per Crate)

**Phase:** 1 (RECON)
**Parameters:** `<PANE_N>`, `<ROLE>`, `<MODEL>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`, `<PORT_PATH>`, `<CRATE>`, `<REFERENCE_VERSION>`, `<COORDINATION_MODE>`, `<THREAD_ID>`, `<OUTPUT_PATH>`

---

You are pane `<PANE_N>` (model `<MODEL>`) in the gauntlet swarm `<SESSION_ID>`, dispatched as a **surface-archaeologist** for crate **`<CRATE>`** of the target port at `<PORT_PATH>`.

Your output is `<OUTPUT_PATH>` — typically `<WORKSPACE_PATH>/phase1_recon_<CRATE>.md`. Do not write anywhere else without posting to the thread first.

**Step 1 — Read the governing instructions.**

Read `<PORT_PATH>/AGENTS.md` if present, else the nearest repository-level `AGENTS.md` that governs the workspace. Read `<WORKSPACE_PATH>/AGENTS.md` for the gauntlet's mandate paragraph (negative-ledger discipline, cass-mining requirement, etc.). Note which files you used in your ack.

**Step 2 — Read the gauntlet's archaeology context.**

Read:

- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/PHASES.md` § Phase 1
- `~/.claude/skills/running-the-gauntlet-on-your-rust-port/references/THREE-PILLARS.md` (for the pillar lens you should apply per section)
- `~/.claude/skills/codebase-archaeology/SKILL.md` if present (helper skill; falls back to inline procedure below)

**Step 3 — Register Agent Mail identity (if `<COORDINATION_MODE>` is `agent-mail`).**

```text
ensure_project(human_key="<WORKSPACE_PATH>")
register_agent(
  project_key="<WORKSPACE_PATH>",
  program="<your-cli-program-name>",
  model="<your-model-or-family>",
  task_description="gauntlet <SESSION_ID> pane <PANE_N> phase1 recon crate=<CRATE>"
)
```

Use the concrete CLI program name (`claude-code`, `codex-cli`, `gemini-cli`). Record the returned name in your ack as `p<PANE_N> -> <agent-mail-name>`.

If `<COORDINATION_MODE>` is `ntm-inbox`: skip Agent Mail; your identity is your pane id.

**Step 4 — Acknowledge dispatch on the assigned thread.**

Post on `<THREAD_ID>` (= `gauntlet-<SESSION_ID>-phase1-recon-<CRATE>`):

```
Subject: [<SESSION_ID>] Phase 1 recon dispatch ack — crate=<CRATE>, pane=<PANE_N>, model=<MODEL>
Body:
  Pane: <PANE_N>
  Role: <ROLE>
  Crate: <CRATE>
  Reference: <REFERENCE_VERSION>
  Output target: <OUTPUT_PATH>
  Started: <UTC timestamp>
```

**Step 5 — Reserve the per-crate scope.**

Reserve `tool://surface-archaeology-<CRATE>` via Agent Mail (exclusive, TTL 90 min):

```text
reserve(
  paths=["<PORT_PATH>/crates/<CRATE>/"],
  scope="tool://surface-archaeology-<CRATE>",
  ttl_seconds=5400,
  reason="gauntlet phase1 recon"
)
```

If the reservation is held by another agent (rare; cross-lane), post to the thread with `BLOCKED_ON: tool://surface-archaeology-<CRATE>` and wait for release.

**Step 6 — Do the archaeology.**

Produce `<OUTPUT_PATH>` with EXACTLY these four sections (other sections are fine to add at the end):

### Section A: Public surface table

For `<PORT_PATH>/crates/<CRATE>/`, enumerate:

- `pub fn` — every public function with its signature
- `pub struct` — every public struct with its fields
- `pub trait` — every public trait + methods
- `pub macro` / `pub macro_rules!` — every exported macro
- `pub use` — every re-export
- `pub const` / `pub static` — every public constant
- `#[no_mangle]` / `extern "C"` — every FFI symbol
- (Class-specific) `#[command]`, `#[pyfunction]`, `PRAGMA <name>`, `Opcode::<name>`, etc.

Use `rg`/`ast-grep`/`syn-walker` (see `scripts/syn-walkers/` and `scripts/ast-grep-surface-patterns/`). Do NOT eyeball with cat. The full file list is too large for context; grep first, then read targeted slices.

### Section B: Perf surface

Enumerate hot paths and perf-sensitive sites:

- `#[inline]` / `#[inline(always)]` / `#[hot]` annotations
- Identified `hot_path` or `fast_path` patterns
- Dispatch sites (`match` over opcodes, type-tag enums, command names)
- Allocation sites (`Box::new`, `Vec::with_capacity`, `String::from`, `clone()` in tight loops)
- Lock-acquisition sites (Mutex, RwLock, parking_lot)
- Atomic-operation sites (`AtomicBool`, `AtomicUsize`, fences)

For each, note the file:line and the surrounding 3-5 lines of context.

### Section C: Conformance surface

Every place where behavior could plausibly diverge from `<REFERENCE_VERSION>`:

- Floating-point arithmetic (NaN handling, denormals, FMA usage)
- Integer overflow handling (`wrapping_*` vs `checked_*` vs `saturating_*`)
- NULL/None/undefined semantics
- Sort ordering / stability
- Iteration order (HashMap vs BTreeMap; `HashSet` is non-deterministic)
- Error-message strings (where the reference emits a specific phrase)
- RNG seeding and reproducibility
- Endian assumptions
- Locale-sensitive operations
- (Class-specific) PRAGMA defaults, autocommit semantics, foreign-key cascade, RESP3 vs RESP2 framing, gradcheck-relevant operators, HTTP header case-insensitivity

### Section D: Reference-mapping table

A table with one row per `<REFERENCE_VERSION>` public symbol that this crate is plausibly responsible for. Columns:

- `reference_symbol` — exact name in `<REFERENCE_VERSION>`
- `port_location` — file:line in this crate where it's implemented (or empty if not implemented here)
- `status` — `present` | `partial` | `missing`
- `notes` — partial reasons; FIXME callouts; intentional deviations

If a reference symbol is implemented in a DIFFERENT crate, leave the row empty here — the synthesizer step will dedup and pick the canonical home.

**Step 7 — Class-specific addendum.**

Read `<WORKSPACE_PATH>/phase0_project_class.json` to learn the project class. Add a "Class addendum" section with these specifics:

- **SQL-class**: enumerate every PRAGMA touched, every Opcode dispatched, every TCL-test-relevant code path.
- **RESP-class**: enumerate every `pub const COMMAND_<name>`, every RESP3 type emitted, every persistence (RDB/AOF) hook.
- **Numerical-Python-class**: enumerate every `#[pyfunction]`, every PyArg conversion path, every `numpy.<ufunc>` analog.
- **ML-System-class**: enumerate every autograd Op, every device-dispatch path, every `torch.use_deterministic_algorithms`-sensitive call.
- **HTTP-Protocol-class**: enumerate every route handler, every middleware, every OpenAPI schema fragment generated.

**Step 8 — Negative-ledger pre-flight.**

Before declaring an apparent gap, grep:

```bash
grep -F "<reference_symbol>" "<WORKSPACE_PATH>/docs/progress/surface-deferrals.md" || true
grep -F "<reference_symbol>" "<WORKSPACE_PATH>/docs/progress/conformance-negative-results.md" || true
```

If the symbol is in `surface-deferrals.md` with a `retry_condition`, mark it `excluded` not `missing` in your Section D table, and cite the deferral row.

**Step 9 — Ship-or-surface SLA.**

You have **90 minutes**. Within that window, either:

- Commit `<OUTPUT_PATH>` with all four sections + class addendum.
- OR post a `BLOCKED` message on `<THREAD_ID>` naming the specific blocker (missing dependency, can't reach the reference source, a syn-walker that crashed on a specific file).

No prose mental models, no "exemplary" self-reviews. Either the file lands or the blocker is named.

**Step 10 — Acknowledge completion.**

When `<OUTPUT_PATH>` is committed, post on `<THREAD_ID>`:

```
Subject: [<SESSION_ID>] Phase 1 recon DONE — crate=<CRATE>
Body:
  Output: <OUTPUT_PATH>
  Public surface count: <N>
  Reference-mapping coverage: <P>%
  Open gaps surfaced: <G>
  Class addendum: yes/no
  Duration: <wall time>
```

**Step 11 — Universal gauntlet rules.**

1. **No file deletion** without explicit user permission.
2. **No destructive git** (`git reset --hard`, `git clean -fd`, `rm -rf`) without explicit operator authorization.
3. **No editing files outside `<WORKSPACE_PATH>` and `<PORT_PATH>/crates/<CRATE>/`** without a reservation that names the scope.
4. **Other agents' edits are normal** — if `git status` shows files you didn't touch, another archaeologist edited them. Do NOT stash or revert. Read and build on.
5. **No bare `cass` / `bv` / `cargo bench` / `cargo test --workspace` in this dispatch** — use `cass --robot`, `bv --robot-*`, `cargo test -p <port>-<crate>`, `cargo bench --bench <one>`.

---

**Reply with:** `Pane <PANE_N> ready, role=<ROLE>, crate=<CRATE>, output=<OUTPUT_PATH>` — that's all the orchestrator needs.
