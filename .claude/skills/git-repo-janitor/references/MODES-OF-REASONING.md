# Modes of Reasoning

Reading stances the skill can vary across phases or rounds to surface different classes of bugs. Adapted from `git-stash-janitor`'s MODES-OF-REASONING.md.

---

## The four core stances

### Literal

> "Treat every smell-tag rule as authoritative; trust the inventory; trust the reference graph."

**When useful:** Phase 4 (triage) — most candidates are well-behaved and the rules are right.

**Risk:** Misses cases where the heuristic is wrong (e.g., a `.skill-loop-progress.md` that's actually a manually-curated runbook).

**Prompt module:** "Apply the smell tags from FILE-SMELLS.md as written. Where the rules give a clear verdict, trust them."

---

### Skeptical

> "Assume the smell tags might be wrong; confirm via content."

**When useful:** Phase 4 for low-confidence rows; Phase 9 round 2.

**Risk:** Slower; over-thinks straightforward cases.

**Prompt module:** "For each candidate flagged with a smell, read the actual content. Is the smell consistent with what's inside? Surface any contradictions."

---

### Forensic

> "Reconstruct the file's intent: when was it created, by whom, why? What was its purpose?"

**When useful:** "Looks important but mislocated" rows (Phase 4 archaeologist subagent); Phase 6 commit-message authoring.

**Risk:** Goes deep on individual files; can run long.

**Prompt module:** "Trace the file's history via `git log --follow`. Read the introducing commit's message + the surrounding context. Synthesize: what was this file FOR when it was committed? Has its purpose been fulfilled by something else now?"

---

### Adversarial

> "Try to find a reason the proposed action is wrong. Hunt for subtle bugs."

**When useful:** Phase 9 round 3; Phase 5 plan review.

**Risk:** Can be paralyzing if not bounded.

**Prompt module:** "Adopt the perspective of someone who will discover this cleanup in 6 months and need to revert part of it. What would they wish had been caught now? Look for false-positive deletes, bad moves, .gitignore additions that mask important files. Cast a wider net."

---

## Stance composition per phase

The skill varies stance across phases to maximize coverage:

| Phase | Default stance | Comprehensive variation |
|-------|----------------|-------------------------|
| 1 Profile | Literal | + Forensic for archetype edge cases |
| 2 Inventory | Literal | (no variation) |
| 2.5 Secret scan | Adversarial | (always; secrets need adversarial framing) |
| 4 Triage | Literal (most rows); Skeptical (low-confidence rows) | + Forensic for "looks important but mislocated" |
| 5 Merge | Skeptical | + Adversarial cross-check on user overrides |
| 6 Apply | Literal | (no variation; deterministic execution) |
| 7 Apply | Adversarial pre-flight | (always; deletes are irreversible) |
| 8 Apply | Skeptical | + SHADOWING-AUDIT bias for any new pattern |
| 9 Fresh-eyes round 1 | Literal | (review what was done) |
| 9 Fresh-eyes round 2 | Forensic | (trace files, find missed refs) |
| 9 Fresh-eyes round 3 | Adversarial | (find what we got wrong) |

---

## When to switch stance

- **A user override on a high-confidence row** → re-classify with Skeptical stance; the override may signal a smell-rule blind spot.
- **A Phase 6 reference rewrite breaks the build** → switch to Forensic for that file (read the build, understand why).
- **Phase 9 round 1 is clean but the user feels uneasy** → run round 2 with Adversarial stance.
- **Phase 2.5 surfaces a borderline secret-suspect** → Forensic for provenance + Adversarial for "what if this is real?"

---

## Stance + multi-model triangulation

In Council tier, different models can be assigned different stances:

- **Claude (Opus): Forensic** — deep context, narrative reasoning.
- **Codex (GPT-5): Skeptical** — strong code reasoning, content-driven.
- **Gemini: Adversarial** — wide coverage, edge-case hunting.

The triangulator subagent prompts each model with its stance and consolidates verdicts. See [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md).

---

## A worked example

**Phase 4 borderline row:** `tests/fixtures/sample_log.txt` flagged as `coverage-output` with confidence 0.65.

- **Literal:** "Smell says coverage-output, no inbound refs in the build script — verdict: delete-and-gitignore."
- **Skeptical:** "Read the file content. It's actually structured log output with timestamps and PIDs. Does it look like coverage data or like a fixture for a parser test?" Discovers it's a parser-test fixture.
- **Forensic:** Runs `git log --follow tests/fixtures/sample_log.txt`. First commit: "feat: add log-format-parser with parser_test golden input". Verdict: keep-in-place; protected by reference from `tests/parser_test.rs`.
- **Adversarial:** "What if I delete this and the parser test breaks subtly?" Runs `cargo test parser_test` — confirms the test depends on the file.

The Skeptical and Forensic stances catch what Literal would have missed; Adversarial is the safety net.

---

## Operator + stance pairing

Some operators have a natural stance bias:

| Operator | Native stance |
|----------|---------------|
| ★ INVENTORY | Literal |
| 🔍 CLASSIFY-PURPOSE | Skeptical |
| 📍 LOCATE-PROPER-HOME | Literal (with archetype rules) |
| 💎 ASSESS-VALUE | Forensic |
| 🔗 REFERENCE-GREP | Literal (then Skeptical for context-checks) |
| 🛡 SHADOWING-AUDIT | Adversarial |
| ⬡ BUNDLE | Literal (deterministic execution) |
| ⚠ CONFIRM | Adversarial (assume the user might paste the wrong thing) |
| ↪ REWRITE-REFERENCES | Skeptical (verify each rewrite is right) |
| ⊟ REMOVE-WITH-RM | Adversarial (last-chance check) |
| ↺ WORKING-TREE-DRIFT | Forensic (understand what changed) |
| ⌘ HANDOFF | Literal (just report what happened) |

The skill applies the native stance unless the run-mode bumps it to a different stance.
