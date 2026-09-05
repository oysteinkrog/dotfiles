# Critique (C-*) Template

Use when filing a `critique` bead during Phase 4 (Devil's-Advocate role) or Phase 7 (audit).

```bash
c_ref="C-NNN"  # public ref; replace NNN before running
priority="2"  # critical=0, serious/high=1, moderate=2, minor=3
c_id="$(br create "$c_ref: <one-line critique>" \
  --type=task --labels=critique --priority="$priority" \
  --slug="$c_ref" --external-ref="$c_ref" --silent \
  --description="$(cat <<'EOF'
target: H-NNN | T-NNN | A-NNN | framing | methodology
attack: <one-paragraph attack on the target>
severity: minor | moderate | serious | critical
evidence_to_confirm: <what observation would, if found, confirm the attack>
session: <SESSION_ID>
by: <PANE_N> (Devil's-Advocate | Auditor | red-team)
attack_class: <see below>

## Detail
<longer explanation: where the target is weak, what's the failure mode>

## Anchors
- §<N> in source S-NNN: <verbatim quote that motivates the attack>
- Cross-domain analog: <if importing pattern from another field>

## Recommended remediation (if accepted)
<what would the target do to address this critique>

## Status
active | addressed | dismissed | accepted

(Started as 'active'; updated as the target's owner responds.)
EOF
)")"
printf 'Created %s as br id %s\n' "$c_ref" "$c_id"
```

## Severity rubric

- **critical** — falsifier-firing evidence found; the target is dead per † Theory-Kill
- **serious** — major weakness; target may need substantial revision
- **moderate** — meaningful weakness; target needs caveat or refinement
- **minor** — small issue; target stands but should note

## attack_class

For Devil's-Advocate critiques (Phase 4):
- `falsifier-firing` — directly fires the target's falsifier
- `evidence-misread` — claims a cited EV is misinterpreted
- `assumption-violation` — load-bearing assumption fails
- `scale-mismatch` — claim doesn't survive ⊞ Scale-Check
- `confirmation-bias` — target only cites supporting EVs

For audit critiques (Phase 7):
- `methodology-violation` — operator algebra or invariant violated
- `convergence-false-positive` — apparent convergence is rhetoric
- `triangulation-failure` — single-family bias

For red-team critiques (T4+):
- `novel-attack` — attack class not previously enumerated
- `coordinate-inversion` — apply 𝓛 to flip the framing
- `time-shift` — claim won't survive future conditions

## Lifecycle

```
filed (status: active)
   ↓
target owner responds (in same RS-...-H-NNN thread):
   ↓
   accept → status: accepted, target updated
   reject → status: dismissed (with reason)
   address → status: addressed (with response)
```

## Phase 7 audit responsibility

Audit checks:
- Every critical critique has been addressed or accepted
- Every accepted critique resulted in actual target update (not just "noted")
- No critique has been silently dismissed

## When to file

- Phase 4: every Devil's-Advocate round should produce ≥1 critique per active H
- Phase 5: champions and adjudicator may file critiques as part of debate
- Phase 7: auditor critiques are usually filed as audit-finding instead, but high-severity audit critiques may use this format
