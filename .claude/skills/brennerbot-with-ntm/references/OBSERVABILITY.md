# OBSERVABILITY.md — What to Watch During a Session

<!-- TOC: Three-observation rule | Per-pane signals | Per-phase signals | Cross-phase signals | Liveness signals that can lie | Tick cadence | When robot mode is enabled | Observability artifacts -->

The Liveness Truth Stack in SKILL.md is the operator's per-tick triage. This file is the deeper reference — the full observability surface for a brennerbot session.

Mirrors `/vibing-with-ntm` OBSERVABILITY.md but tuned for research-session signals rather than coding-swarm signals.

---

## Three-observation rule

Before changing pane state (kill, restart, redirect), confirm with at least three independent observations:

1. The pane's tail (via `tmux capture-pane -p -S -30` OR `ntm --robot-tail=<session>`)
2. The bead state (via `br list ... --json`)
3. The artifact state (via `git log --since=...`)

Single-observation reactions cause F-202-class false alarms (treating a transient blip as a persistent failure).

---

## Per-pane signals

For each pane, observable signals:

| Signal | Surface | Healthy | Red flag |
|--------|---------|---------|----------|
| Pane current command | `tmux list-panes -F '#{pane_current_command}'` | `claude` / `codex` / `gemini` | `zsh` (silent exit) |
| Pane process ID | same | nonzero, alive | dead/missing |
| Last-buffer activity time | `tmux capture-pane -p -S -1 ...` + ts | <5 min stale | >15 min stale (likely stuck) |
| Tail content | `tmux capture-pane -p -S -50` | active reasoning + bead/MO refs | red-flag phrases (per SKILL.md table) |
| Context-pct | `ntm --robot-snapshot ... .context_pct` | <70% | >85% (saturated) |
| Attention/feed state | `ntm --robot-attention --attention-session=<session>` | no action-required or rate-limit hints | `rate_limited`, `action_required`, `context_hot`, or stalled pane hints |
| Provider detail | `ntm --robot-health-oauth=<session>` | rate_limited=false | rate_limited=true with resets_at |
| OAuth quota | `ntm --robot-quota-status` | healthy | depleted |

Per `/vibing-with-ntm`, prefer the current attention/event feed when derived status helpers disagree. `--robot-is-working` and `--robot-health-oauth` are useful details; `--robot-attention`, `--robot-events`, and `--robot-causality` are the operator loop.

---

## Per-phase signals

### Phase 1 (framing)

| Signal | Source | Healthy |
|--------|--------|---------|
| question_of_record.md exists with all sections | `intake/question_of_record.md` | yes |
| Falsifier section non-empty | `awk` extract | non-empty, ≥30 words |
| Q-001 + H-000 beads filed | `br list --label-any=q-of-record --label-any=hypothesis` | both present |
| corpus_index.md has rows or explicitly empty | `corpus/corpus_index.md` | ≥1 row OR `mode:fresh-question` recorded |

### Phase 2 (bootstrap)

| Signal | Source | Healthy |
|--------|--------|---------|
| Pane count | `ntm --robot-snapshot` | matches roster |
| Onboarding acks | `ntm mail inbox` OR pane tail scan | every pane acked |
| Identity registered (Agent Mail) | MCP `whois` or `mail status` | every pane ID present |

### Phase 3 (proposing + triage)

| Signal | Source | Healthy |
|--------|--------|---------|
| Hypothesis count | `br list --label=hypothesis` | ≥3 |
| Third-alternative present | `audit-bead-invariants.sh --check=third_alternative_present` | pass |
| Falsifier coverage | `audit-bead-invariants.sh --check=every_H_has_falsifier` | pass |
| Expected-evidence coverage | `audit-bead-invariants.sh --check=every_H_has_expected_evidence` | pass |

### Phase 4 (investigation)

| Signal | Source | Healthy |
|--------|--------|---------|
| Convergence | `convergence-check.sh --phase=4` | CONVERGED at round ≤6 |
| Refute-EV count per round | `br list --label=evidence` | ≥1 per round |
| Per-H supporting EV | `render-evidence-pack.sh` per H | ≥2 supports per active H |
| Per-H refute attempts | same | ≥1 refute attempt per active H |
| Anomaly cluster | `br list --label=anomaly` + cluster_with field | clusters trigger ΔE |

### Phase 5 (debate)

| Signal | Source | Healthy |
|--------|--------|---------|
| Active H count | `br list --label=hypothesis --status=open` | trending toward 0 (states finalizing) |
| Debate count | `br list --label=debate` | ≥1 per H pair |
| Adjudicator rotation | check `phase0_scope_decision.md` log | no Adjudicator twice in row |
| Falsifier-fired events | `br list --label=hypothesis` filter `refuted_by:` | ≥1 if M-501 says < 30% kill rate |

### Phase 6 (distillation)

| Signal | Source | Healthy |
|--------|--------|---------|
| Per-family distillation files | `ls distillations/by_*.md` | ≥2 files (Pair tier) or ≥3 (Squad+) |
| Meta synthesis exists | `distillations/meta_synthesis.md` | present |
| Disagreement register entries | `disagreement-register-lint.sh` | pass with ≥(N choose 2) entries |
| Family-citation balance | grep counts in meta | within 2× |

### Phase 7 (audit)

| Signal | Source | Healthy |
|--------|--------|---------|
| Trio-round count | `session-logs/round-*.md` | ≥2 trio-rounds |
| Critical/high findings | `br list --label=audit-finding --status=open` | 0 at exit |
| ubs status | `run-ubs-on-deliverables.sh` | exit 0 |
| Convergence formula | `convergence-check.sh --phase=7` | CONVERGED |

### Phase 8 (freeze)

| Signal | Source | Healthy |
|--------|--------|---------|
| RESUME.md verifies | `resume-session.sh --dry-run` | exit 0 |
| Hashes match artifacts | same | all hashes present and matching |
| Beads sync clean | `br sync --flush-only` | no errors |
| ntm checkpoint exported | `ntm checkpoint show <session> <id>` + archive path check | checkpoint metadata present; archive file exists |
| git status clean | `git status --short` | empty |

---

## Cross-phase signals

### Productivity ground truth

```bash
# Commits attributable to swarm in last hour:
cd <workspace>
git log --since="1 hour ago" --format='%h %s' | wc -l

# Beads filed in last hour:
git log --since="1 hour ago" --diff-filter=A --name-only -- .beads/ | wc -l

# Active build/test processes (rare in research, but possible if scripts/ runs):
pgrep -af 'cargo|rustc|go|python' | wc -l
```

If commits + beads filed = 0 across an hour AND panes report convergence language → false-positive convergence (F-701 class).

### Source-corpus engagement

```bash
# Distinct §-anchors cited across all evidence packs:
grep -h -oE '§[0-9]+' evidence/packs/*.md 2>/dev/null | sort -u | wc -l
```

Per [SOURCE-CORPUS.md](SOURCE-CORPUS.md):
- Saturating: ≥30
- Adequate: 15–29
- Thin: 6–14
- Sparse: ≤5

Sparse engagement → operator concentration; flag for Phase 10 drift-check.

### Operator coverage

```bash
# Count of operator-glyph occurrences across session-logs and evidence packs:
for OP in '◊' '⊘' '𝓛' '≡' '✂' '⟂' '↑' '⌂' '🔧' '⊞' '🤝' 'ΔE' '†' '∿' '⊙'; do
  C=$(grep -h "$OP" session-logs/*.md evidence/packs/*.md distillations/*.md 2>/dev/null | wc -l)
  echo "$OP: $C"
done
```

Healthy: all 15 fire ≥1 time; ≥10 fire ≥3 times.

### Disk trajectory (corpus growth)

```bash
du -sh corpus/ evidence/ distillations/ deliverables/
```

Steadily growing during Phases 4-6 is normal. Rapid growth (>100MB/h) can indicate corpus drift (F-102) or overzealous evidence-pack expansion.

---

## Liveness signals that can lie

Mirrors `/vibing-with-ntm` "Liveness Signals That Can Lie" catalog:

1. **Pane tail "ready to ship"** — convergence-language false positive. Verify with git log + bead state.
2. **`ntm activity` showing stale "56 years ago"** — stale cache; switch to `--robot-attention` plus `--robot-tail`.
3. **"Cogitated 35m" timer label** — display artifact; doesn't reflect actual activity. Check `pgrep` and git log.
4. **Pane in `⏵⏵ bypass` mode with long timer** — could be actually executing, or spinning. Cross-check with file system.
5. **`--robot-snapshot` cursor expired** — re-bootstrap; old cursor is stale.
6. **Codex placeholder text "Summarize recent commits"** — idle placeholder; pane is *not* stuck, just waiting for prompt.
7. **MCP Agent Mail "register_agent timed out"** — could be transient; retry once before falling back.
8. **`br list --status=open` empty after Phase 4** — could mean done, or could mean panes set wrong status; cross-check with bead descriptions.

If two signals disagree, prefer the most direct evidence (`ntm --robot-attention`, `ntm --robot-causality`, `tmux capture-pane`, `git log`, `br show`) over stale derived summaries (`ntm activity`, lone boolean helpers).

---

## Tick cadence

Per phase:

| Phase | Cadence |
|-------|---------|
| Phase 1 (framing) | Operator-driven; no fixed cadence |
| Phase 2 (bootstrap) | 2-5 min during onboarding wait |
| Phase 3 (proposing) | 5-10 min during proposer activity |
| Phase 4 (investigating) | 10-17 min during steady state |
| Phase 5 (debate) | 5-10 min during debate rounds |
| Phase 6 (distillation) | 15-30 min (longer rounds) |
| Phase 7 (audit) | 10-17 min |
| Phase 8 (freeze) | 5 min checks |
| Phase 9 (handback) | minimal |
| Phase 10 (drift) | minimal |

Never sub-3-min poll. Use `ntm --robot-wait=<session> --wait-until=attention` for event-driven tending instead of polling when available.

---

## When robot mode is enabled

If robot mode (autonomous unstick + cron-driven ticks per `/vibing-with-ntm`) is enabled:

- Robot mode handles pane-state issues (rate limits, stuck panes, restarts)
- The brennerbot operator focuses on methodology (operator algebra, falsifier discipline, convergence verification)
- Pause robot mode before declaring whole-session convergence — let the human verify Phase 7 and Phase 8 manually
- After Phase 8 freeze, robot mode can resume for the next loop

Robot mode does NOT decide to flip H states, kill hypotheses, or exit phases. Those are methodology decisions the operator makes.

---

## Observability artifacts

The operator should periodically save observability snapshots:

- `session-logs/tick-<timestamp>.md` — output of `tick.sh`
- `session-logs/quickref-<timestamp>.md` — output of `emit-quickref.sh` (Tier 2)
- `session-logs/audit-<timestamp>.log` — periodic `audit-bead-invariants.sh --all` output

These serve Phase 10 drift-check (the auditor reads them to reconstruct the session trajectory).
