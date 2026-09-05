# Harmonization — Deep Dive Into the Synthesis Algorithm

> **Read [HARMONIZATION.md](HARMONIZATION.md) first.** That file establishes *why* harmonization exists and *what* the variant matrix looks like. This file goes deeper into *how* the synthesis is mechanically derived from the matrix — the hunk dependency graph, AST-aware merging, semantic deduplication, refactor-vs-feature distinction, the dependency order of defensive checks, and what happens when synthesis fails gracefully.

> **The cognitive frame.** The synthesis is *not* an artifact the planner produces by inspiration. It is the deterministic output of an algorithm operating on the variant matrix. The algorithm has steps. Each step has invariants. When invariants are violated, the algorithm halts and surfaces the failure to the user — it never patches over a violation by guessing.

> **Why a deep dive:** [HARMONIZATION.md §6](HARMONIZATION.md#6-the-synthesis-discipline-how-synthesis-actually-lands) says "synthesis lands via the Edit tool, not sed/awk." Per AGENTS.md "No Script-Based Changes." But the *plan* the agent applies via Edit must itself be derived from a defensible algorithm — otherwise the synthesis is just a plausible guess. This file is that algorithm.

---

## 1. The Hunk Dependency Graph

The first move in harmonization is to build a graph over every hunk in every variant and then synthesize in topological order.

### 1.1 What a node is

A node is a triple `(variant, file, hunk_id)` where:
- `variant` ∈ `{canonical, branch_1, ..., branch_N, worktree_1, ..., worktree_M}`
- `file` is a relative path within the repo
- `hunk_id` is a stable identifier for one logical change (typically a `@@` block in the unified diff)

Hunks are atomized at the `@@` boundary, but adjacent `@@` blocks in the same diff that touch the same function or symbol are coalesced — synthesis is sometimes correct only when adjacent hunks are taken together.

### 1.2 What an edge is

Edges encode dependencies. For two nodes A and B, there's an edge A → B (A depends on B) when:

| Edge type | Example | How detected |
|---|---|---|
| **Symbol dependency** | A's hunk uses a function `redact_secrets`; B's hunk introduces `redact_secrets` | `ast-grep` for symbol-introduction in B; symbol-use in A |
| **Same-file structural** | A's hunk modifies lines 1–10 of `logger.rs`; B's hunk modifies lines 12–18 of the same file (in the same variant) | line range overlap; same-variant grouping |
| **Cross-file co-change** | A's hunk renames `Logger::new` in `logger.rs`; B's hunk updates a call site in `main.rs` | symbol rename detection across the variant's commits |
| **Test-of-symbol** | A is a test for `redact_secrets`; B is the introduction of `redact_secrets` | test-name matching to symbol; or `cargo test --no-run` shows the test as failing without B applied |
| **Type-narrowing chain** | A narrows `arg: &str` → `arg: &NonEmptyStr`; B is a constructor `NonEmptyStr::try_from` | type-name unification |
| **Refactor-then-feature** | A is a structural refactor; B adds a new feature on top | "B's hunk modifies lines that A's hunk introduced" |

### 1.3 Topological sort = synthesis order

Once the graph is built, topological sort gives the order in which hunks must be applied. Cycles are *forbidden* — if the graph has a cycle, the variants have circular dependencies that no synthesis can resolve coherently. Per [HARMONIZATION.md §5](HARMONIZATION.md#5-when-not-to-harmonize), this is `divergent-refactor` territory; surface to user.

```
Topological sort algorithm:
  G = (V, E)
  L = []  # output order
  S = {v ∈ V | in-degree(v) = 0}  # nodes with no incoming edges
  while S not empty:
    pop n from S
    L.append(n)
    for each m where n → m:
      remove edge n → m
      if in-degree(m) = 0:
        S.add(m)
  if E not empty:
    halt with "cycle detected: variants <list> share a circular dependency on file <path>"
  else:
    return L
```

### 1.4 Worked example — logger.rs DAG

Three variants touch `src/util/logger.rs`:

- `agent-cleanup-pass-3`: hunk H1 adds `null_arg_guard()` function; hunk H2 modifies `log()` to call `null_arg_guard()`.
- `feature/length-cap`: hunk H3 adds constant `MAX_LOG_MSG_BYTES`; hunk H4 modifies `log()` to check length.
- `feature/redact-secrets`: hunk H5 adds `redact_secrets()` function; hunk H6 modifies `log()` to call it before write.

Edges:

```
H2 → H1   (log() uses null_arg_guard; null_arg_guard introduced in H1)
H4 → H3   (log() uses MAX_LOG_MSG_BYTES; constant introduced in H3)
H6 → H5   (log() uses redact_secrets; function introduced in H5)
```

H2, H4, H6 all touch the same `log()` function in different variants. They are *the same logical hunk* in the synthesis (the rewritten `log()`). The synthesis algorithm coalesces them in §3.

Topological sort (after coalescence):

```
Layer 0: H1 (null_arg_guard), H3 (MAX_LOG_MSG_BYTES), H5 (redact_secrets)
Layer 1: H2/H4/H6 (the rewritten log() — one synthesis hunk that uses all three)
```

The synthesis applies in Layer order. Layer 0 hunks are independent and can be applied in any sub-order. Layer 1 is a single synthesis hunk derived from H2, H4, and H6 per §6 (defensive composition).

### 1.5 Why the graph matters

Without the graph, the synthesizer might apply H6 (redact_secrets call in log()) before H5 (the function definition) — producing code that doesn't compile. The graph makes this impossible: H6 → H5 means H5 lands first. The graph is the structure that makes "best-of-all-worlds" mechanically derivable.

---

## 2. AST-Aware Merge via ast-grep

The variant matrix in [HARMONIZATION.md §2](HARMONIZATION.md#2-the-variant-matrix-structure) records signatures. When two variants both modify the same function, the synthesis must reconcile signatures. `ast-grep` (per AGENTS.md "ast-grep vs ripgrep") is the right tool because it operates on parsed AST, not text — it sees structure, not bytes.

### 2.1 The signature reconciliation pattern

For a Rust function:

```bash
ast-grep run -l Rust -p 'fn $NAME($$$ARGS) -> $RET { $$$BODY }' \
  -- src/util/logger.rs
```

This matches every function in `logger.rs` and exposes `$NAME`, `$ARGS`, `$RET`, `$BODY` as captures. For each variant, run the pattern and compare:

```
Variant A: fn log(level: Level, msg: &str)            -> Result<()>
Variant B: fn log(level: Level, msg: &str)            -> Result<()>
Variant C: fn log(level: Level, msg: &str, ctx: &Ctx) -> Result<()>
Variant D: fn log(level: Level, msg: NonEmptyStr<'_>) -> Result<()>
```

Reconciliation rules:

| Pattern | Synthesis decision |
|---|---|
| Variants A and B have identical signatures | Compose their bodies (§6) |
| Variant C extends signature with new param | Treat as a refactor; if D's narrower type fits, compose narrowings into the extended signature; surface to user if C's intent is unclear |
| Variant D narrows a parameter type | Adopt narrower type if its construction sites can be adapted; otherwise rebase D's body onto the wider type |

### 2.2 Per-language patterns

| Language | Pattern | What it captures |
|---|---|---|
| Rust | `fn $NAME($$$ARGS) -> $RET { $$$BODY }` | name, args, return, body |
| Rust | `pub fn $NAME($$$ARGS) -> $RET { $$$BODY }` | as above + visibility |
| Rust | `impl $TRAIT for $TYPE { $$$BODY }` | trait, type, methods |
| TypeScript | `function $NAME($$$ARGS): $RET { $$$BODY }` | name, args, return, body |
| TypeScript | `($$$ARGS): $RET => $$$BODY` | arrow function |
| TypeScript | `interface $NAME { $$$MEMBERS }` | interface |
| Python | `def $NAME($$$ARGS) -> $RET: $$$BODY` | typed function |
| Python | `def $NAME($$$ARGS): $$$BODY` | untyped function |
| Python | `class $NAME($$$BASES): $$$BODY` | class |
| Go | `func $NAME($$$ARGS) $RET { $$$BODY }` | func |
| Go | `func ($RECV $TYPE) $NAME($$$ARGS) $RET { $$$BODY }` | method |
| C++ | `$RET $NAME($$$ARGS) { $$$BODY }` | function |

### 2.3 Comparing structures, not text

A variant adding a comment line above a function modifies the *text* but not the *structure*. ast-grep normalizes this. Two variants that "differ" only in whitespace/comment placement around the same function body are detected as **identical** — and §3's semantic deduplication folds them into one row.

### 2.4 When ast-grep can't help

For languages without a tree-sitter grammar (e.g., obscure DSLs, custom config formats), or for files where ast-grep matches are noisy (e.g., heavy macros), the synthesis falls back to canonical-form text comparison (§3.1). The fallback is documented in `harmonization_plan.md`'s row's `risks` column with text "ast-grep unavailable; using canonical-form text compare."

---

## 3. Semantic Deduplication of Variants

When two variants modify the same function in *effectively* the same way (whitespace, import order, comment placement), they should be coalesced into one row in the variant matrix — not treated as competing.

### 3.1 Canonical-form comparison

For each language, run the project's formatter on each variant's content and compare:

| Language | Formatter | Notes |
|---|---|---|
| Rust | `cargo fmt --check` or `rustfmt` | Project's `rustfmt.toml` is honored |
| TypeScript / JavaScript | `prettier` | Project's `.prettierrc` honored |
| Python | `black` or `ruff format` | Or `autopep8` if the project uses it |
| Go | `gofmt` or `goimports` | `goimports` also normalizes import order |
| Java | `google-java-format` | Or whatever the project uses |
| C / C++ | `clang-format` | With project's `.clang-format` |

Compare the formatted texts byte-for-byte. If equal, the variants are semantically identical — fold them into one matrix row (cite both sources in the synthesis commit message).

### 3.2 What canonical-form comparison catches

Common cases where canonical-form comparison saves the user from spurious "competing variants":

- **Import order:** branch A imports `use std::io::Write` first; branch B imports `use std::collections::HashMap` first. After `cargo fmt`, they sort the same way.
- **Trailing comma:** branch A omits trailing commas in arg lists; branch B includes them. `cargo fmt` enforces a project-wide rule.
- **Whitespace within strings vs. outside:** branch A indents a multiline string with 4 spaces; branch B with 8. The string content is identical when leading-whitespace is normalized.
- **Brace placement:** `if x {\n y;\n}` vs `if x\n{\n  y;\n}`. After `cargo fmt`, identical.
- **Comment-only differences:** branch A added a `// TODO` above a function; branch B added a `// FIXME` in the same place. Strip comments (`ast-grep` lets us do this); if the structural code is identical, the variants are effectively the same.

### 3.3 What canonical-form comparison does NOT catch

- Variants that introduce different inner-implementation but identical outer-behavior (e.g., one uses `for` loop, the other `iter().map().collect()`). These are *semantically* equivalent but textually different post-format. The synthesizer doesn't try to detect this — the user reviews the matrix and decides if they're equivalent.
- Variants that differ only in error-message strings. The behavior is the same; the user-facing text differs. Treat as competing rows in the matrix; let the planner pick one.
- Type-equivalent renames (`Box<dyn Error>` vs. `anyhow::Error`). Treat as competing.

### 3.4 The deduplication step in the synthesis algorithm

```
for each contested file F:
  variants_F = {variants that touch F}
  canonical_form_groups = {}
  for v in variants_F:
    cf = canonical_form(v's content for F)
    canonical_form_groups[cf].append(v)
  for cf in canonical_form_groups:
    if len(canonical_form_groups[cf]) > 1:
      coalesce into one matrix row
      synthesis commit message: "from <v1>, <v2>, ... (semantically identical)"
      provenance: all variants
```

---

## 4. Test Fixture Composition Rules

Tests and fixtures are mostly additive (per [HARMONIZATION.md §4.4–4.5](HARMONIZATION.md#44-tests-are-additive)) but the rules are subtle when fixtures interact across variants.

### 4.1 Test files are additive

Across variants:

- **New test files** (didn't exist on canonical) land directly. Name collisions resolved by suffixing: `tests/log_input_validation.rs` from variant A becomes `tests/log_input_validation_null.rs`; from variant B becomes `tests/log_input_validation_length.rs`.
- **New test functions in existing files** are appended. Name collisions resolved by suffixing the function name.
- **Modifications to existing test functions** require the variant matrix's intent column. If both variants modified the same test (e.g., both updated the expected output), surface to user.

### 4.2 Fixture files — the additive default

A fixture file (`tests/fixtures/parse_input.json`, `testdata/golden_output.txt`, `*.snap`) added by a variant lands. If two variants both add fixtures with the same name but different content, the synthesis algorithm needs more information.

### 4.3 The fixture interaction rules

| Situation | Synthesis decision |
|---|---|
| Both variants add a new fixture file with the same name and identical content | Land it once (semantic dedup, §3) |
| Both variants add a new fixture file with the same name and different content | Surface to user — fixture content is usually evidence of a real semantic difference in the code |
| Both variants modify an existing fixture file in additive sections (e.g., both append) | Compose the additions — the synthesis's fixture is the union |
| Both variants modify the same section of a fixture file in incompatible ways | Surface to user; this almost certainly indicates the underlying *code* changes are incompatible |
| One variant adds a fixture file; another deletes it | Surface to user — deletion-vs-addition is direction disagreement |

### 4.4 Integration tests with `before_each` / `setUp` / `setup` fixtures

Integration tests with shared setup are tricky. If variant A's `setup()` adds a database row and variant B's `setup()` truncates a table, the *union* setup might leave the table truncated AFTER the row was added. Order matters.

For Rust integration tests:

```rust
#[ctor]                               // from `ctor` crate
fn setup_v_a() { /* variant A setup */ }

#[ctor]
fn setup_v_b() { /* variant B setup */ }
```

The order of `#[ctor]` execution is unspecified — this is an actual hazard. The synthesis algorithm flags any cross-variant setup composition as `setup-composition-risk` and surfaces to user with the recommendation to merge setups by hand.

### 4.5 Snapshot files (`.snap`, `__snapshots__/*.snap`)

Snapshot tests freeze a serialized value. When two variants update the same snapshot, the snapshots literally cannot be unioned — only one can win. Treat as same-fixture-different-content: surface to user, recommend re-recording the snapshot from the synthesized code.

---

## 5. Refactor-vs-Feature Distinction

One of the most common synthesis decisions is whether two variants are (a) competing refactors of the same code, (b) two features on top of an unchanged base, or (c) a refactor followed by a feature.

### 5.1 Detection from the diff

For each variant's hunks on file F, classify:

| Hunk shape | Likely class |
|---|---|
| Renames a symbol; updates call sites | Refactor (no new behavior) |
| Extracts a function; replaces inline code with a call | Refactor |
| Replaces `if-else` with `match`, `Vec<u8>` with `Bytes`, `Mutex` with `RwLock` | Refactor |
| Adds a new function with new behavior; existing functions unchanged | Feature |
| Adds a new branch to an `if-else` chain | Feature (or behavior change) |
| Adds defensive checks to an existing function | Feature (defensive intent — see [HARMONIZATION.md §3](HARMONIZATION.md#3-intent-taxonomy)) |
| Changes a public function's signature AND updates all callers | Refactor |

### 5.2 Composition rules

| Variant A's class | Variant B's class | Synthesis composition |
|---|---|---|
| Refactor | Feature | Apply A first (refactor establishes new shape); apply B's feature on top of A's shape |
| Feature | Refactor | Same as above (apply B first, then A) |
| Refactor | Refactor | Cannot freely compose. If A and B are *orthogonal* refactors (different code regions), apply both. If overlapping, surface as `divergent-refactor` |
| Feature | Feature | Compose if intents are independent (per [HARMONIZATION.md §4.2](HARMONIZATION.md#42-defensive-checks-compose) for defensive features); pick stronger if not |

### 5.3 Worked example — refactor-then-feature

`feature/extract-logger-trait` (variant R): extracts `Logger` trait from a free function `log()`. Implementation moves to `impl Logger for FileLogger`.

`agent-cleanup-pass-3` (variant F): adds null-arg guard to `log()` (the original free function).

Detection:
- Variant R is a refactor (renames the API surface, no new behavior).
- Variant F is a feature (adds new defensive behavior).

Composition:
1. Apply R first (replace free `log()` with `Logger::log` method).
2. Apply F's intent (the null-arg guard) into the new shape — i.e., add the null-arg guard to `Logger::log`'s body.
3. The synthesis's commit cites both: "extract Logger trait + lift null-arg guard from agent-cleanup-pass-3 onto Logger::log".

The user reviewing the harmonization plan sees explicit reasoning for the composition order. If the planner can't tell which is the refactor (e.g., both variants change signatures), it surfaces to user.

---

## 6. Synthesis Dependency Order — Defensive Checks

When multiple variants add defensive checks at function entry, the synthesis composes them. Order matters: cheap-rejection-first preserves performance; structurally-required ordering (type narrowing before content checks) preserves correctness.

### 6.1 The ordering rule

> **Order defensive checks by the earliest stage at which they fire, cheapest-first, then by data-flow dependency.**

Stages, ordered (most-permissive to most-restrictive):

| Stage | What it checks | Cost (typical) |
|---|---|---|
| 1. Type-narrowing (compile-time) | The argument's *type* already excludes invalid values (e.g., `NonEmptyStr` excludes empty) | 0 (compile-time) |
| 2. Null / empty check | Argument is non-nil/non-empty | O(1) |
| 3. Length / size cap | Argument size ≤ MAX_LEN | O(1) |
| 4. Range / value check | Argument's numeric value is in [min, max] | O(1) |
| 5. Regex / pattern check | Argument matches/avoids a pattern | O(n × pattern_complexity) |
| 6. Redaction / transformation | Strip secrets, normalize encoding | O(n × pattern_count) |
| 7. Authorization / permission check | Caller is allowed to invoke | O(network or O(database)) |
| 8. Resource availability | Required resource is reachable | O(network or O(disk)) |

A function that has guards at multiple stages applies them in stage-order. Rationale: rejection at stage 2 is cheaper than at stage 5, so a malformed-and-too-large-and-pattern-violating input is rejected on the cheapest grounds first.

### 6.2 The synthesis composition

For a `log()` function with guards from three variants:

```
agent-cleanup-pass-3:    null-arg guard               (Stage 2)
feature/length-cap:      length-cap guard              (Stage 3)
feature/redact-secrets:  redact_secrets() before write (Stage 6)
```

Synthesis order:

```rust
fn log(level: Level, msg: &str) -> Result<()> {
    // Stage 2: null/empty
    if msg.is_empty() {
        return Err(LoggerError::EmptyMessage);
    }
    // Stage 3: length cap
    if msg.len() > MAX_LOG_MSG_BYTES {
        return Err(LoggerError::MessageTooLong(msg.len()));
    }
    // Stage 6: redact (transformation, not rejection)
    let msg = redact_secrets(msg);
    // Now write
    write_log_entry(level, &msg)
}
```

This is exactly the synthesis in [HARMONIZATION.md §4.2](HARMONIZATION.md#42-defensive-checks-compose). The order isn't aesthetic — it's algorithmic.

### 6.3 Wrong order produces correct-but-wasteful code

Suppose the synthesizer applied redaction first, then length cap, then null:

```rust
fn log(level: Level, msg: &str) -> Result<()> {
    let msg = redact_secrets(msg);                  // BAD: regex over potentially-empty input
    if msg.len() > MAX_LOG_MSG_BYTES { ... }        // BAD: would always be redact'd first
    if msg.is_empty() { ... }                       // BAD: redaction may have produced empty
    write_log_entry(level, &msg)
}
```

The behavior is *almost* correct — but redaction on an empty string is wasted work (it allocates a new string for nothing). And length-cap-after-redaction means a 4-KiB message with secrets gets redacted (potentially expanded with `[REDACTED]` placeholders) and THEN length-checked — the user gets a different rejection threshold than they asked for.

### 6.4 Wrong order produces semantic bugs

A type-narrowing-before-feature ordering is *always* required (Stage 1 must precede Stages 2+). If the narrowing happens after the check, the check is implicit-redundant or, worse, the check operates on a non-narrowed value:

```rust
// WRONG: check before narrow
fn process(input: &str) -> Result<()> {
    if input.is_empty() {                     // generic check
        return Err(...);
    }
    let input: NonEmptyStr = NonEmptyStr::try_from(input)?;  // implicit-redundant; would the check just pass?
    ...
}

// RIGHT: narrow before any other check
fn process(input: NonEmptyStr) -> Result<()> {
    // No need to check is_empty — the type guarantees it
    ...
}
```

The `RIGHT` form requires the call site to construct the `NonEmptyStr`. If a variant introduced the narrowing, the synthesis must propagate the narrowing to the call sites — this is the cross-file co-change edge in §1.2.

---

## 7. The Synthesis as a Code-Review-Grade Commit

A synthesis commit is not a "rough merge" or an "auto-merge with a note." It must satisfy the same review bar as any feature commit on the project's main line.

### 7.1 The bar

| Property | How to verify |
|---|---|
| Compiles | `cargo check` / `tsc --noEmit` / `python -m py_compile` / `go build ./...` |
| Type-checks | language-specific |
| Passes lint | `cargo clippy` / `eslint` / `ruff` / `golangci-lint` |
| Passes tests | `cargo test` / `npm test` / `pytest` / `go test ./...` |
| Passes UBS | `ubs <changed-files>` (per AGENTS.md "UBS Static Analysis") |
| Pre-commit hooks pass | The project's `.pre-commit-config.yaml` or `husky` hooks |
| Signed if canonical's commits are signed | `git commit -S` if the project signs |
| Commit message cites every source variant | per [HARMONIZATION.md §6.2](HARMONIZATION.md#62-commit-messages-cite-source-branches-and-explain-why-each-hunk-came-from-where) |

### 7.2 Per-apply gates run on every synthesis

Per [SKILL.md Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms): "Run the project's actual `test`, `typecheck`, `lint`, `ubs` after every Phase 8 apply." A synthesis commit is a Phase 8 apply. The gates run; the commit lands only if they pass.

### 7.3 If a gate fails

- The synthesis is broken. The Edit-tool changes are reverted with `git checkout -- <file>` (NOT `git reset --hard` — that's blocked by DCG and forbidden by Axiom 11).
- The harmonization plan row's confidence drops; the planner re-considers (often the dropped intent reveals an MR-Compose failure per [DECISION-THEORY.md §7](DECISION-THEORY.md#7-metamorphic-relations-as-confidence-boosters)).
- The user is surfaced the failure with the gate output and the planner's revised proposal.

The synthesis NEVER lands with a broken gate "to be fixed later" — that violates the Polish Bar's "no compounding errors" rule.

---

## 8. The Logger.rs Synthesis — Full Derivation Step-by-Step

Re-running the [HARMONIZATION.md §7](HARMONIZATION.md#7-worked-example--logger-harmonization-across-three-branches) example with the full algorithm visible.

### 8.1 Inputs

Three variants modifying `src/util/logger.rs`:
- **V1** = `agent-cleanup-pass-3` (null-arg guard)
- **V2** = `feature/length-cap` (length cap at 4 KiB)
- **V3** = `feature/redact-secrets` (redact secrets before write)

Canonical's `log()`:

```rust
pub fn log(level: Level, msg: &str) -> Result<()> {
    write_log_entry(level, msg)
}
```

### 8.2 Step 1 — Build the hunk dependency graph

Per §1, atomize each variant's diff into hunks. Annotate symbols introduced.

| Hunk | Variant | Introduces | Modifies |
|---|---|---|---|
| H1 | V1 | `null_arg_guard()` | — |
| H2 | V1 | — | `log()` (calls null_arg_guard) |
| H3 | V2 | `MAX_LOG_MSG_BYTES` | — |
| H4 | V2 | — | `log()` (uses MAX_LOG_MSG_BYTES) |
| H5 | V3 | `redact_secrets()` | — |
| H6 | V3 | — | `log()` (calls redact_secrets) |

Edges: H2→H1, H4→H3, H6→H5.

H2/H4/H6 all modify `log()` — they coalesce per §1 into a single synthesis hunk Hsyn for the rewritten `log()`.

Topological order:

```
Layer 0 (independent introductions): H1, H3, H5 (any order)
Layer 1 (the merged log()):          Hsyn
```

### 8.3 Step 2 — AST-aware reconciliation

Run `ast-grep -l Rust -p 'fn log($$$ARGS) -> $RET { $$$BODY }'` on each variant.

```
V1: fn log(level: Level, msg: &str) -> Result<()>   args = [level: Level, msg: &str]
V2: fn log(level: Level, msg: &str) -> Result<()>   args = [level: Level, msg: &str]
V3: fn log(level: Level, msg: &str) -> Result<()>   args = [level: Level, msg: &str]
```

Signatures are identical. Compose bodies (no signature divergence — no need to surface to user).

### 8.4 Step 3 — Semantic deduplication

Run formatter (`rustfmt`) on each variant's `logger.rs`. The variants' content for H1, H3, H5 (the introductions) is independent — no canonical-form match. The variants' content for `log()`'s body (H2, H4, H6) IS different — each adds a different guard. No deduplication.

### 8.5 Step 4 — Refactor-vs-feature classification

Per §5:

- V1's hunks are: introduce a function (Feature/defensive), call it from `log()` (Feature). All Feature-class.
- V2's hunks are: introduce a constant (Feature), check it (Feature). All Feature-class.
- V3's hunks are: introduce a function (Feature/defensive), call it (Feature). All Feature-class.

No refactors. All three are independent defensive features. They compose per [HARMONIZATION.md §4.2](HARMONIZATION.md#42-defensive-checks-compose).

### 8.6 Step 5 — Defensive ordering

Per §6.1:

```
V1 null-arg     → Stage 2 (null/empty)
V2 length cap   → Stage 3 (size)
V3 redact       → Stage 6 (transformation)
```

Order: Stage 2 → Stage 3 → Stage 6.

### 8.7 Step 6 — Generate the synthesis hunk Hsyn

```rust
const MAX_LOG_MSG_BYTES: usize = 4096;

pub fn log(level: Level, msg: &str) -> Result<()> {
    if msg.is_empty() {
        return Err(LoggerError::EmptyMessage);
    }
    if msg.len() > MAX_LOG_MSG_BYTES {
        return Err(LoggerError::MessageTooLong(msg.len()));
    }
    let msg = redact_secrets(msg);
    write_log_entry(level, &msg)
}
```

Plus the introductions H1 (`null_arg_guard` — but actually inlined as `if msg.is_empty()` since the helper was trivial), H3 (`MAX_LOG_MSG_BYTES`), H5 (`redact_secrets()`).

### 8.8 Step 7 — Land via Edit tool

Per [HARMONIZATION.md §6.1](HARMONIZATION.md#61-synthesis-commits-land-via-the-edit-tool-never-sedawk), the agent reads the synthesis from `harmonization_plan.md`, opens the Edit tool on `src/util/logger.rs`, applies the changes manually. Tests + lint + UBS run. Commit lands with the [HARMONIZATION.md §7.3](HARMONIZATION.md#73-the-commit-message) commit message.

### 8.9 Step 8 — MR self-checks

Per [DECISION-THEORY.md §7](DECISION-THEORY.md#7-metamorphic-relations-as-confidence-boosters):
- **MR-Compose:** every test from V1, V2, V3 passes on the synthesis. PASS.
- **MR-Idempotence:** re-running the harmonization plan on the synthesized commit produces no new changes. PASS.
- **MR-Commutativity:** synthesizing in order V1→V2→V3 vs V3→V2→V1 produces the same result (after fmt). PASS.

Confidence escalates from initial 0.91 to ~0.999. The synthesis is decisively correct.

### 8.10 What changed vs. a vibes-based synthesis

A synthesis without the algorithm might:
- Apply the redaction first ("seems important"), giving the wrong stage order.
- Forget MAX_LOG_MSG_BYTES (V2's introduction) because only the call site was visible.
- Drop the test files because "they're already covered by V1's test."

The algorithm prevents all three by construction.

---

## 9. When Synthesis FAILS Gracefully

Some variant matrices have no valid synthesis. The algorithm must detect this and surface it cleanly.

### 9.1 Failure modes the algorithm catches

| Failure | Detection | What happens |
|---|---|---|
| **Cycle in the dependency graph** | Topological sort detects a cycle | Halt; mark file `divergent-refactor`; user picks one variant |
| **Signature divergence on a contested function with no compatible reconciliation** | ast-grep shows incompatible parameter lists | Halt; the file is `divergent-refactor`; user picks one |
| **Two variants implement fundamentally different storage backends** (column-vs-row, mutex-vs-channel) | Per [HARMONIZATION.md §5](HARMONIZATION.md#5-when-not-to-harmonize) | Halt; surface; user picks |
| **Test setup composition produces nondeterministic ordering** | §4.4 setup-composition-risk flag | Halt; user manually merges setups |
| **Fixture conflict on the same section** | §4.3 modify-same-section-incompatibly | Halt; user reconciles fixture |
| **MR-Compose fails on the synthesis** | §7.2 of [DECISION-THEORY.md](DECISION-THEORY.md) | Confidence drops; planner retries; if retries don't improve, halt and surface |
| **Per-apply gates fail repeatedly** | gate output + retry loop | After 2 failed retries, halt; user reviews gate output |

### 9.2 The graceful failure path

When the algorithm halts on a contested file:

1. Mark the file `divergent-refactor` retroactively in the variant matrix.
2. In `harmonization_plan.md`, the file's section reads: "FAILED TO SYNTHESIZE — {failure mode}. Variants preserved in the bundle. User must pick one variant or merge by hand."
3. Phase 8 skips the synthesis for this file. The variants' content is untouched (still in the bundle, still on the source branches).
4. The user reviews the failure, picks a variant, and restarts Phase 7 for that file (or hand-merges).

### 9.3 The user-facing message

Failure messages are concrete and actionable:

```
HARMONIZATION FAILED for src/storage/backend.rs

3 variants modify this file with incompatible storage layouts:
  - feature/columnar-store: column-oriented Parquet
  - feature/row-store:      row-oriented sled key-value
  - agent-rewrite-pass-2:   in-memory HashMap

These designs cannot be synthesized — the data layout IS the design.

Action: pick one variant. The chosen variant will be applied via cherry-pick;
the other variants' content remains in the bundle (recoverable via
[RECOVERY-RECIPES.md R1](RECOVERY-RECIPES.md#r1-i-regret-deleting-a-branch))
but is NOT applied to the rationalization branch.

Type one of:
  KEEP feature/columnar-store
  KEEP feature/row-store
  KEEP agent-rewrite-pass-2
  SKIP   (apply none; the file remains as canonical has it)
```

The user types one phrase verbatim. Phase 7 records the choice in `user_overrides.tsv` and proceeds.

### 9.4 Why graceful failure matters

The alternative to graceful failure is the algorithm guessing — picking a "best" variant by some heuristic. That's fine when the heuristic agrees with the user; when it doesn't, the user has to undo the decision, and now there's a cherry-pick on the rationalization branch that needs reverting. Graceful failure means the user makes the call BEFORE work lands.

> **Why:** [HARMONIZATION.md §5](HARMONIZATION.md#5-when-not-to-harmonize): "When in doubt, flag rather than synthesize. The harmonization plan's confidence column for any synthesis row must be ≥0.7 to land without explicit user OK." This file makes "flag rather than synthesize" mechanical — the algorithm halts at well-defined failure modes, and the user decides.

---

## 10. Cross-References

- [HARMONIZATION.md](HARMONIZATION.md) — the conceptual centerpiece this file deepens
- [DECISION-THEORY.md](DECISION-THEORY.md) — confidence and MR-based escalation
- [TESTING-METAMORPHIC.md](TESTING-METAMORPHIC.md) — MR-Compose, MR-Idempotence, MR-Commutativity
- [PROVENANCE-CHAIN.md](PROVENANCE-CHAIN.md) — how each synthesized hunk traces back to source variants
- [OPERATOR-LIBRARY.md ◇ HARMONIZE](OPERATOR-LIBRARY.md#-harmonize--the-conceptual-centerpiece) — the operator card
- [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md) — the commit-message format used after synthesis
- [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) — `divergent-refactor` verdict that synthesis-failure rolls back to
- [PHASES.md Phase 7](PHASES.md) — the orchestration loop where this algorithm runs

---

## 11. The Mantra

> **Build the dependency graph. Reconcile signatures via AST. Deduplicate by canonical form. Distinguish refactor from feature. Order defensive checks by stage. Land via Edit tool with provenance. Verify by MR. Halt gracefully on cycles, divergent shapes, and failed gates. The synthesis is an algorithm, not an inspiration.**
