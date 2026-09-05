# Operator Glyph Cheatsheet (1-page)

The 19 cognitive-move glyphs from `references/methodology/OPERATORS.md`, compressed to a single page for printout / wall reference.

```
PILLAR                    GLYPH  NAME                       QUESTION
─────────────────────────────────────────────────────────────────────────────────────────────────────
all                        ★    PIN-REFERENCE-VERSION       "Does every artifact identify the reference version?"
surface                    ✦    ENUMERATE-SURFACE           "Is every pub item accounted for in FeatureUniverse?"
conformance                ◐    WIRE-ORACLE                 "Does the subject have an in-process / subprocess bridge to the pinned reference?"
perf                       ⬡    INSTRUMENT-HOT-PATH         "Does this loop have a counter that would attribute a regression to a specific frame?"
all                        ⚠    ESCALATE-TO-FRESH-REPRO     "Does the FailureBundle have seed + schedule_fp + repro_command + platform?"
all                        ⊕    ISOMORPHIC-REWRITE          "What are 2+ behavior-preserving rewrites, scored on the rubric?"
conformance                ⊙    DEBOUNCE-FALSE-POSITIVE     "Is this a TrueDivergence or one of the 5 false-positive classes?"
all                        ⊞    SOAK                        "Has this been run for the soak duration (24h / multi-day / multi-thousand-iter)?"
conformance                ⌘    REDUCE/MINIMIZE             "Has this been delta-debugged with the schema-preservation guard?"
perf                       ⟁    TRIANGULATE-PROFILE         "Do flamegraph + samply + dhat + strace agree on the attribution?"
perf                       ⤴    ATTRIBUTE-TO-MT8            "Does this kept win cite a specific frame ≥0.1% self-time?"
perf                       🔁   PASS-OVER-PASS-GATE         "Have both focused + broad gates moved in the same run window?"
all                        ⚖    RATCHET-LOWER-BOUND         "Does the proposed change raise the conformal LOWER bound without lowering any per-category bound?"
all                        🪟   FRESH-EYES                  "Have the 3 calibrated fresh-eyes prompts run, and the round come up clean twice?"
all                        🗄   LEDGER-RETIRE               "Does this ledger entry have a concrete retry-condition predicate (not 'later')?"
all                        🧪   EXPERIMENT-DESIGN           "Does this gap have hypothesis / repro / signal / falsifiability / invocation / results-inline?"
all                        📐   CONFORMAL-BAND              "Does the release decision use the LOWER bound and not the point estimate?"
ml/numerical               🎚   RAISE-ULP-TOLERANCE         "Has the ULP change been justified, scoped, and accompanied by gradcheck_max_rel_error?"
conformance                🪞   ENGINE-IDENTITY-GUARD       "Does every artifact carry Subject + Oracle identity strings, asserted distinct?"
```

## Composition cheat-sheet (one per common motion)

```
PERF REGRESSION:      ⚠ → 🗄 → ⬡ → ⤴ → ⟁ → 🧪 → ⊕ → ⚖ → 🪟
ORACLE DIVERGENCE:    ⚠ → 🪞 → ⌘ → ⊙ → 🗄 → 🧪 → ⊕ → ⚖
SURFACE GAP:          ✦ → 🧪 → ⊕ → ⚖ → 🪟
CV_PCT FLAKE:         ⚠ → 🔁 → ⟁ → 🗄 → ⊞
E-PROCESS REJECT:     ⚠ → 🪞 → ⌘ → ⊞ → 🧪 → 🗄
BOCPD SHIFT-DETECT:   ⊞ → ⚠ → ⌘ → 🧪
RATCHET BLOCK:        ⚖ → 🗄 → ⊕ → 🪟  (or waiver-author if eligible)
MT8 FLAT PROFILE:     ⤴ → (call /idea-wizard for structural redesign candidates)
```

Each operator card in `references/methodology/OPERATORS.md` carries its full prompt module + verbatim quote-bank anchor.
