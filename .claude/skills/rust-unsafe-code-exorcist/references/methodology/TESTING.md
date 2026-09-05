# TESTING.md — Verifying the Skill Works End-to-End

Three layers of testing to confirm the skill is healthy on your machine + behaves correctly for your prompts:

1. **Trigger test** — does the skill actually activate when you ask for it?
2. **Smoke test** — does the audit pipeline run end-to-end on a toy project?
3. **Harness self-test** — do all the verification tools work on YOUR machine?

---

## 1. Trigger test (30 seconds)

The skill's frontmatter description is its trigger. To verify your local coding agent correctly routes your phrasing to this skill:

### Phrases that SHOULD activate it

Drop any of these into a local coding-agent session in a Rust project. The skill should activate:

```
Audit every unsafe in this project.
Help me eliminate unsafe from this Rust crate.
Run an unsafe code exorcist pass.
Find the macro-generated unsafe hiding in this workspace.
Add a `safe-only` feature flag and CI matrix for the SIMD path.
Convince me this `unsafe` block is actually necessary.
Is the unsafe in this dependency reachable from our public API?
Pre-release soundness gate for this crate.
Build a verification harness with miri, loom, fuzz, mutants, and geiger.
Three-bucket-classify this project's unsafe.
```

### Phrases that should NOT activate it

These are too general:

```
How do I write unsafe code?
What is the borrow checker?
Add a new feature to my Rust project.
Generate Rust documentation.
```

If a non-trigger phrase activates the skill, the description is too broad. File feedback.

### Per-model testing

Smaller models need explicit trigger signals; mid-sized models handle medium subtlety; frontier models are most forgiving.

Test sequence:

1. **Haiku** — try with a Haiku model first. Use the most explicit phrasing: "Run the rust-unsafe-code-exorcist skill on /path/to/project."
2. **Sonnet** — try a mid-subtlety phrase: "Audit my Rust crate's unsafe code."
3. **Opus** — try a high-level phrase: "I want to know which unsafe in my crate I should worry about."

All three should activate the skill. If Haiku misses a phrase that Sonnet+ catches, the description needs more explicit triggers (file feedback so the skill author can refine).

---

## 2. Smoke test (5 minutes)

Verify the audit pipeline runs end-to-end on a tiny project. Use the toy from [README.md § Try it on a toy project first](../../README.md):

```bash
# 1. Create the toy
mkdir -p /tmp/exorcist-smoke && cd /tmp/exorcist-smoke
cat > Cargo.toml <<'EOF'
[package]
name = "exorcist-smoke"
version = "0.1.0"
edition = "2021"
EOF
mkdir src
cat > src/lib.rs <<'EOF'
pub fn from_be_unsafe(b: [u8; 4]) -> u32 {
    unsafe { std::mem::transmute::<[u8; 4], u32>(b) }.to_be()
}
pub fn first_byte_unchecked(s: &[u8]) -> u8 {
    unsafe { *s.get_unchecked(0) }
}
unsafe impl Send for MyHandle {}
pub struct MyHandle { inner: *const u8 }
EOF
cargo build  # ensure it compiles

# 2. Run the enumerator alone (no full audit yet)
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
AUDIT_DIR=/tmp/exorcist-smoke/.unsafe-audit
mkdir -p "$AUDIT_DIR"
"$SKILL/scripts/check-prerequisites.sh"
"$SKILL/scripts/enumerate-unsafe.sh" /tmp/exorcist-smoke "$AUDIT_DIR"
node "$SKILL/scripts/generate-inventory.mjs" "$AUDIT_DIR"

# 3. Inventory should have ≥3 rows (transmute + get_unchecked + unsafe impl Send)
wc -l "$AUDIT_DIR/unsafe-inventory.jsonl"
cat "$AUDIT_DIR/unsafe-inventory.jsonl" | jq -r '.kind' | sort | uniq -c
```

Expected output (with ast-grep installed) includes at least these rows; newer
enumerators may also report hazard-signal rows such as raw pointer casts,
`UnsafeCell`, or pointer intrinsics:

```
N /tmp/exorcist-smoke/.unsafe-audit/unsafe-inventory.jsonl   # N >= 3
   2 block
   1 unsafe_impl
```

The two `block` rows are the `transmute` and the `get_unchecked`; additional
rows are acceptable when they correspond to documented inventory kinds in
`INVENTORY-SCHEMA.md`.

### Variant: smoke with ripgrep fallback (no ast-grep)

Verify the fallback path works on machines without ast-grep. The trick: shadow
JUST `ast-grep` (without removing the rest of `~/.cargo/bin` — that would also
remove `cargo`, breaking the run).

```bash
# Create a tmp dir holding ONLY a fake "ast-grep" that always errors.
SHADOW_BIN=$(mktemp -d)
cat > "$SHADOW_BIN/ast-grep" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$SHADOW_BIN/ast-grep"

# Prepend the shadow dir so the fake ast-grep wins; everything else on PATH stays.
PATH="$SHADOW_BIN:$PATH" "$SKILL/scripts/enumerate-unsafe.sh" /tmp/exorcist-smoke "$AUDIT_DIR-fallback"
node "$SKILL/scripts/generate-inventory.mjs" "$AUDIT_DIR-fallback"
wc -l "$AUDIT_DIR-fallback/unsafe-inventory.jsonl"
```

Should produce a similar inventory (less precise; relies on ripgrep + grep heuristics).

Alternatively, on a machine where ast-grep was never installed, the fallback path runs naturally — no shadow needed.

### Variant: smoke with full audit pipeline

Once enumeration works, invoke the orchestrator in your local coding-agent session:

```
/rust-unsafe-code-exorcist /tmp/exorcist-smoke
```

If your agent does not support slash-command invocation, ask it directly to run
`rust-unsafe-code-exorcist` on `/tmp/exorcist-smoke` in audit-only quick mode.

Acceptance:
- After ~5–15 minutes (small project), `<AUDIT_DIR>/AUDIT_SUMMARY.md` exists.
- Tally is something like `A: 1, B: 1, C: 1` (or similar — exact bucketing depends on the rewrite plans).
- Risk scores are computed.

---

## 3. Harness self-test (10–30 minutes)

Verify each verification tool runs on your machine, with the toy project:

```bash
cd /tmp/exorcist-smoke
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"

# Each script can run independently. Each emits to verify.log; exits non-zero on failure.
bash "$SKILL/scripts/run-miri.sh" /tmp/exorcist-smoke/.unsafe-audit /tmp/exorcist-smoke
bash "$SKILL/scripts/run-careful.sh" /tmp/exorcist-smoke/.unsafe-audit /tmp/exorcist-smoke
bash "$SKILL/scripts/run-loom.sh" /tmp/exorcist-smoke/.unsafe-audit /tmp/exorcist-smoke  # skips (no loom suites)
bash "$SKILL/scripts/run-fuzz.sh" /tmp/exorcist-smoke/.unsafe-audit /tmp/exorcist-smoke   # skips (no fuzz/)
bash "$SKILL/scripts/run-mutants.sh" /tmp/exorcist-smoke/.unsafe-audit /tmp/exorcist-smoke
bash "$SKILL/scripts/run-geiger.sh" /tmp/exorcist-smoke/.unsafe-audit /tmp/exorcist-smoke
```

Each script appends to `/tmp/exorcist-smoke/.unsafe-audit/audit/phase7/verification-log.md`. Each step's section ends with `Status: GREEN` or a failure with triage hints.

Expected on the toy project:
- miri: GREEN (the unsafe code's narrow surface; no UB).
- careful: GREEN.
- loom: SKIPPED (no loom suites configured).
- fuzz: SKIPPED (no fuzz/ targets).
- mutants: GREEN (toy has minimal tests; coverage % may be low).
- geiger: counts +3 sites (matches inventory).

---

## 4. Validator tests (for maintainers, 30 seconds)

If you've edited the skill itself (added a new operator, added an exemplar entry):

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
python3 "$SKILL/scripts/validate-corpus.py"
python3 "$SKILL/scripts/validate-operators.py"
```

Each should print `OK` or `valid`. Failures name the specific entry that's malformed.

---

## 5. Failure-mode tests

What happens when things go wrong? Verify graceful degradation:

| Test | How | Expected |
|------|-----|----------|
| No `ast-grep` AND no `rg` | Mask both on PATH | Warning printed; falls back to plain `grep`; inventory still produced (less precise) |
| No nightly toolchain | `rustup default stable` (temp) | enumerate works; miri/careful/geiger skip with documented message |
| No `cargo expand` | Uninstall (temp) | Macro-generated unsafe not surfaced; warning in expand step; non-macro analysis still runs |
| Bad project path | Pass `/nonexistent` | Clear error; no panic |
| Empty Rust project | No unsafe sites | Inventory is empty; AUDIT_SUMMARY says "A: 0, B: 0, C: 0; nothing to do." |
| Project with only macro-generated unsafe | Test with a derive-only crate | If cargo expand works, macro unsafe surfaces; otherwise the audit notes the limitation. |

If any of these produces a hard crash or confusing error, file feedback.

---

## 6. Continuous-mode self-test (1 hour)

If you've configured continuous mode ([CONTINUOUS-MODE.md](CONTINUOUS-MODE.md)):

```bash
# Wait for a cron run (or trigger manually)
bash "$SKILL/scripts/cron-drift-check.sh" "$AUDIT_DIR" /tmp/exorcist-smoke

# Inspect today's drift summary
DATE=$(date -u +%Y-%m-%d)
cat "$AUDIT_DIR/drift/$DATE/summary.md"

# Verify: drift count is 0 (no changes since baseline)
```

Then modify the toy project (add an `unsafe` block) and re-run:

```bash
# Edit src/lib.rs to add another unsafe block
echo 'pub fn extra() { unsafe { libc::abort() } }' >> /tmp/exorcist-smoke/src/lib.rs

# Re-run drift check
bash "$SKILL/scripts/cron-drift-check.sh" "$AUDIT_DIR" /tmp/exorcist-smoke

# Expect: drift count > 0, drift bead filed (if br installed)
```

---

## 7. CI integration self-test

If you've copied the GitHub Actions template to a project:

```bash
# Push a commit that adds unsafe; expect CI to flag it
cd /your/project
echo 'unsafe { /* new */ }' >> src/lib.rs
git add src/lib.rs && git commit -m "test: add unsafe to verify CI gate"
git push
# Watch the soundness workflow; expect a failure on geiger-delta (or a PR comment)
```

If the CI gate doesn't fire, check `.github/workflows/soundness.yml` matches the template and the workflow has run-on-PR enabled.

---

## What "passing" means

The skill is healthy on your machine when:

- Trigger test: phrases activate the skill on Haiku (the canary model).
- Smoke test: enumerate-unsafe.sh produces a non-empty inventory on the toy.
- Harness: miri + careful + geiger run clean on the toy.
- Validators: corpus + operators pass.
- Failure-mode tests: graceful degradation in each fault.

If any layer fails: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) has fixes for the common issues.

---

## What "not passing" means

- Triggers miss → the skill description needs tightening; file feedback so the description gets updated.
- Smoke fails → check [PREREQUISITES.md](PREREQUISITES.md); usually a missing tool.
- Harness fails → individual tools have known-issue lists in [TOOLCHAIN-RUNBOOK.md](TOOLCHAIN-RUNBOOK.md).
- Validators fail → either the skill was edited incorrectly, or there's a real catalog/operator-card bug. Read the validator's error message; fix the cited file.
- Failure-mode tests produce hard crashes → real bug; file feedback.

---

## Continuous testing

For maintainers + power users: run these on a schedule:

```bash
# Weekly: full smoke
bash "$SKILL/scripts/check-prerequisites.sh"
# (re-run the smoke test from §2)

# Per skill update: validators
python3 "$SKILL/scripts/validate-corpus.py"
python3 "$SKILL/scripts/validate-operators.py"

# Per release: end-to-end on a representative project
# (full audit invocation; verify AUDIT_SUMMARY produced)
```

The skill's CI workflow (if installed in this repo) runs these automatically.
