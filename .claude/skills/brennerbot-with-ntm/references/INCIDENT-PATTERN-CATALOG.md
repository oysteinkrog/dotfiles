# INCIDENT-PATTERN-CATALOG.md — Cross-Incident Pattern Catalog

This catalog collects patterns that recur across post-mortem-formalization sessions. Add an entry only after a pattern appears in at least three incidents or is severe enough that waiting would be irresponsible.

## Entry Template

```markdown
## IP-<NNN>: <short pattern name>

**First observed:** <ISO>
**Seen in sessions:** RS-..., RS-..., RS-...
**Severity band:** SEV-<1|2|3|4>
**Pattern type:** code | monitoring | process | training | vendor | unknown

### Signature

<What repeated symptom, timeline shape, or evidence pattern identifies this?>

### Common Contributing Factors

- <factor>
- <factor>

### Preventive Controls

- <control>
- <control>

### Playbook Changes

- <runbook / alert / test / owner change>

### Source Evidence

- <post-mortem path and section>
- <EV-NNN / log anchor>
```

## Open Entries

No cross-incident patterns have been promoted yet.
