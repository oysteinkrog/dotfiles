---
rubric_version: "security-heavy-1.0.0"
threshold: 750
score_threshold: 750
weights_by_type:
  security:
    implementation: 200
    tests:           350    # negative tests + revocation tests dominate
    anti_theater:    250    # mocks-where-forbidden = fatal
    test_depth:      150
    docs:             50
    integration:      0
  auth:
    implementation: 200
    tests:           350
    anti_theater:    250
    test_depth:      150
    docs:             50
    integration:      0
weights_by_label:
  critical-path:
    implementation: 350     # bump core for spine beads
  needs-runbook:
    docs:           250     # ops surface needs more docs
---

# Rubric — security-heavy variant

A bead can score 0–1000. The default rubric weights the 6 dimensions per
`assets/rubric-template.md`; THIS variant re-weights for projects with many
security/auth/crypto/webhook beads.

**Score bands** (same as default — change only via deliberate tuning):

| Band | Range | Verdict |
|------|------:|---------|
| 🟢 Verified | 950–1000 | Truly done. Ship-ready. |
| 🟢 Substantially complete | 850–949 | Minor gaps; document and move on. |
| 🟡 Partial | 700–849 | Acceptable for now; not "closed" caliber. |
| 🟠 False-closed (mild) | 500–699 | Status lies. Reopen or completion-debt. |
| 🔴 False-closed (severe) | 250–499 | Substantially fictional. Reopen. |
| 🚨 Theater | 0–249 | Implementation absent. Flag closer. |

## Default 6 dimensions (apply to non-security beads)

| Dimension | Max | What it measures |
|-----------|----:|------------------|
| Implementation completeness vs. spec | 300 | Code matches the spec |
| Required tests present and meaningfully passing | 250 | Tests exist, run, assert non-trivially |
| Anti-theater / no stubs / no mocks where forbidden | 150 | Zero TODOs, mocks-where-forbidden, etc. |
| Test depth | 150 | Coverage / fuzz / golden / e2e realism |
| Documentation, telemetry, migrations, feature flags | 100 | Non-code artifacts |
| Cross-bead integration & no contradictions | 50 | Contracts hold; siblings unbroken |
| **TOTAL** | **1000** | |

## Per-type overrides (frontmatter applies)

For `security` and `auth` beads, weights shift toward tests + anti-theater:

| Dimension | security/auth max | Default | Why |
|-----------|------------------:|--------:|-----|
| Implementation | 200 | 300 | Many security beads are config + glue, not lots of code |
| **Tests** | **350** | 250 | Negative tests, revocation tests, boundary tests dominate |
| **Anti-theater** | **250** | 150 | Mocks-where-forbidden in security tests is FATAL |
| Test depth | 150 | 150 | Same as default |
| Docs | 50 | 100 | Less weight on docs |
| Integration | 0 | 50 | Folded into tests |

## Threshold = 750 (vs default 700)

Security beads should not be merely "passing" — they should be high-confidence.
A 720 in the default rubric is a 🟡 Partial; in this variant it lands in
🟠 False-closed territory and forces reopen / completion-debt.

## Hard rules (in addition to the rubric)

- Any `security` / `auth` bead with a `BLOCKING` theater finding → score capped at 249 (Theater band) regardless of dimension scores.
- Any `webhook` bead lacking signature-verification evidence → automatic FAIL on dimension 1 (Implementation).
- Any `auth` / `crypto` bead claiming "mocked for tests" without explicit ADR justification → BLOCKING.

## What this variant does NOT change

- The 10-phase loop is unchanged.
- The convergence criteria are unchanged (±10 score delta, 0 new false-closed).
- The remediation policy default is unchanged (`completion-debt`).

## When to use

- Project's `security` / `auth` / `crypto` / `webhook` bead count > 30% of total
- Pre-launch security sign-off
- Annual SOC2 / HIPAA / PCI evidence cycle
- Post-incident hardening pass
