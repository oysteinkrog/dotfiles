# SELF-TEST.md — Trigger Phrases and Smoke Test

## Trigger phrases (should activate this skill)

- "Audit every `unsafe` in this project"
- "Help me eliminate unsafe from this Rust crate"
- "Run an unsafe code exorcist pass on `/dp/franken_engine`"
- "Find the macro-generated unsafe hiding in this workspace"
- "Add a `safe-only` feature flag and CI matrix for the SIMD path"
- "Convince me this `unsafe` block is actually necessary"
- "Is the unsafe in this dependency reachable from our public API?"
- "Pre-release soundness gate for this crate"
- "Build a verification harness with miri, loom, fuzz, mutants, and geiger"
- "Harden SAFETY comments for every remaining unsafe site"
- "Three-bucket the unsafe in this project: unavoidable, perf-only, refactorable"
- "Three-bucket-classify this project's unsafe"
- "Pin migration to pin-project-lite for these futures"
- "Replace `mem::transmute` with `zerocopy`"
- "Replace `MaybeUninit::assume_init` with safe initializer"
- "I want a defensible audit I could show another senior Rust engineer"

## Trigger phrases that should NOT activate this skill

- "How do I write unsafe code?" — general Rust question, not an audit
- "What is the borrow checker?" — Rust 101 question
- "Add a new feature to my Rust project" — generic dev request, not soundness-focused
- "Generate Rust documentation" — different skill (documentation-website-for-software-project)

## Smoke test on a tiny crate

A 30-second sanity check that the skill loads and the phase 0 + phase 1 scripts work:

```bash
# 1. Create a tiny test crate with a known unsafe site
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
    // (C) candidate — should be u32::from_be_bytes
    unsafe { std::mem::transmute::<[u8; 4], u32>(b) }.to_be()
}

pub fn first_byte_unchecked(s: &[u8]) -> u8 {
    // (B) candidate — get_unchecked vs bounds-check
    // SAFETY: caller must ensure s.len() >= 1
    unsafe { *s.get_unchecked(0) }
}

unsafe impl Send for MyHandle {}
pub struct MyHandle {
    inner: *const u8,  // (likely C) — newtype the raw pointer
}
EOF

cargo build || echo "(build failure expected — toy crate)"

# 2. Run the skill's enumeration on this crate
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"
if [ ! -d "$SKILL" ] && [ -d "$HOME/.codex/skills/rust-unsafe-code-exorcist" ]; then
  SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
fi
if [ ! -d "$SKILL" ]; then
  echo "Set SKILL=/path/to/rust-unsafe-code-exorcist and re-run this smoke test." >&2
  exit 2
fi
mkdir -p /tmp/exorcist-smoke/.unsafe-audit
$SKILL/scripts/check-skills.sh /tmp/exorcist-smoke/.unsafe-audit
$SKILL/scripts/install-toolchain.sh --check /tmp/exorcist-smoke/.unsafe-audit
$SKILL/scripts/detect-mode.sh /tmp/exorcist-smoke
$SKILL/scripts/enumerate-unsafe.sh /tmp/exorcist-smoke /tmp/exorcist-smoke/.unsafe-audit
node $SKILL/scripts/generate-inventory.mjs /tmp/exorcist-smoke/.unsafe-audit

# 3. Verify the inventory has at least the expected sites
cat /tmp/exorcist-smoke/.unsafe-audit/unsafe-inventory.jsonl | wc -l
# Expected: at least 3 rows (from_be_unsafe transmute, get_unchecked, unsafe impl Send)

jq . /tmp/exorcist-smoke/.unsafe-audit/unsafe-inventory.jsonl
```

If the above succeeds AND the inventory contains at least the three expected sites, the skill's Phase 1 plumbing is working.

A full audit on this toy crate would proceed through Phases 2-10. The expected outcomes:
- site for `transmute` → (C); rewrite to `u32::from_be_bytes`.
- site for `get_unchecked` → (B) or (C) depending on benchmark; with such a simple loop, LLVM autovec usually graduates it to (C).
- `unsafe impl Send` → (C); newtype the `*const u8` field per pattern P-2 in `10-POINTER-MIGRATIONS.md`.

## End-to-end smoke (full audit, ~30 min on tiny crate)

Once the user confirms the smoke above works, an end-to-end run is:

```bash
# Invoke the skill via the Skill tool / slash command:
#   /rust-unsafe-code-exorcist /tmp/exorcist-smoke
#
# Or programmatically (orchestrator-driven):
Agent({
  description: "rust-unsafe-code-exorcist on exorcist-smoke",
  subagent_type: "general-purpose",
  prompt: "Run the rust-unsafe-code-exorcist skill on /tmp/exorcist-smoke. Use audit-only mode, full toolchain profile, 5% perf budget. Audit dir: /tmp/exorcist-smoke/.unsafe-audit."
})
```

Expected outcome:
- `<audit-dir>/AUDIT_SUMMARY.md` exists with the tally line.
- `<audit-dir>/verify.sh` exists and exits 0.
- `<audit-dir>/.beads/` exists with at least 1 epic + 3 task beads.
- `<audit-dir>/REVIEWER_RESPONSES.md` exists with `Confidence: Medium` or `High`.

## Cleanup

Leave `/tmp/exorcist-smoke` in place unless the human/project owner explicitly
asks you to remove it. The directory is useful for inspecting generated
`.unsafe-audit/` artifacts after the smoke run, and agents should not run
cleanup commands automatically.
