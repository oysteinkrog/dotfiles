# PARSER-ROBUSTNESS-AND-LENIENT-TOLERANCE.md — Tolerate Hallucinations, Reject Silently-Dropping

<!-- TOC: Why parser robustness | The lenient-but-not-silent invariant | Per-format tolerance examples | Anchor format flexibility | Operator card parsing | Common agent hallucinations + handling | Anti-patterns | Cross-references -->

Agents hallucinate. They post inline JSON without fences, capitalize section names randomly, add fields that aren't in the schema. The parser must handle these gracefully — but **never silently drop content**.

This file specifies the **lenient-but-not-silent invariant**: accept common variations, normalize known mistakes, but loudly fail when content can't be parsed.

Mined from `/dp/brenner_bot/CHANGELOG.md` v0.3.0 § Parser Robustness and `README.md § Parser Robustness`.

---

## Why parser robustness

Three failures of strict parsing:

1. **Round drops** — pane posts a near-correct delta; strict parser rejects entire round; signal lost
2. **Format-evolution friction** — agents pick up format conventions from training; v0.1 strict rejects v0.2-style inputs
3. **Cascade failures** — one bad delta in a 10-delta message breaks all 10

Three failures of overly-lenient parsing:

1. **Silent drops** — parser extracts 0 deltas; round produces no artifact change; nobody notices
2. **Loose semantics** — parser accepts wrong values; downstream code sees plausible-but-wrong data
3. **Schema drift** — without strict validation, the schema accumulates de-facto extensions

The brennerbot pattern: **lenient parsing for known-tolerable variations**, **strict failure for ambiguous content**, **always loud about both**.

---

## The lenient-but-not-silent invariant

| Condition | Behavior |
|-----------|----------|
| Valid fence + valid JSON + valid schema | Apply silently |
| Valid fence + valid JSON + tolerable variation (e.g., `target_id` for ADD) | Normalize + warn |
| Valid fence + invalid JSON | Error: "JSON parse failed at line N" |
| Valid fence + valid JSON + invalid schema | Error: "missing required field `section`" |
| Missing fence + JSON-shaped content + DELTA prefix | **Error: "0 fenced delta blocks but DELTA prefix used"** |
| Missing fence + JSON-shaped content + no DELTA prefix | Warning: "appears to be a delta but no DELTA prefix" |
| Empty message body | Warning: "no content to parse" |

The invariant: **ambiguity is OK; silent-drop is not**.

Per DELTA-PROTOCOL-FAIL-FAST.md: this is the contract that prevents the inline-delta failure mode.

---

## Per-format tolerance examples

### `target_id` in ADD operations

Agents sometimes hallucinate IDs for new entities:

```json
{
  "operation": "ADD",
  "section": "hypothesis_slate",
  "target_id": "H7",   // <-- hallucinated; real ADD has null
  "payload": { ... }
}
```

Per parser logic:

```typescript
// ADD operations: target_id is normalized to null regardless of input
target_id: operation === "ADD" ? null : (typeof target_id === "string" ? target_id : null)
```

The hallucination is silently normalized. The compiler auto-assigns the next sequential ID. The agent's intent (add a new H) is preserved.

### Missing optional fields

Agent omits `rationale`:

```json
{
  "operation": "EDIT",
  "section": "hypothesis_slate",
  "target_id": "H2",
  "payload": { "confidence": "high" }
  // no rationale field
}
```

Parser: applies the EDIT; warns "rationale recommended"; doesn't fail. Per CITATION-PROVENANCE-RULES.md: rationale supports audit but isn't strictly required.

### Capitalization variations

Agent posts `**Definition**` and `**definition**` — operator-card parser handles both (case-insensitive).

### Field aliases

Agent posts `kill_reason` instead of `reason` (the canonical field):

```json
{
  "operation": "KILL",
  "target_id": "H1",
  "payload": {
    "kill_reason": "Contradicted by EV-002"   // <-- alias
  }
}
```

Per CHANGELOG.md v0.4.0 § Promote "reason" to first-class system field, remove kill_reason alias:

The migration was to **promote** `reason` and **remove** `kill_reason`. Lenient parsing during migration accepted both; current parser:
- `reason` is canonical
- `kill_reason` triggers a warning + normalization
- Both produce the same effect

This is the **migration discipline**: lenient during transition, strict after.

---

## Anchor format flexibility

Per `/dp/brenner_bot/README.md` § Parser Robustness:

```typescript
// Matches: §42, § 42, §42-45, § 42 - 45
const anchorPattern = /§\s*(\d+)(?:\s*-\s*(\d+))?/g;
```

Tolerated variations:
- `§42` (canonical)
- `§ 42` (whitespace after symbol)
- `§42-45` (range, no space)
- `§ 42 - 45` (range with spaces)
- `§42, §44` (multiple anchors)
- `§42-45, §50` (mixed range + single)

NOT tolerated:
- `§abc` (must be numeric)
- `§42.5` (subsection format requires explicit dot, not space)
- `[§42]` (bracket form not in canonical taxonomy)

Per CITATION-PROVENANCE-RULES.md: the canonical form is `§n` or `§n-§m`; whitespace is normalized away.

---

## Operator card parsing

The operator library (per OPERATORS.md) has flexible markdown parsing. Agent-authored operator cards may have:

- **Section boundaries**: lookahead patterns instead of strict `\n\n` (so single newlines work)
- **Optional backticks**: `` `tag` `` or `tag` both accepted in canonical-tag fields
- **Heading variations**: `## Definition`, `### Definition`, `**Definition**` all parsed

Why? Because operator cards are authored by humans + agents alike; rigid expected formatting blocks contributions that are otherwise correct.

But: per /dp/brenner_bot CHANGELOG mention "Update tests and regex for operator-library parsing" — the parser is tuned over time; hardening happens in tests, not by removing flexibility.

---

## Common agent hallucinations + handling

### Hallucination 1: Wrong section name

Agent posts `section: "hypothesis"` instead of `"hypothesis_slate"`:

| Parser response |
|---------------|
| Warn: "Unknown section 'hypothesis'; did you mean 'hypothesis_slate'?" |
| Suggest the canonical name |
| Fail the delta if no fuzzy-match found |

Per `/dp/brenner_bot/README.md`: the parser uses fuzzy-match heuristics for known section name typos.

### Hallucination 2: Confidence as `"very high"`

Agent posts `confidence: "very high"` instead of canonical `low | medium | high`:

| Parser response |
|---------------|
| Warn: "Non-canonical confidence value 'very high'; mapped to 'high'" |
| Apply the EDIT with normalized value |
| Log the normalization |

### Hallucination 3: `target_id` for ADD

Already covered above; silent-normalize to null.

### Hallucination 4: Missing `target_id` for EDIT or KILL

Agent posts EDIT or KILL without `target_id`:

| Parser response |
|---------------|
| **Error: "EDIT/KILL requires target_id"** |
| Reject the delta (don't silent-fail) |
| Surface the error in mail thread for sender |

This is **strict** because the operator's intent is genuinely ambiguous (which item to modify?).

### Hallucination 5: Multiple deltas in one fence

Agent crams 3 deltas into one ` ```delta ` block:

| Parser response |
|---------------|
| Try to parse as JSON array |
| If array: split into individual deltas; apply each |
| If single object with multiple operations: warn + try to expand |
| Per CHANGELOG: "Expand array payloads into individual ADD deltas" |

---

## The `reason` field normalization

Per CHANGELOG.md v0.4.0:
> Promote "reason" to first-class system field, remove kill_reason alias

Mid-migration parser handling:

```typescript
function extractReason(payload: any): string {
  // Canonical: payload.reason
  // Aliases (warn + normalize):
  //   - payload.kill_reason
  //   - payload.dismiss_reason
  //   - payload.reject_reason
  if (payload.reason) return payload.reason;
  if (payload.kill_reason) {
    console.warn("kill_reason deprecated; use reason");
    return payload.kill_reason;
  }
  // ... other aliases
  throw new Error("Required field 'reason' missing from KILL operation");
}
```

This **migrate-with-warning** pattern preserves backwards compatibility while pushing toward canonical form. Eventually the warnings get loud enough that agents update; aliases can be removed.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Strict parsing of every field; reject unknown | Loses tolerable variations; round drops |
| Silent acceptance of unknown fields | Schema drifts; downstream code breaks |
| Lenient acceptance of malformed JSON | Ambiguous intent; data corruption |
| Skip warnings for normalization | Agents don't learn canonical form |
| Treat all "wrong" inputs as parse errors | Fuzzy-match catches typos; reject only ambiguous ones |
| Build new parsers per format version | Maintain one parser with version-aware tolerance |
| Disable lenient parsing in tests | Tests should cover both canonical AND tolerated variations |

---

## Composition with brennerbot

Parser robustness integrates with:

- **DELTA-PROTOCOL-FAIL-FAST.md**: the lenient-but-not-silent invariant
- **OPERATORS.md**: operator card parsing tolerance
- **CITATION-PROVENANCE-RULES.md**: anchor format flexibility
- **TAXONOMIES-COMPLETE-CATALOG.md**: canonical values; aliases trigger normalization warnings
- **MESSAGE-BODY-SCHEMA-PER-TYPE.md**: subject prefix + body fuzzy-match

---

## Cross-references

- [DELTA-PROTOCOL-FAIL-FAST.md](DELTA-PROTOCOL-FAIL-FAST.md) — lenient-but-not-silent
- [CITATION-PROVENANCE-RULES.md](CITATION-PROVENANCE-RULES.md) — anchor format
- [TAXONOMIES-COMPLETE-CATALOG.md](TAXONOMIES-COMPLETE-CATALOG.md) — canonical values
- [OPERATORS.md](OPERATORS.md) — operator card format
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — alias-deprecation tracking
- /dp/brenner_bot/README.md § Parser Robustness — original source
- /dp/brenner_bot/CHANGELOG.md v0.3.0 § Parser Robustness — implementation milestone
- /dp/brenner_bot/CHANGELOG.md v0.4.0 § Artifact Merge & Delta Pipeline — `reason` promotion
