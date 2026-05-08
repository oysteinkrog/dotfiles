# Subagents for the Wills & Estate Planning Skill

Specialized subagents that the main skill can invoke (via the Agent tool) for specific tasks. Each subagent has a focused purpose and a prepared prompt template.

## Available Subagents

### intake-conductor
**Purpose:** Run the adaptive intake interview with the user.
**When invoked:** Phase 1 of the workflow; when user needs to be walked through intake questions.
**Input:** Current tier estimate, specific domain focus (e.g., "blended family"), or "full intake."
**Output:** Updated `intake/intake-record.md` plus an initial mode / overlay view.
**Prompt template:** See intake-conductor.md

### overlay-resolver
**Purpose:** Convert intake facts into a disciplined coverage map so the skill can show what was considered and why.
**When invoked:** At the start of any substantial engagement, or after facts change materially.
**Input:** Intake record, current mode, triggered overlays, project directory.
**Output:** `analyses/plan-coverage-matrix.md`.
**Prompt template:** See overlay-resolver.md

### document-organizer
**Purpose:** Inventory, categorize, and analyze documents in the user's project directory.
**When invoked:** Phase 2 after intake, or when user has just placed documents in the project folder.
**Input:** Project directory path.
**Output:** `analyses/current-document-audit.md`, `analyses/beneficiary-form-audit.md`, `analyses/titling-audit.md`, and updates to `analyses/coherence-audit.md` / `analyses/decision-ledger.md` when the evidence is strong enough to support them.
**Prompt template:** See document-organizer.md

### asset-discovery-auditor
**Purpose:** Find missing assets, liabilities, and weakly documented control points.
**When invoked:** Early inventory work, or whenever the plan is being built from memory.
**Input:** Project directory path + intake record.
**Output:** updates to `deliverables/asset-inventory.md`, plus `analyses/document-acquisition-plan.md` and `analyses/evidence-confidence-map.md`.
**Prompt template:** See asset-discovery-auditor.md

### beneficiary-audit
**Purpose:** Audit all beneficiary designations for coherence with will / trust.
**When invoked:** Part of Phase 4 validation.
**Input:** List of accounts (retirement, insurance, POD/TOD) + will / trust provisions.
**Output:** `analyses/beneficiary-form-audit.md`, updates to `deliverables/beneficiary-map.md`, and `deliverables/beneficiary-change-packet.md` when needed.
**Prompt template:** See beneficiary-audit.md

### tax-analyzer
**Purpose:** Analyze federal and state estate / gift / income tax implications of current plan.
**When invoked:** When planning approaches HNW tier, or specific tax question arises.
**Input:** Net worth, domicile, planned gifts, trust structure.
**Output:** `analyses/tax-exposure-analysis.md`, `analyses/liquidity-analysis.md`, updates to `analyses/recommendation-confidence-register.md`, and primary-source verification notes in `analyses/official-source-log.md`.
**Prompt template:** See tax-analyzer.md

### execution-formalities-router
**Purpose:** Identify which states' signing / attestation / e-will / TOD rules matter and turn them into an attorney-facing checklist.
**When invoked:** When a move, bedside signing, real-estate situs issue, or remote-execution question is in play.
**Input:** Domicile state, relevant property states, desired signing method.
**Output:** State-specific execution checklist + official-source log items + attorney questions.
**Prompt template:** See execution-formalities-router.md

### state-law-verifier
**Purpose:** Verify current law from primary official sources and produce an audit trail.
**When invoked:** Any time a volatile legal point affects the plan.
**Input:** Issue list + jurisdiction list.
**Output:** Verification memo + official-source-log entries + unresolved ambiguities.
**Prompt template:** See state-law-verifier.md

### fiduciary-bench-builder
**Purpose:** Compare realistic executor, trustee, guardian, and agent candidates rather than picking them by habit.
**When invoked:** Once people and family dynamics are known.
**Input:** Family map + current named fiduciaries + conflict context.
**Output:** `analyses/fiduciary-bench-scorecard.md`.
**Prompt template:** See fiduciary-bench-builder.md

### anti-pattern-scanner
**Purpose:** Scan current plan against the anti-patterns catalog and flag risks.
**When invoked:** Before finalizing plan, or on audit request.
**Input:** Current plan summary / documents.
**Output:** List of identified anti-patterns + severity + fixes.
**Prompt template:** See anti-pattern-scanner.md

### multi-model-validator
**Purpose:** Invoke the multi-model-triangulation skill to cross-check the plan against Codex, Gemini, Grok perspectives.
**When invoked:** For complex HNW plans before finalization.
**Input:** Plan summary + specific questions to validate.
**Output:** Consensus + disagreements + final recommendations, especially for ambiguous state-law edge cases, tax tradeoffs, and drafting-risk areas.
**Prompt template:** See multi-model-validator.md

### funding-checklist-generator
**Purpose:** Convert the legal plan into an implementation / trust-funding queue.
**When invoked:** After the structure is chosen, before final handoff.
**Input:** Plan summary + asset inventory + beneficiary map.
**Output:** `deliverables/implementation-ledger.md` plus sequencing notes that feed `deliverables/institution-contact-matrix.md`.
**Prompt template:** See funding-checklist-generator.md

### implementation-ops-planner
**Purpose:** Build the signing, funding, institution, and business-continuity execution layer.
**When invoked:** After the structure is chosen, before calling the plan complete.
**Input:** Plan report + inventory + beneficiary map + official-source log.
**Output:** The coverage-matrix-approved execution subset, typically including `deliverables/signing-readiness-checklist.md`, `deliverables/funding-proof-log.md`, `deliverables/institution-contact-matrix.md`, `deliverables/beneficiary-change-packet.md`, and `deliverables/business-continuity-activation.md` when needed.
**Prompt template:** See implementation-ops-planner.md

### conflict-prevention-planner
**Purpose:** Reduce litigation and family blowups through explanation, governance, and sequencing.
**When invoked:** Unequal inheritance, blended family, estrangement, or lumpy-asset cases.
**Input:** Family structure + intended dispositive plan.
**Output:** `deliverables/conflict-prevention-plan.md`, `deliverables/family-meeting-agenda.md`, and suggested language for `analyses/decision-ledger.md`.
**Prompt template:** See conflict-prevention-planner.md

### litigation-defense-reviewer
**Purpose:** Review the plan with adversarial eyes for contest, capacity, execution, and fiduciary-conflict risk.
**When invoked:** Unequal treatment, blended family, bedside signing, elder planning, or any high-conflict file.
**Input:** Plan report + coherence audit + conflict-prevention materials + family context.
**Output:** `analyses/litigation-risk-memo.md`.
**Prompt template:** See litigation-defense-reviewer.md

### deliverables-generator
**Purpose:** Generate the coverage-matrix-approved output packet from completed planning.
**When invoked:** Final phase of workflow.
**Input:** Complete intake + plan + analyses.
**Output:** The mode-appropriate final packet across `analyses/` and `deliverables/`, including attorney handoff materials where applicable.
**Prompt template:** See deliverables-generator.md

## How to Invoke

Within the main skill, the user (or the skill execution) can request:

```
/agent intake-conductor --mode=full-intake
/agent overlay-resolver
/agent document-organizer --path=.
/agent asset-discovery-auditor --path=.
/agent beneficiary-audit
/agent tax-analyzer --scope=federal+state
/agent execution-formalities-router --state=NY --property-state=FL
/agent state-law-verifier --issue="New York will execution and self-proving"
/agent fiduciary-bench-builder
/agent implementation-ops-planner
/agent funding-checklist-generator
/agent conflict-prevention-planner
/agent litigation-defense-reviewer
/agent anti-pattern-scanner
/agent multi-model-validator --question="Is SLAT appropriate for our situation?"
/agent deliverables-generator
```

Or the main skill can invoke them sequentially via the Agent tool.

## Architecture Note

These subagents are designed as prompt templates rather than separate executables. Each is a defined role with specific inputs/outputs that Claude can perform within the same conversation or delegate through the Agent tool.

## Workflow Note

For live-law questions, the subagent that makes the recommendation is also responsible for recording:

- what was verified,
- which official source was used,
- when it was verified,
- and any unresolved state-specific ambiguity

That record belongs in `analyses/official-source-log.md` so a future attorney or reviewer can audit the reasoning quickly.

## Cross-Reference

- Methodology: [PROMPTS.md](../references/methodology/PROMPTS.md), [INTERVIEW-FLOW.md](../references/methodology/INTERVIEW-FLOW.md)
- Templates: see /assets
