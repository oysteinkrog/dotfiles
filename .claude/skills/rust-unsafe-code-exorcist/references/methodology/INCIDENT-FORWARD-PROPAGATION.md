# INCIDENT-FORWARD-PROPAGATION.md — One Incident, Multiple Fixes

When an incident reveals a soundness obligation was violated, the audit's discipline says: find every OTHER site with the SAME obligation and verify it holds there too.

This is the principle: one bug found means many similar bugs may exist. Forward-propagate the lesson.

---

## The propagation protocol

```
1. Incident IDENTIFIES the soundness obligation violated.
   - From incident-rca.md § "Invariant violated".

2. Find every site with a SIMILAR obligation.
   - Search by:
     a. Same obligation keyword (e.g., "null-terminated CStr").
     b. Same FFI call (e.g., other libc::* functions that take char*).
     c. Same kind (e.g., other unsafe impl Send on raw-pointer field).

3. Per sibling site, verify the obligation holds.
   - Either: the obligation is enforced (sound).
   - Or: it's violated (file a bead; another incident-in-the-making).

4. File propagation findings.
   - File adjacent-to-incident-NNN beads.
   - Update audit's soundness-surface to reflect new findings.
   - Update SECURITY.md if findings are externally visible.
```

---

## Example

```
Incident: CVE-2026-NNNN
RCA: parse_jwt(empty_token) caused UB because the unsafe block
     assumed token.len() >= 16 but no validation was in the safe wrapper.

Soundness obligation: "input slice has length >= 16 before unchecked indexing."

Propagation: search for ALL `unsafe { *buf.get_unchecked(N) }` or similar:
  - parse_jwt: VIOLATED → original incident.
  - parse_header: enforced via let _ = buf.get(15)?; (sound).
  - read_record: NOT enforced! Same pattern; same bug. New finding.
  - write_field: enforced via assert!(buf.len() >= 16); (sound).

Result:
  - Incident: CVE-2026-NNNN (parse_jwt) — fix shipped.
  - Adjacent bead: read_record has the same obligation gap.
    File adjacent-to-incident-NNN bead; priority P0; treat like a CVE-in-waiting.
```

The propagation pass turned ONE incident into TWO fixes.

---

## How to search for sibling sites

The audit has multiple search vectors:

### 1. By obligation keyword

The incident's RCA documents the obligation. Grep for it in other write-ups:

```bash
# Find sites whose write-ups mention the same kind of invariant
grep -lE "null.terminated|CStr" <audit-dir>/audit/sites/**/*.md
```

Sites mentioning the same invariant are candidates.

### 2. By unsafe-kind + FFI call

If the incident is in an FFI call, find every other site calling the same FFI:

```bash
# Find every site calling libc::open
ast-grep run -l Rust -p 'libc::open($$$)' <project>/src --json | jq -r '.[].file'
```

Cross-reference with the audit's inventory.

### 3. By pattern signature

If the incident's site matches a pattern from `EXEMPLAR-CATALOG.md` or [COMMON-FAILURE-CASES.md](COMMON-FAILURE-CASES.md), search for other sites of the same pattern:

```bash
# Find all sites matching F-001 (use-after-free in arena pointer)
grep -l "F-001" <audit-dir>/audit/sites/**/*.md
```

### 4. By soundness-surface adjacency

If the incident is on a soundness-surface entry, find sibling pub API paths:

```bash
# Find all pub APIs in the same module + nearby modules
jq -r '.[] | select(.crate == "<incident-crate>") | .pub_api_path' \
   <audit-dir>/audit/synthesis/soundness-surface.md
```

Sibling pub APIs may inherit the same obligation.

---

## Per-sibling verification

For each candidate sibling site:

```markdown
## Verification: <sibling-site-id>

**Invariant.** <inherited from incident's obligation>

**Sibling site's write-up:** <link>

**Enforcement check.**
- Is the obligation enforced in the call graph? (run the operator ⊕ Reachability-From-Safe)
- Where? (cite line numbers)
- Does it match the incident's enforcement pattern, or differ?

**Verdict.**
- ENFORCED: sound. No action.
- NOT ENFORCED: FINDING. File adjacent-to-incident-NNN bead.
- AMBIGUOUS: needs deeper review. File investigation bead.
```

---

## The adjacent-bead template

```bash
br create --title "adjacent-to-incident-<incident-id>: <sibling-site-id> shares obligation [PROPAGATION]" \
          --type bug --priority 0 \
          --description "$(cat <<EOF
Incident <incident-id> revealed obligation: <one-line>.

Sibling site: <sibling-site-id> at <file>:<line>.

The sibling site has the SAME obligation BUT:
<NOT ENFORCED / ENFORCED DIFFERENTLY / ENFORCED BUT WITH GAP>

Per [INCIDENT-FORWARD-PROPAGATION.md], this is a CVE-in-waiting if it remains unaddressed.

Recommendation:
- Fix using the same approach as <incident-id>.
- Add regression test: tests/regression_adjacent_<sibling-id>.rs.
- Document in audit/synthesis/forward-propagation.md.

Cross-reference:
- Incident RCA: audit/incident-rca.md
- Sibling site write-up: <link>
- Pattern bundle: <link>
EOF
)"
```

The bead is P0 because adjacent-to-incident findings are urgent (they're known-vulnerable).

---

## Forward-propagation summary doc

`<audit-dir>/audit/synthesis/forward-propagation.md`:

```markdown
# Forward Propagation

For each closed incident, the search for sibling sites with the same obligation.

## Incident CVE-2026-NNNN

**Obligation.** "input slice has length >= N before unchecked indexing."

**Search vectors used.**
- Keyword "get_unchecked"
- FFI call libc::read
- Pattern F-008 (provenance violation)

**Sibling sites found.**
- site-0142 (in parse_jwt): the original incident.
- site-0421 (in read_record): NOT ENFORCED — file adjacent-bead.
- site-0203 (in write_field): ENFORCED via assert! — sound.
- site-0890 (in cache_lookup): ENFORCED via type system (BoundedU8) — sound.

**Beads filed.**
- adjacent-to-incident-2026-NNNN-1: site-0421 (read_record).

**After fix:**
- site-0421's adjacent-bead resolved in v<X.Y.Z+1>.
- All sibling sites verified sound.

## Incident CVE-2025-MMMM

...
```

The doc is auto-updated after each incident's propagation pass.

---

## When propagation finds nothing

A clean propagation (no sibling sites with the same gap) is a STRONG signal:

- The audit's existing analysis identified the obligation pattern at every site.
- The incident was a one-off, not a systemic gap.

Document the clean pass: "Forward propagation for incident NNN found no adjacent sites; the pattern was uniquely violated at the incident site."

---

## Continuous-mode + propagation

In continuous mode, when a drift event matches an existing incident's signature:

- Auto-link to the incident's RCA.
- Auto-file adjacent-bead with priority inherited from the incident.

This prevents drift from re-introducing the obligation gap that was once an incident.

---

## When the audit didn't catch the propagation gap

Sometimes the audit's classification of a sibling site was wrong; the incident reveals it. In that case:

- Reclassify the sibling site.
- Update the audit's CLASSIFICATION-RUBRIC if a new failure mode was discovered.
- Update OPERATORS.md if a new operator would have helped.
- File a `audit-improvement-<ID>` meta-bead documenting the gap in the audit's own methodology.

The audit improves by recording its own misses.

---

## Acceptance signal

Forward propagation is healthy when:

1. Each closed incident has a `forward-propagation.md` entry.
2. Every adjacent-bead is filed within 7 days of the incident's RCA completion.
3. The audit's coverage of "this kind of obligation" is documented after each propagation.
4. Continuous mode wires incident signatures into drift detection.

One incident, multiple fixes. The audit's institutional learning compounds.
