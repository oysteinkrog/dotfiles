# CALIBRATION-FRAMING.md — How to read deterministic-only false-closed counts

<!-- TOC: The problem | The 15/15 case study | The calibration prior | Headline reframing | calibrate-bottom-n.sh walkthrough | Decision tree | Anti-patterns -->

## The problem

When the audit pipeline runs in deterministic-only mode (Phase 4 / Phase 6 stubbed — typical for `run-pass.sh` and any pass that wasn't given LLM subagent access for compliance verification and test-depth measurement), the `false-closed` count in REPORT.md is an **upper bound on suspicion**, not a list of findings. Most flagged beads are pipeline artifacts — beads where:

- the spec was prose-style and the deterministic extractor couldn't pull out structured code/test artifacts;
- the theater scanner false-positive'd on idiomatic code (e.g. Rust `#[cfg(test)]`, bash `return 0`);
- the bead's evidence file was scanned without a Phase-4 LLM gatherer, so per-item `verdict` collapsed to `MISSING` for items that were actually fine.

If the user reads "153 false-closed beads (18% rate!)" and acts on it, they will create 153 completion-debt beads, drown their swarm in noise, and lose trust in the audit. Across actual runs of this skill, this has happened. The fix is **calibration framing**: never let the headline number stand alone.

## The 15/15 case study (beads_rust, May 2026)

### Initial pass output

```
Beads audited: 844
False-closed: 153 (18.1%)
Recommendation: DO NOT reopen the 153 flagged beads yet — this pass is
deterministic-only (Phase 4/6 stub).
```

The deterministic-only banner was present (good!), but the headline still drew the eye to "153 false-closed!". A user skimming the report would file 153 reopen tickets.

### Ground-truth investigation

The user manually inspected the **15 lowest-scoring** beads (scores 200–505). For each, they:

1. Read the spec.
2. Read the cited files.
3. Ran the tests.
4. Checked git log for fix commits.

**Result: 15 / 15 were SCORE FALSE POSITIVES.**

| Bead | Score | Real status | Why the audit got it wrong |
|------|------:|-------------|----------------------------|
| `aeb` | 200 | ✅ shipped | Spec mentioned "field_name=123" prose; extractor parsed `field_name` as a required source path → MISSING |
| `b9o` | 220 | ✅ shipped | Same as `aeb` |
| `ciu` | 280 | ✅ shipped | Same as `aeb` |
| `11n3` | 320 | ✅ shipped | Idiomatic `#[cfg(test)] mod tests { ... }` flagged as `conditional_skip_in_test_mode` MAJOR theater |
| `2f4x` | 380 | ✅ shipped | Same as `11n3` |
| `9yw1` | 410 | ✅ shipped | Same as `11n3` |
| `dwec` | 420 | ✅ shipped | Same as `11n3` |
| `149j` | 450 | ✅ shipped | Bash `return 0` in helper script flagged as `hardcoded_return` MAJOR theater |
| `jnxv` | 470 | ✅ shipped | Bead's `.beads/issues.jsonl` runtime data file scanned as source code → false BLOCKING findings |
| `nz0` | 480 | ✅ shipped | Same as `jnxv` |
| `zfz2` | 490 | ✅ shipped | Same as `jnxv` |
| `19my.x` | 500 | ✅ shipped | Cross-project bead pollution — beads_rust-19my.* references `/data/projects/ntm` paths |
| `lxn5` | 505 | ✅ shipped | Spec-vs-evidence ID-scheme mismatch; LLM-gatherer used `ac.X` while extractor used `code.primary` |
| `ifr7` | 505 | ✅ shipped | Same as `lxn5` |
| `2dccg.2.1` | 505 | ✅ shipped | Phantom spec items — `telemetry.primary`, `migrations.primary` marked MISSING when never required |

**Conclusion:** The deterministic baseline had 0/15 hit rate on the lowest-scoring band. Extrapolating: of the 153 flagged beads, **plausibly 5–10 are truly false-closed; the other ~145 are pipeline artifacts.**

The user wrote up the case study in `AUDIT_FINDINGS.md` and the lessons informed v1.1's bug fixes (idiomatic-Rust exclusions, `.beads/` path filtering, evidence-supersedes-spec fallback) and v1.2's calibration framing.

## The calibration prior

Based on the case study (and corroborated by similar runs in `coding_agent_session_search` and `remote_compilation_helper`), the empirical prior is:

> **In a deterministic-only pass with N flagged beads, expect ~10–25% to be true false-closed; the remaining ~75–90% are pipeline artifacts.**

The math behind master-report.py's calibration bullet:

```python
low  = max(1, N // 10)   # ~10% lower bound
high = max(low + 1, N // 4)  # ~25% upper bound
```

For N=153: plan for 15–38 true false-closed, not 153.
For N=42: plan for 4–10 true false-closed, not 42.
For N=10: plan for 1–2 true false-closed, not 10.
For N<5: prior is omitted (the formula would produce noise).

## Headline reframing

**Do NOT report:**

> "Your project has 153 false-closed beads — 18% of all closed beads are theater."

**Do report:**

> "The deterministic baseline flagged 153 beads for review. Across prior real-world runs of this skill, ~75–90% of such flags are pipeline artifacts (idiomatic code mistaken for theater, prose-style ACs the deterministic extractor couldn't parse, etc.). Plan for ~15–38 true false-closed beads, not all 153. I've generated a calibration spot-check for the 5 lowest-scoring beads at `<pass-dir>/calibration.md` — read it before recommending any reopens."

The reframing is the difference between:

- **Useless** ("the project is 18% broken — panic")
- **Actionable** ("the audit surfaced ~20 real issues; here's how to confirm before acting")

## `calibrate-bottom-n.sh` walkthrough

The driver: `scripts/calibrate-bottom-n.sh <project> <pass-dir> --n 5`. Reads REPORT.md's False-closed list, picks the bottom N (lowest score first, since those are the most likely to be real or the most likely to be artifacts), and emits `calibration.md` with one section per bead containing:

1. **Bead title + score + verdict + close reason + closed-at timestamp** — at-a-glance triage info.
2. **Commits referencing the bead's ID** — `git log --grep=<bead-id>`. If there are commits, the bead was *probably* implemented (commits don't lie about themselves; they lie about what they did). If there are zero commits, the bead is *more suspicious* but not necessarily false-closed (the project's commit-message convention may not include bead IDs).
3. **Cited files table** — every path in evidence.json with: does it exist? when was it first added? when was it last modified? If "exists ✓" + "first commit dated long before close_at" + "last commit dated near close_at", the bead's claimed implementation is plausible. If "exists ✗" or "first commit AFTER close_at", red flag.
4. **Missing items checklist** (verbatim from scorecard.md § Missing items) — the human-readable list of what the audit thinks is missing.
5. **Calibration verdict checkboxes** (TRUE false-closed / SCORE false positive / PARTIAL) — the orchestrator (or user) fills these in.

After calibration, the orchestrator knows which of the bottom-N are real. They re-run remediation only for the TRUE-false-closed cohort.

## Decision tree (after running calibrate-bottom-n.sh)

```
Read calibration.md for the bottom N flagged beads.
        │
        ▼
For each bead:
  - cited files exist? + commits reference the bead?
        │
        ├── YES + YES → SCORE false positive (95% likely)
        │              → mark in audit-policy.yaml#calibration_overrides
        │
        ├── YES + NO  → AMBIGUOUS — read close_reason; if "implemented per
        │              ticket" with no commit reference, project's commit-
        │              message convention is the issue, not the bead. Likely
        │              SCORE false positive.
        │
        ├── NO + YES  → suspicious — files don't exist but commits claim work.
        │              Files may have been moved/renamed. Read commit diffs.
        │              Likely PARTIAL — some refactor lost the original path.
        │
        └── NO + NO   → TRUE false-closed (genuinely missing). Reopen or
                       create completion-debt bead.
```

For N ≥ 50 flagged beads, calibrate the bottom 5 + 5 random + 5 in the middle band rather than all 50 — extrapolate from the sample.

## Anti-patterns

| ✗ | Why |
|---|-----|
| Reporting the raw flag count without calibration framing | The user has been burned by alarming-but-wrong headlines; this is now Hard Rule #3 |
| Skipping calibrate-bottom-n.sh because "the report already has a banner" | The banner is necessary but not sufficient — the user needs concrete bead-by-bead evidence to trust the calibration prior |
| Running calibration only when N > 100 | The prior framing applies at any N ≥ 5; for N < 5, the prior is noise but the spot-check is still cheap and worthwhile |
| Skipping calibration because the pass is "Comprehensive mode" | Comprehensive mode runs full Phase 4 and 6, which dramatically reduces false positives — but doesn't eliminate them. Always calibrate. |
| Trusting the orchestrator's gut over calibration.md | Calibration is the SAFETY NET specifically for cases where the gut would have said "yeah looks bad" — bypass it and you're back to the 15/15 problem |

## Cross-references

- **Always-on calibration recommendation:** [master-report.py § calibration bullet](../scripts/master-report.py)
- **The driver:** [scripts/calibrate-bottom-n.sh](../scripts/calibrate-bottom-n.sh)
- **Hard rule #3:** [SKILL.md § The Five Hard Rules](../SKILL.md#-stop--read-this-first-the-five-hard-rules)
- **Failure modes catalog:** [FAILURE-MODES.md](FAILURE-MODES.md) — many of the case-study patterns are documented here
- **Audit smells:** [AUDIT-SMELLS.md](AUDIT-SMELLS.md) — when the audit *itself* is sick (vs. when the project is sick)
