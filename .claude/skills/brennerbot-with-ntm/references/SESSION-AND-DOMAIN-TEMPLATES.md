# SESSION-AND-DOMAIN-TEMPLATES.md — Reusable Configuration for New Sessions

<!-- TOC: Why templates | Session templates | Domain templates | Template composition | Per-archetype template library | Authoring custom templates | The template-version contract | Anti-patterns | Cross-references -->

Every brennerbot session starts with the same 80% configuration: same kickoff structure, same canonical 5-role roster, same archetype-specific framing patterns, same Phase 1 framing rigor. The remaining 20% is the question itself.

**Session templates** capture the 80% so the operator only writes the 20%. **Domain templates** capture per-archetype refinements so questions in known domains get domain-specific guidance.

Without templates, every session re-invents the bootstrap; with them, sessions are faster, more consistent, and cross-comparable.

Mined from `/dp/brenner_bot/CHANGELOG.md` v0.2.0 § Add session template system + Add domain templates.

---

## Why templates

Three failures of bootstrap-from-scratch:

1. **Inconsistent framing** — operator A writes 5-line intake; operator B writes 80-line intake; cross-session diff impossible
2. **Repeated work** — same archetype runs same patterns; manual re-creation each time
3. **Domain-specific patterns lost** — operator A learned what works for A4 incidents; operator B starts cold

Three benefits of templates:

1. **Stable bootstrap** — every session of a given archetype starts the same way
2. **Reusable expertise** — domain knowledge encoded into the template
3. **Cross-session diffability** — structurally-identical sessions diff cleanly

---

## Session templates

A session template captures: kickoff structure, recommended roster, default archetype, default tier, default operating mode.

```typescript
interface SessionTemplate {
  id: string;                  // unique identifier
  name: string;                // display name
  description: string;         // when to use
  archetype: string;           // A1-A10
  tier_default: 1 | 2 | 3 | 4 | 5;
  mode_default: string;        // "fresh-question" | "code-investigation" | etc.
  roster_preset: string;       // links to AGENT-ROSTER-AND-PRESETS.md preset
  kickoff_sections: KickoffSectionTemplate[];
  recommended_excerpts: string[];   // §-anchors to include by default
  recommended_operators: string[];  // operators most relevant
  recommended_jargon: string[];     // jargon to inject in MOs
  default_constraints?: string;
  default_outputs?: string;
}

interface KickoffSectionTemplate {
  heading: string;
  required: boolean;
  template_text?: string;      // placeholder text with {{ vars }}
  guidance?: string;           // what to fill in
}
```

Example template:

```yaml
id: tmpl-A4-incident-investigation
name: "Incident Investigation Template"
description: "Production-incident investigation; ≤60 min; Pair tier"
archetype: A4
tier_default: 2
mode_default: incident-investigation
roster_preset: preset-incident-pair
kickoff_sections:
  - heading: "Research Question"
    required: true
    template_text: "What caused {{ symptom }} starting at {{ time }}?"
    guidance: "Specific symptom + start-time; not 'why is the system slow'"
  - heading: "Context"
    required: true
    template_text: |
      Symptom: {{ symptom }}
      Detection: {{ detection_source }}
      Severity: {{ severity }}
      Affected: {{ affected_systems }}
    guidance: "Concrete observables; not narrative"
  - heading: "Excerpt"
    required: true
recommended_excerpts: [§99, §103, §147]
recommended_operators: ["⊘ Level-Split", "⌂ Materialize", "✂ Exclusion-Test"]
recommended_jargon: ["digital-handle", "third-alternative", "potency-check"]
default_constraints: "Wall-time ≤60min; HITL pauses at Phase 5+7"
default_outputs: "INCIDENT-VERDICT.md (compressed); post-mortem trigger if T4+"
```

Operator usage:

```bash
brenner session create \
  --template tmpl-A4-incident-investigation \
  --vars symptom="p99 latency >2s" \
        time="2026-03-01T14:00Z" \
        detection_source="Prometheus alert" \
        severity="critical" \
        affected_systems="api-gateway, billing-service"
```

The template's placeholders get filled; the resulting kickoff is consistent across all incident-investigation sessions.

---

## Domain templates

Domain templates layer on top of session templates with **field-specific** guidance:

```typescript
interface DomainTemplate {
  id: string;
  name: string;
  description: string;
  domain: string;              // "psychology" | "epidemiology" | "biology" | etc.
  hypothesis_examples: string[];   // exemplar Hs from domain
  test_design_patterns: string[]; // domain-specific test strategies
  confound_library: string[];   // confound IDs (per DOMAIN-AWARE-CONFOUND-DETECTION.md)
  domain_jargon: string[];      // domain-specific terms
  recommended_evidence_sources: string[];   // where to find EV
}
```

Example: biology-domain template:

```yaml
id: domain-biology
name: "Biology Research Domain"
description: "For experimental biology research questions"
domain: biology
hypothesis_examples:
  - "PAR proteins establish A-P polarity through cortical flows"
  - "MOM-2/Wnt signal from P2 polarizes EMS blastomere"
test_design_patterns:
  - "Single-gene RNAi for loss-of-function"
  - "Mosaic analysis for cell-autonomous testing"
  - "Domain swaps for protein-function dissection"
confound_library:
  - "batch_effects"
  - "genetic_background_confounding"
  - "off_target_effects"
domain_jargon:
  - "C. elegans"
  - "morphogen"
  - "embryogenesis"
  - "RNAi"
  - "mosaic analysis"
recommended_evidence_sources:
  - "WormBase"
  - "PubMed"
  - "domain-specific journals"
```

Per DOMAIN-AWARE-CONFOUND-DETECTION.md: domain templates feed the confound detector with domain-specific patterns.

---

## Template composition

Templates compose: a `SessionTemplate` + `DomainTemplate` + question content = full kickoff.

```
SessionTemplate (tmpl-A4-incident-investigation)
  + DomainTemplate (domain-distributed-systems)
  + question content (operator-supplied)
  = full kickoff prompt
```

The composition order:
1. Session template fills structure (kickoff sections, roster, mode)
2. Domain template fills field-specific guidance (jargon, confounds, evidence sources)
3. Operator fills the unique content (the actual question, specific symptoms, context)

Conflicts resolved by precedence: operator > domain template > session template (operator overrides).

---

## Per-archetype template library

Per QUESTION-ARCHETYPES.md, each archetype has at least one canonical template:

| Archetype | Canonical templates |
|-----------|---------------------|
| A1 design-space | `tmpl-A1-design-decision`, `tmpl-A1-architecture-review` |
| A2 codebase | `tmpl-A2-bug-investigation`, `tmpl-A2-code-archaeology` |
| A3 methodology | `tmpl-A3-method-evaluation`, `tmpl-A3-replication-attempt` |
| A4 incident | `tmpl-A4-incident-investigation`, `tmpl-A4-post-mortem` |
| A5 research-strategy | `tmpl-A5-research-program-launch` |
| A6 adversarial | `tmpl-A6-threat-assessment`, `tmpl-A6-vulnerability-scan` |
| A7 decision | `tmpl-A7-recommendation-memo`, `tmpl-A7-buy-build-decide` |
| A8 governance | `tmpl-A8-policy-evaluation` |
| A9 retrospective | `tmpl-A9-quarterly-retro` |
| A10 forecast | `tmpl-A10-forecast-evaluation` |

Operators can list available templates:

```bash
brenner session templates list
brenner session templates list --archetype A4
brenner session templates show tmpl-A4-incident-investigation
```

---

## Authoring custom templates

For organizations with recurring question patterns, authoring custom templates pays off after ~5-10 sessions of the same shape.

```bash
# Create a template from a successful session:
brenner session templates extract --from-session RS-20260301-... --out tmpl-custom.yaml

# Edit the YAML; remove session-specific content; add placeholders
# Save and register:
brenner session templates register --file tmpl-custom.yaml

# Use the new template:
brenner session create --template tmpl-custom --vars ...
```

The `extract` command pulls structure from a known-good session — saves authoring work.

---

## The template-version contract

Templates are versioned (semantic versioning):

```yaml
id: tmpl-A4-incident-investigation
version: 1.2.0
schema_version: "v0.1"
```

Version bumps:
- **Patch (1.2.0 → 1.2.1)**: typo fixes, minor wording
- **Minor (1.2.0 → 1.3.0)**: new optional sections, new optional placeholders
- **Major (1.2.0 → 2.0.0)**: required-field changes; existing sessions need migration

Per SESSION-REPLAY-AND-REPRODUCIBILITY.md: SessionRecord captures the template version used. Replay can target the same version to reproduce.

Per METHODOLOGY-EVOLUTION-LOG.md: template version changes are logged.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip templates; bootstrap from scratch every time | Inconsistency; cross-session diff impossible |
| Use a session template without a domain template (when domain template exists) | Missing domain-specific guidance |
| Edit a template mid-session | Session uses one version; template now another; replay broken |
| Author custom template without testing | Templates are reusable; bugs propagate |
| Override default constraints without documenting | OPERATOR-INTERVENTION-RECORDING.md severity: minor |
| Reuse template across very different archetypes | Per archetype templates exist for a reason |
| Treat templates as immutable | Iterate based on retrospectives (per PILOT-RETROSPECTIVE-PROTOCOL.md) |
| Hardcode operator-specific style in shared templates | Templates are organization-shared; personal style → operator-config |

---

## Composition with brennerbot

Templates integrate with:

- **AGENT-ROSTER-AND-PRESETS.md**: roster_preset reference
- **QUESTION-ARCHETYPES.md**: per-archetype canonical templates
- **DOMAIN-AWARE-CONFOUND-DETECTION.md**: domain template confound library
- **EXCERPT-FORMAT-AND-CORPUS-WORKFLOW.md**: recommended_excerpts
- **JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md**: recommended_jargon
- **MESSAGE-BODY-SCHEMA-PER-TYPE.md**: kickoff_sections fill the KICKOFF body
- **SESSION-REPLAY-AND-REPRODUCIBILITY.md**: template_version in SessionRecord
- **METHODOLOGY-EVOLUTION-LOG.md**: template-version-bump tracking

---

## Cross-references

- [AGENT-ROSTER-AND-PRESETS.md](AGENT-ROSTER-AND-PRESETS.md) — roster presets
- [QUESTION-ARCHETYPES.md](QUESTION-ARCHETYPES.md) — archetypes
- [ARCHETYPE-START-PACKS.md](ARCHETYPE-START-PACKS.md) — start packs
- [DOMAIN-AWARE-CONFOUND-DETECTION.md](DOMAIN-AWARE-CONFOUND-DETECTION.md) — domain confounds
- [EXTENDED-PROJECT-TYPES.md](EXTENDED-PROJECT-TYPES.md) — domain-specific adjustments
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — template version log
- /dp/brenner_bot/CHANGELOG.md v0.2.0 § Add session template system, domain templates — feature source
