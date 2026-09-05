# MO-evidence-verify.md — Independent Verification of an Evidence Bead

**Phase:** 4 (post-EV-filing) or 7 (audit)
**Operators activated:** ⌂ Materialize (re-verify), ✂ Exclusion-Test (re-verify)
**Parameters:** `<PANE_N>`, `<EV_ID>` (the EV to verify), `<SESSION_ID>`

---

Per CONFIDENCE-SCORING.md, an `EV-*.verified=true` requires *independent* re-checking — a different pane than the one that filed the EV navigates to the source and confirms the verbatim excerpt.

This MO is the verification step. It's typically run during Phase 4 round-end or Phase 7 audit.

---

**Step 1 — Read the EV bead.**

```bash
ev_ref="<EV_ID>"
ev_id="$(br list --all --json | jq -r --arg ref "$ev_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
[ -n "$ev_id" ] || { echo "No bead found for public ref: $ev_ref" >&2; exit 1; }
br show "$ev_id" --json
```

Note: `source:`, `excerpts:`, `imported_by:`. You must NOT be the same pane as `imported_by` (or this is self-verification, not independent).

**Step 2 — Verify pane independence.**

If you are pane `<PANE_N>` and `imported_by:<PANE_N>` matches, decline this dispatch and tell the operator. Verification by the same pane that filed is anti-Brenner — it's confirmation, not verification.

**Step 3 — Navigate to the source.**

For each source type:

- **File path with line range:** `sed -n '<line_start>,<line_end>p' <file_path>`
- **URL:** `WebFetch` if available, OR ask operator to surface manually
- **DOI:** look up via DOI resolver
- **Code commit:** `git show <sha>:<file>`
- **Prior session (cass):** navigate to the cass-indexed file directly

**Step 4 — Compare to verbatim excerpts.**

For each excerpt in the EV bead:

- Does the verbatim quote appear at the cited location?
- Is the quote exact (modulo whitespace)?
- Is the surrounding context consistent with the EV's `relevance:` claim?

**Step 5 — Decide verification verdict.**

| Verdict | When |
|---------|------|
| `verified:true` | All excerpts confirmed verbatim at cited locations; relevance claim is supportable |
| `verified:false` (still) | Excerpts cannot be confirmed (source unavailable, location wrong, quote drifted) |
| `verified:false`, file as discrepancy | Excerpts confirmed but `relevance:` claim is misinterpretation |

**Step 6 — Update the EV bead.**

```bash
br update "$ev_id" --description="$(br show "$ev_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' | sed 's/^verified: false$/verified: true/')

verification_notes: <one paragraph>
verified_by: <PANE_N>
verified_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

(Adapt heredoc to your shell.)

**Step 7 — Append to evidence/verification_log.md.**

```bash
cat >> evidence/verification_log.md <<EOF

| <TIMESTAMP_UTC> | <EV_ID> | <PANE_N> | <verified | discrepancy | unavailable> | <one-line note> |
EOF
```

**Step 8 — If discrepancy, file an audit-finding.**

```bash
af_ref="AF-NNN"  # public ref; replace NNN before running
af_id="$(br create "$af_ref: Evidence-verification discrepancy on $ev_ref" \
  --type=task --labels=audit-finding --priority=1 \
  --slug="$af_ref" --external-ref="$af_ref" --silent \
  --description="$(cat <<EOF
severity: high
target_artifact: $ev_ref
recommendation: Re-investigate the cited source. If quote drift, file fresh EV with corrected excerpt. If interpretation drift, sharpen relevance claim.
by_pane: <PANE_N>
prompt_used: MO-evidence-verify
session: <SESSION_ID>

## Detail
<what was claimed vs what was found>
EOF
)")"
printf 'Created %s as br id %s\n' "$af_ref" "$af_id"
```

**Step 9 — Post to per-H thread.**

```
Subject: [<SESSION_ID>-EV-VERIFY] Verification of <EV_ID>: <verified | discrepancy | unavailable>

Verifier pane: <PANE_N>
Source: <where checked>
Verdict: <one sentence>
EOF (if updated): yes
Audit finding filed (if discrepancy): AF-NNN
```

---

**Anti-patterns:**

- ✗ Self-verification (same pane as `imported_by:`). Defeats the whole point.
- ✗ Verify by re-running the same search — must navigate to the actual cited location.
- ✗ Mark verified:true without actually navigating to the source. Audit will catch (Phase 7 cross-checks verification_log.md against the EV beads).
- ✗ Skip filing audit-finding when discrepancy found. Verification ≠ overlooking.
- ✗ Verify only the supports: EVs and skip the refutes:. Verification applies equally.

**Ship-or-Surface SLA:** within 15 min per EV. If source is genuinely unavailable, mark `verified:false` with reason and continue.
