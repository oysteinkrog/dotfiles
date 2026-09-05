# Self-Test

Trigger phrases that should activate this skill. If any of these fail to wake the skill, tighten the description in SKILL.md frontmatter.

## Should trigger

- "Audit /data/projects/frankensqlite for undefined behavior"
- "Run a Miri sweep on this Rust repo"
- "Find every UB site in /data/projects/asupersync and fix the ones you find"
- "Soundness review of this `unsafe` module"
- "Hunt use-after-free in /data/projects/frankenfs"
- "Rustonomicon audit on this codebase"
- "Exorcise unsafe from this crate"
- "Run miri + loom + fuzz on this Rust project and tell me everything that's wrong"
- "Set up a UB-exorcism workspace for /data/projects/frankenlibc"
- "Apply the rust-undefined-behavior-exorcist skill to https://github.com/foo/bar"

## Should NOT trigger

- "Find every unsafe block in this project and add SAFETY comments" → use `/rust-unsafe-code-exorcist` (narrower in scope; SAFETY-comment focused)
- "Hunt for deadlocks" → use `/deadlock-finder-and-fixer`
- "Speed up the slow function" → use `/extreme-software-optimization`
- "Add tests to this Rust project" → use `/testing-fuzzing` / `/testing-metamorphic`
- "Review this PR" → use `/review`

The distinction between this skill and `rust-unsafe-code-exorcist`: this skill targets the *whole Rustonomicon UB taxonomy plus soundness-adjacent invariant drift* (data races, FFI contracts, validity invariants, unsafe library contracts, etc.), and includes the empirical-validation-then-remediation pipeline with experiment registry + beads handoff. The unsafe-code-exorcist focuses narrowly on `unsafe { ... }` block hygiene and refactoring.

## End-to-end smoke on a tiny repo

Create a 2-file dummy Rust project with one obvious UB:

```bash
mkdir -p /tmp/dummy-ub-project/src
cat > /tmp/dummy-ub-project/Cargo.toml <<'TOML'
[package]
name = "dummy-ub-project"
version = "0.1.0"
edition = "2021"
TOML
cat > /tmp/dummy-ub-project/src/lib.rs <<'RS'
/// Reads through a cast that strips constness — classic UB shape.
pub fn bad_mutation(p: &u32) {
    let q = p as *const u32 as *mut u32;
    unsafe { *q = 99; }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn smoke() {
        let x = 0u32;
        bad_mutation(&x);
    }
}
RS
cd /tmp/dummy-ub-project && git init -q && git add -A && git commit -q -m "init"
```

Invoke the skill with: "Audit /tmp/dummy-ub-project for undefined behavior in Quick mode". Expected:

1. Skill asks up-front confirmations (workspace dir, mode, toolchain install). Default workspace is `/tmp/dummy-ub-project/.ub-exorcism/<run-id>/`, not a sibling directory.
2. Phase 0 partition: a single section (`src`).
3. Phase 1 produces `phase1_unsafe_surface_inventory.md` with the `*q = 99` site tagged `aliasing` + `const-mutation`.
4. Phase 2 produces `phase2_findings_aliasing.md` and/or `phase2_findings_const-mutation.md` with the finding at MUST-BE-UB severity.
5. Phase 3 Miri (tree-borrows) reports UB on the `cargo test --doc`-extracted test.
6. Phase 4 synthesis writes `phase4_unified_findings.md` and `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` with EXP-001 for the const-mutation finding.
7. Phase 5 runs EXP-001 and records `CONFIRMED_UB`.
8. (Quick mode stops here.) Skill posts a summary; recommends Standard mode for full remediation.

A workspace with `phase1_unsafe_surface_inventory.md` AND `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` AND at least one `CONFIRMED_UB` verdict in the experiment registry is a successful Quick-mode smoke test.

## Validation

Run the writing-skills validator:

```bash
~/.claude/skills/writing-skills/scripts/validate-skill.py \
  /data/projects/je_private_skills_repo/.claude/skills/rust-undefined-behavior-exorcist/
```

Expected: zero errors. Some warnings are acceptable:
- SKILL.md may exceed 200 lines (matches documentation-website skill; depth is justified)
- Total tokens may exceed 5000 (this is a deep methodology skill)
