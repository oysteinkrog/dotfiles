# MO-hypothesis-pre-registration.md — Lock Falsifier Before Investigation

**Mode:** hypothesis-pre-registration (per EXTENDED-OPERATING-MODES.md)
**Phase:** between Phase 3 and Phase 4
**Operators activated:** ✂ Exclusion-Test (lock-in)
**Parameters:** `<SESSION_ID>`, `<COMMITMENT_DURATION>` (e.g., "until 2026-06-01" — when investigation may begin), `<WORKSPACE_PATH>`

---

You (the operator) are pre-registering the hypothesis slate + falsifiers BEFORE Phase 4 investigation. This protects against post-hoc rationalization of evidence — the falsifiers are committed to immutable record before any data is collected.

This is the scientific pre-registration norm applied to brennerbot.

---

**Step 1 — Verify Phase 3 is complete.**

```bash
[ -f <WORKSPACE_PATH>/.brenner_workspace/phase_3_complete.flag ] || { echo "Phase 3 not complete; cannot pre-register"; exit 1; }
```

The hypothesis slate must be locked. If panes are still proposing, abort and re-run Phase 3.

**Step 2 — Snapshot the slate.**

```bash
br list --label=hypothesis --status=open --json > intake/pre-registration-snapshot.json
sha256sum intake/pre-registration-snapshot.json | awk '{print $1}' > intake/pre-registration.hash
```

**Step 3 — Write pre-registration.md.**

```markdown
# Pre-registration — <SESSION_ID>

**Pre-registered at:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Snapshot hash:** <hash from .hash file>
**Investigation may begin:** <COMMITMENT_DURATION>

## Question of record (from intake/question_of_record.md)

<verbatim copy>

## Pre-registered hypothesis slate

(N hypotheses with locked falsifiers)

### H-001
- Claim: <claim>
- Mechanism: <mechanism>
- Falsifier: <falsifier — LOCKED>
- Expected evidence: <expected_evidence — LOCKED>
- Origin: <origin>
- Confidence at pre-registration: <confidence>

### H-002
...

(repeat for all Hs)

## Pre-registration rules

1. **Falsifier locking:** the `falsifier:` field on every pre-registered H is LOCKED. It cannot be relaxed, narrowed, or changed during Phase 4 investigation.

2. **Expected_evidence locking:** same.

3. **Hypothesis additions allowed but flagged:** new Hs added during Phase 4 are marked `origin:post-hoc` and treated with REDUCED weight in Phase 6 distillation.

4. **Hypothesis modifications:** if an H must be modified (e.g., refining the mechanism), file as a NEW H with `origin:refinement` and `parent:<original H-ID>`. Don't edit the pre-registered H in place.

5. **Verification:** Phase 7 audit explicitly compares pre-registered vs current; any modification to pre-registered Hs is a hard finding.

## Commitment

By pre-registering, the operator commits that:
- The current hypothesis slate represents genuine prior expectations
- Investigations will probe these specific falsifiers, not new ones invented after seeing data
- Any deviation will be explicitly documented in DRIFT-CHECK.md

This is an anti-bias protocol. Skipping or relaxing it post-hoc undermines the methodology.

---

**Lock signature:** <hash from intake/pre-registration.hash>
```

Save to `<WORKSPACE_PATH>/intake/pre-registration.md`.

**Step 4 — Commit immediately.**

```bash
cd <WORKSPACE_PATH>
git add intake/pre-registration.md intake/pre-registration-snapshot.json intake/pre-registration.hash
git commit -m "Pre-register hypothesis slate for <SESSION_ID> (locking falsifiers)"
```

The git commit timestamps the pre-registration at a specific point in time. Subsequent rewrites would require force-push (which AGENTS.md forbids without explicit approval).

**Step 5 — Optionally publish externally.**

For T4+ adversarial-context sessions, the operator may want to publish the pre-registration externally:

```bash
# Push the commit to a remote git repo:
git push origin main

# Or upload pre-registration.md to an OSF (Open Science Framework) project, GitHub gist, or similar
# This makes the pre-registration verifiable by external parties.
```

The published artifact creates a verifiable timestamp that the falsifier was committed BEFORE investigation, defending against post-hoc claims.

**Step 6 — Update phase0_scope_decision.md.**

```bash
cat >> .brenner_workspace/phase0_scope_decision.md <<EOF

## Pre-registration — $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Pre-registered: <N> hypotheses
- Snapshot hash: <hash>
- Mode: hypothesis-pre-registration
- Investigation may begin: <COMMITMENT_DURATION>
- External publication: <yes/no — link if yes>
EOF
```

**Step 7 — PAUSE the session.**

The pane that pre-registered does NOT proceed to Phase 4 immediately. The session is paused until `<COMMITMENT_DURATION>` is reached.

The operator can resume via `MO-resume.md` when investigation conditions are met (data is collected / sources are available / time has passed).

---

**Anti-patterns:**

- ✗ Pre-register and then immediately begin investigation — defeats the temporal separation
- ✗ Pre-register but allow falsifier edits during Phase 4 — defeats the anti-bias protocol
- ✗ Add post-hoc hypotheses without `origin:post-hoc` flag — silent rationalization
- ✗ Skip the hash + commit — no verifiable pre-registration record
- ✗ Pre-register a falsifier you suspect won't fire (planned-confirmation bias) — Phase 7 should catch but it's hard

**Phase 7 audit responsibilities for pre-registered sessions:**

- Compare current `H-*.falsifier` to pre-registered version
- Compare current `H-*.expected_evidence` to pre-registered version
- Identify any H with `origin:post-hoc` and weight accordingly
- File audit-finding for any modification to pre-registered fields

**Ship-or-Surface SLA:** within 15 min of Phase 3 exit, pre-registration complete + committed + published (if T4+).

---

## When to use this MO

This MO is HIGH-VALUE for:

- T4+ adversarial contexts (legal, regulatory, scientific publication)
- Long-running living-review sessions (per EXTENDED-OPERATING-MODES.md)
- Sessions where the answer is politically charged
- Sessions where the operator has known conflicts of interest

LOW-VALUE for:

- T1-T2 internal exploratory sessions (overhead exceeds benefit)
- Incident-investigation mode (compressed; no time for pre-registration)
- Methodology drift checks (the methodology is already published)

In doubt, lean toward pre-registering for T3+. The cost is low; the benefit (defensibility) compounds.
