# Skills Cross-Reference Matrix

Every methodology piece in this skill is informed by one or more adjacent skills. This matrix lets you trace any decision back to its origin.

When you find yourself wondering "why did we do it this way?", look up the methodology piece in the left column; the right column tells you which adjacent skill to consult for deeper rationale.

| Methodology piece | Informed by | What we adopted |
|-------------------|-------------|-----------------|
| KERNEL.md (axioms) | `operationalizing-expertise` | The kernel-as-lens pattern; axioms numbered 0–N; citation discipline (Q-NNN) |
| CORPUS.md | `operationalizing-expertise` | The 7-layer corpus; named, citable, enumerable |
| QUOTE-BANK.md | `operationalizing-expertise` | Stable Q-NNN IDs; never reuse retired IDs |
| OPERATORS.md (cognitive moves) | `operationalizing-expertise` | The "operators are moves not rules" framing; per-operator triggers + failure modes |
| SCORING-RUBRIC.md | `agent-ergonomics-and-intuitiveness-maximization-for-cli-tools` | The 0/250/500/750/1000 anchor pattern; per-dimension weighting |
| PHASES.md (10-phase loop) | `codebase-archaeology` (Phase 1) + `codebase-report` (Phase 3) + `multi-pass-bug-hunting` (Phase 7) | Archaeology shape; synthesis chapters; audit-fix-rescan loop |
| AGENT-PROMPTS.md (calibrated prompts) | `multi-pass-bug-hunting` | The three verbatim fresh-eyes prompts |
| PHASES.md § Phase 0 cass mining | `cass` | The `--robot --limit --days` query shape; classification by KIND |
| MUTATE-CHOKEPOINT.md | `dcg` (block-with-redirect philosophy) + `slb` (two-person rule) | Single chokepoint, mandatory backup, audit trail |
| AGENT-MAIL-INTEGRATION.md | `agent-mail` | File reservations, threaded coordination, pre-commit guards |
| BEADS-INTEGRATION.md | `beads-br` + `beads-bv` | Bead-driven Phase 4; bv-triage at dispatch |
| TESTING-INTEGRATION.md | `testing-fuzzing`, `testing-metamorphic`, `testing-conformance-harnesses`, `testing-golden-artifacts`, `testing-real-service-e2e-no-mocks` | Phase 5.2–5.6 extension layers |
| TRIANGULATION.md | `multi-model-triangulation` | The three-model harness; verbatim disagreement reporting |
| ABSORB-PLAYBOOK.md mode | `fixing-beads-problems` (canonical example) | Step-by-step playbook → (detector, fixer, fixture) tuple |
| Cookbook Pattern 4 (daemon CLI) | `ntm`, `wezterm`, `mcp_agent_mail_rust` | Daemon liveness probing; socket health; pidfile discipline |
| Cookbook Pattern 5 (installer) | `installer-workmanship`, `dsr` | Trust-manifest pattern; bundled signing key; reinstall-from-bundle |
| Cookbook Pattern 7 (AI-agent CLI) | `caam`, `cass`, `cass-memory`, `ntm` | Agent-session subsystem; account/credential FMs |
| Cookbook Pattern 9 (distributed) | `wrangler`, `vercel`, `gh`, `gcloud`, `stripe-cli` | Auth-state, vendor-drift, rate-limits subsystems; `--online` opt-in |
| Cookbook Pattern 14 (build-system) | `cargo`, `rustup`, `npm` patterns | Lockfile drift, cache integrity, phantom deps |
| Cookbook Pattern 15 (compliance) | `security-audit-for-saas`, `reporting-sensitive-encrypted-gh-issues` | Audit-export, regime-specific detectors |
| GROWTH-LADDER.md (stages) | `agent-fungibility-philosophy` (interchangeable agents per stage) + `flywheel` | Per-stage minimum-viable artifact; pass cadence |
| ETIQUETTE.md (multi-agent) | AGENTS.md § Codex/GPT-5.5 (Q-009) + `agent-mail` + `vibing-with-ntm` | "Multiple agents per minute" reality; reservation discipline |
| METRICS.md (observability) | `extreme-software-optimization` (profile-driven) + `profiling-software-performance` | Per-tier latency budgets; p95 metrics; profile-guided detector selection |
| PERFORMANCE.md | `extreme-software-optimization` | Hot-path discipline; lazy-init; bounded scans |
| SECURITY.md | `security-audit-for-saas` + `dcg` + `slb` + `reporting-sensitive-encrypted-gh-issues` | Three risk classes; redaction set; audit checklist |
| VERSIONING.md | AGENTS.md § Backwards Compatibility (Q-004) | No-shims-long-term; major bumps over forever-back-compat |
| ADVERSARIAL-REVIEW.md (18 attack scenarios) | `multi-pass-bug-hunting` + `mock-code-finder` + `dcg` | Audit-fix-rescan loop applied to specific attack classes |
| STATE-MACHINE.md | `lean-formal-feedback-loop` (formal state-machine reasoning) | FSM-as-checklist for Phase 7 review |
| ORCHESTRATION.md (tiers) | `multi-agent-swarm-workflow`, `flywheel-with-two-agents-per-repo`, `open-beads-weighted-tmux-agent-sessions` | Solo / Pair / Squad / Swarm tiering |
| Phase 8 pre-commit hook | `cc-hooks` | PreToolUse hook discipline; idempotent install |
| Phase 8 CI workflow | `gh-actions` | Workflow shape; release-train coupling |
| Phase 1 bug-tracker mining | `gh-cli` (`gh issue list`) + `gh-triage-ru` | Bug-tracker FM source |
| Phase 7 UBS gate | `ubs` | Static-analysis gate before fresh-eyes-clean |
| Phase 10 idea-wizard | `idea-wizard` | Second-order improvements generator |
| OPS-RUNBOOK.md (cadence) | `release-preparations` + `commit-and-release` + `changelog-md-workmanship` | Quarterly pass cadence; release discipline; changelog hygiene |
| Pattern 12 (meta-doctor) | `mock-code-finder` (skill validators) + general skill-authoring discipline | Recursive validator; bidirectional cross-references |
| skill-card.md (one-page elevator) | `readme-writing` | Hero section, feature table, quick-start |
| MEMORY discipline (when ops-runbook persists) | `cass-memory` (CASS Memory System) | Procedural memory across passes |
| FIRST-PRINCIPLES.md (rationale) | `operationalizing-expertise` + decision-theoretic / formal-rigor literature | Per-axiom failure-motivation + alternative-considered + corpus citation |
| Multi-binary recipe shared library | `flywheel-connector-final-testing` (cross-binary integration tests) | doctor-core extraction discipline |
| Daemon-cli recipe `--watch` mode | `ntm`, `wezterm`, `vibing-with-ntm` | NDJSON streaming health |
| Property tests (testing-metamorphic) | `testing-metamorphic` + property-based testing literature | `fix(corrupt(x)) ≡ x` properties |
| Backups encryption (compliance) | `reporting-sensitive-encrypted-gh-issues` (X25519) | Backup encryption-at-rest patterns |
| `validate-skill.sh` meta-doctor | general skill-authoring discipline (frontmatter, cross-ref, Q-ID anchoring) | Cross-ref + Q-ID + frontmatter checks |

---

## Reverse-lookup: which skills DO I cite?

Every skill in the user's repo that this skill cites at least once:

```
agent-ergonomics-and-intuitiveness-maximization-for-cli-tools
agent-fungibility-philosophy
agent-mail
beads-br
beads-bv
cass
cass-memory
cc-hooks
changelog-md-workmanship
codebase-archaeology
codebase-audit
codebase-report
commit-and-release
dcg
dsr
extreme-software-optimization
fixing-beads-problems
flywheel
flywheel-connector-final-testing
flywheel-with-two-agents-per-repo
gh-actions
gh-cli
gh-triage-ru
idea-wizard
installer-workmanship
lean-formal-feedback-loop
mock-code-finder
multi-agent-swarm-workflow
multi-model-triangulation
multi-pass-bug-hunting
ntm
open-beads-weighted-tmux-agent-sessions
operationalizing-expertise
profiling-software-performance
release-preparations
reporting-sensitive-encrypted-gh-issues
security-audit-for-saas
slb
testing-conformance-harnesses
testing-fuzzing
testing-golden-artifacts
testing-metamorphic
testing-real-service-e2e-no-mocks
ubs
vibing-with-ntm
wezterm
```

That's 46 adjacent skills, each contributing at least one specific pattern, axiom, prompt, or check to this skill. The doctor methodology is genuinely the union of the user's tooling discipline; this matrix makes the genealogy explicit.

---

## When to consult this matrix

- **Onboarding a new maintainer.** Show them this matrix first; they understand provenance immediately.
- **Audit pass.** Verify each cited skill is still installed; if uninstalled, document the inline fallback.
- **Adding new methodology.** Before adding, check if an existing skill already informs the area; cite from it.
- **Removing methodology.** Before removing (per AGENTS.md no-delete, this is rare), check if any other skill depends on the cited piece.
