# Disagreement Register — RS-<YYYYMMDD>-<slug>

This file records ≥1 disagreement per pair of per-family distillations. Phase 6 cannot exit without ≥(N choose 2) entries where N = number of model families.

For 3 families (cc, cod, gmi), required: ≥3 entries.

---

## D-001: <one-line subject of disagreement>

**Distillations involved:** cc vs cod
**The point under dispute:** <one sentence>
**cc reading:** (cite by_cc.md § X) <cc's view>
**cod reading:** (cite by_cod.md § Y) <cod's view>
**Chosen synthesis:** <which view, or new synthesis>
**Reasoning for synthesis:** <one paragraph>
**Operator that surfaces this disagreement:** <which Brenner operator's lens makes the disagreement visible>

---

## D-002: <one-line subject>

**Distillations involved:** cc vs gmi
**The point under dispute:** <one sentence>
**cc reading:** (cite by_cc.md § X) <cc's view>
**gmi reading:** (cite by_gmi.md § Y) <gmi's view>
**Chosen synthesis:** <...>
**Reasoning for synthesis:** <one paragraph>
**Operator that surfaces this disagreement:** <...>

---

## D-003: <one-line subject>

**Distillations involved:** cod vs gmi
**The point under dispute:** <...>
**cod reading:** (cite by_cod.md § X) <cod's view>
**gmi reading:** (cite by_gmi.md § Y) <gmi's view>
**Chosen synthesis:** <...>
**Reasoning for synthesis:** <one paragraph>
**Operator that surfaces this disagreement:** <...>

---

(Add more entries as discovered.)

---

## Anti-pattern check (run before exit)

- [ ] Each pair of distillations has ≥1 disagreement entry: <yes/no>
- [ ] No entry is "trivial" (typo / wording-only). <yes/no — list violators>
- [ ] No entry is rationalized by averaging without choosing. <yes/no>
- [ ] Each entry cites specific sections of the per-family distillations. <yes/no>

If any answer is "no", the register is not yet complete. Phase 6 cannot exit.

---

## Validation

```bash
./scripts/disagreement-register-lint.sh
```

Must exit 0. Otherwise, re-run MO-06b-meta-synthesize.md.
