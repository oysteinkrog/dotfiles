# NTM-PIPELINES.md — Pipeline Definitions for the Canonical Roster

## Table of Contents

- Schema overview
- Variant pipelines
- Pipeline invocation
- Pipeline state files
- When NOT to use pipelines
- Pipeline template authoring rules

NTM pipelines (`.ntm/pipelines/*.yaml`) orchestrate Phase 2 (registration/onboarding) through Phase 8 (freeze) after the operator has created the tmux roster with `ntm spawn`. Phases 1, 9, and 10 remain operator-driven because they depend on user framing, final handback judgment, and methodology drift review.

This file documents the pipeline schema we use, the canonical 5-role pipeline, and variants for Pair / Swarm / Resume / no-mail tiers.

The drop-in pipeline YAMLs live at `assets/ntm-pipelines/*.yaml`. The files with `schema_version: "2.0"` and `steps:` are runnable pipeline inputs; the phase-outline YAMLs that use `phases:` are specs for operator-driven modes, not `ntm pipeline run` inputs.

Current `/dp/ntm` is the native runner for these files, not an approximation layer. The May 2026 pipeline Phase-B push closed the old gap where BrennerBot YAML could parse but not execute. Supported runtime primitives now include `command:`, `template:`, `template_params:` / `params:`, `args:`, `after:` (alias for `depends_on:` accepting string or list), `foreach:` and `foreach_pane:` with iteration sources (`items` / `beads` / `pairs` / `debates` / `models`), `filter:`, `pane_assignment_strategy:`, `loop.until:`, `loop.body:`, nested branch/parallel/foreach bodies, `parallel: true`, `on_failure:` shorthands (`retry:N` and structured `{pane, template}`), output variables and parsers, command stdin/stdout streaming/truncation, duration-form `timeout: 300s`, and Agent Mail pipeline steps (`mail_send`, `file_reservation_paths`, `mail_inbox_check`, `file_reservation_release`). See the `/ntm` skill's pipeline reference for the canonical field catalog.

**Execution status by step kind:** executable pipeline assets should pass `ntm pipeline run <file> --session <session> --dry-run` after that session exists, and then run for real. Current NTM command-step `args:` are exported as environment variables; BrennerBot command steps therefore inline required CLI flags directly in `command:`. If a current binary reports a schema error or `phase_b_not_implemented`, you are on an old NTM build; upgrade/build the live `/dp/ntm` checkout or switch to manual dispatch only for that run. Do not keep telling operators that `command`, `template`, `foreach`, or `branch` are dry-run-only.

The proof surface in NTM includes a mocked BrennerBot incident E2E fixture (`e2e/pipeline/testdata/brennerbot-incident.yaml`) that runs command steps, foreach fan-out, template dispatch, phase flags, and `INCIDENT-VERDICT.md` production against in-memory panes.

---

## Schema overview

```yaml
schema_version: "2.0"
name: brennerbot-squad
description: 5-role canonical brennerbot research session
inputs:
  - workspace_path        # absolute path to <workspace>
  - session_id            # RS-<YYYYMMDD>-<slug>
  - question_of_record_path
  - mode                  # one of OPERATING-MODES.md modes
  - model_mix             # e.g. cc:3,cod:1,gmi:1

steps:
  - id: register_mail
    command: ./scripts/register-mail-identities.sh --project-key=${workspace_path} --session=${session_id}
    on_failure: fallback_to_ntm_inbox

  - id: dispatch_onboarding
    after: register_mail
    foreach_pane:
      template: assets/marching-orders/MO-02-onboarding.md
      params:
        WORKSPACE_PATH: ${workspace_path}
        QUESTION_OF_RECORD_PATH: ${question_of_record_path}
        SESSION_ID: ${session_id}
        ROLE: ${pane.role}
        MODEL: ${pane.model}
        PRODUCTIVE_IGNORANCE: ${pane.productive_ignorance}
    parallel: true
    on_failure: continue

  - id: wait_for_acks
    after: dispatch_onboarding
    command: ./scripts/wait-for-onboard-acks.sh --session=${session_id}
    timeout: 300s

  - id: phase_3_propose
    after: wait_for_acks
    foreach_pane:
      filter: role==proposer
      template: assets/marching-orders/MO-03a-propose.md
    parallel: true
    on_failure: retry:1

  - id: phase_3_triage
    after: phase_3_propose
    pane: 1   # designated triage pane
    template: assets/marching-orders/MO-03b-triage.md

  - id: phase_3_third_alternative_check
    after: phase_3_triage
    command: ./scripts/audit-bead-invariants.sh --check=third_alternative_present --workspace=${workspace_path}
    on_failure:
      pane: 1
      template: assets/marching-orders/MO-03c-third-alternative.md

  - id: phase_4_loop
    after: phase_3_third_alternative_check
    loop:
      max_iterations: 6
      until: ./scripts/convergence-check.sh --phase=4 --workspace=${workspace_path}
      body:
        - id: phase_4_investigate
          foreach:
            beads: >-
              $(br list --label=hypothesis --status=open --json | jq -r '.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*active([[:space:]]|$)")) | (.external_ref // "") as $external_ref | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref | if $external_ref != "" then $external_ref elif $title_ref != "" then $title_ref else .id end')
            template: assets/marching-orders/MO-04a-investigate.md
            pane_assignment_strategy: round_robin_by_domain
          parallel: true
        - id: phase_4_devils_advocate
          foreach:
            beads: >-
              $(br list --label=hypothesis --status=open --json | jq -r '[.issues[]? | select(((.description // "") | test("(^|\\n)state:[[:space:]]*active([[:space:]]|$)")) and (((.description // "") | contains("confidence: high")) or ((.description // "") | contains("confidence: medium"))))][:2][] | (.external_ref // "") as $external_ref | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref | if $external_ref != "" then $external_ref elif $title_ref != "" then $title_ref else .id end')
            template: assets/marching-orders/MO-04b-devils-advocate.md
            pane_assignment_strategy: by_model_family_difference
          parallel: true

  - id: phase_5_debate_pairs
    after: phase_4_loop
    # Not bare foreach.pairs: each row carries both champion panes, so the
    # helper files the DEBATE bead and dispatches MO-05a to both champions.
    command: ./scripts/run-phase5-debate-loop.sh --workspace=${workspace_path} --session=${session_id} --round=1

  - id: phase_5_rounds_gate
    after: phase_5_debate_pairs
    command: |
      test -f ${workspace_path}/.brenner_workspace/phase_5_debate_rounds_complete.flag || {
        echo "Phase 5 Round 1 was dispatched and debate-pairs.pairs is frozen. Run ./scripts/run-phase5-debate-loop.sh --workspace=${workspace_path} --session=${session_id} --round=2, then --round=3 when ready; round 3 marks .brenner_workspace/phase_5_debate_rounds_complete.flag before adjudication."
        exit 1
      }

  - id: phase_5_adjudicate
    after: phase_5_rounds_gate
    foreach:
      # Reuse the pair rows so rotate_adjudicator can see champion_a/champion_b.
      pairs: $(cat "${workspace_path}/.brenner_workspace/debate-pairs.resolved.pairs" 2>/dev/null || true)
      template: assets/marching-orders/MO-05b-adjudicate.md
      pane_assignment_strategy: rotate_adjudicator   # never same pane two debates in a row
      params:
        DEBATE_ID: ${item.debate_id}
    parallel: true

  - id: phase_6_distill
    after: phase_5_adjudicate
    foreach:
      models: ${distinct_model_families}
      template: assets/marching-orders/MO-06a-distill.md
    parallel: true

  - id: phase_6_meta_synthesize
    after: phase_6_distill
    pane: ${meta_synthesizer_pane}   # different family from dominant
    template: assets/marching-orders/MO-06b-meta-synthesize.md
    on_failure: retry_with_explicit_disagreement_directive:1

  - id: phase_6_disagreement_lint
    after: phase_6_meta_synthesize
    command: ./scripts/disagreement-register-lint.sh --workspace=${workspace_path}
    on_failure:
      pane: ${meta_synthesizer_pane}
      template: assets/marching-orders/MO-06b-meta-synthesize.md
      reason: "disagreement register insufficient"

  - id: phase_7_audit_loop
    after: phase_6_disagreement_lint
    loop:
      max_iterations: 4
      until: ./scripts/convergence-check.sh --phase=7 --workspace=${workspace_path}
      body:
        - id: phase_7_trio
          foreach_pane:
            template: assets/marching-orders/MO-07a-fresh-eyes.md
          parallel: true

  - id: phase_7_ubs
    after: phase_7_audit_loop
    command: ./scripts/run-ubs-on-deliverables.sh --workspace=${workspace_path}
    on_failure: abort

  - id: phase_8_freeze
    after: phase_7_ubs
    pane: 0   # operator
    template: assets/marching-orders/MO-08-freeze.md

outputs:
  - workspace: ${workspace_path}
  - resume_md: ${workspace_path}/deliverables/RESUME.md
  - phase_8_complete_flag: ${workspace_path}/.brenner_workspace/phase_8_complete.flag
```

`MO-08-freeze.md` owns the actual `ntm checkpoint save/export` commands because
the operator must review `RESUME.md` fields before finalizing the freeze.

---

## Variant pipelines

### `brennerbot-pair.yaml`

2 panes, cc + cod. Skip `phase_4_devils_advocate` (one pane wears both Investigator and Advocate hats via mode-flip). Phase 5 debates are between cc and cod. Phase 6 has only 2 distillations + 1 meta.

### `brennerbot-swarm.yaml`

8–12 panes. Domain-assigned investigators. Multi-pane Phase 7 audit (≥3 panes). Phase 6 meta-synthesizer is a distinct pane from any per-family synthesizer.

### `brennerbot-resume.yaml`

Pre-condition: `RESUME.md` parses cleanly. Skips Phase 1, 2 spawn (uses `ntm checkpoint restore` instead). Re-attaches Agent Mail threads via `register_agent` per pane. Re-enters at the phase indicated by `RESUME.md § next_loop_recommendation.phase`.

### `brennerbot-squad-no-mail.yaml`

Same as `brennerbot-squad.yaml` but with `register_mail` step replaced by `register_assignees.sh` (sets `assignee` on each H- bead per pane). Coordination falls back to ntm-inbox per `AGENT-MAIL-FALLBACKS.md`.

### `brennerbot-incident.yaml`

Compressed phases for incident-investigation mode. 2 panes; runs Phase 1 + Phase 3 + Phase 5 with inline investigation + Phase 7. Hard timeout 60 min.

---

## Pipeline invocation

Use the same live NTM session name for `--session` and `--var session_id=...`; helper scripts such as `register-mail-identities.sh` and `wait-for-onboard-acks.sh` read that variable as the tmux session to inspect.

```bash
ntm spawn RS-20260516-event-log --cc=3 --cod=1 --gmi=1
ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml \
  --session RS-20260516-event-log \
  --var workspace_path=$HOME/brennerbot_sessions/event-log \
  --var session_id=RS-20260516-event-log \
  --var question_of_record_path=intake/question_of_record.md \
  --var mode=corpus-distillation \
  --var model_mix=cc:3,cod:1,gmi:1
```

Robot-mode invocation, useful for orchestrator agents that need machine-readable envelopes:

```bash
ntm --robot-pipeline-run=.ntm/pipelines/brennerbot-squad.yaml \
  --session=RS-20260516-event-log \
  --vars="{\"workspace_path\":\"$HOME/brennerbot_sessions/event-log\",\"session_id\":\"RS-20260516-event-log\",\"mode\":\"corpus-distillation\"}" \
  --dry-run
```

`bootstrap-session.sh` seeds runnable copies into `<workspace>/.ntm/pipelines/` and rewrites script/template paths in those copies to the installed `brennerbot-with-ntm` skill directory. The source YAMLs under `assets/ntm-pipelines/` remain skill-relative for local editing and validation.

The pipeline runs unattended unless an `on_failure: abort` step fires. Operator can attach to the session at any time via `ntm attach RS-20260516-event-log`.

During a real run, monitor with:

```bash
ntm pipeline status <run-id> --json
ntm --robot-attention --attention-session=RS-20260516-event-log --attention-cursor=<cursor>
ntm --robot-causality=RS-20260516-event-log --causality-project=<workspace>
```

---

## Pipeline state files

`.ntm/pipelines/<run-id>.json` records every step's status, output, timing, and persisted outputs used by resume. Resume preserves completed step outputs by default and starts from the first incomplete step/iteration; use `ntm pipeline resume <run-id> --mode=continue` for normal recovery, or the explicit force/start-from modes only when the operator wants to deliberately re-run work. Run `ntm pipeline cleanup --older=7d` periodically after exporting reproducibility bundles.

---

## When NOT to use pipelines

Pipelines are now good for the canonical phase sequence and compressed incident loops. They are *not* the right surface for:

- Phase 1 framing (operator + user judgment-heavy)
- Phase 9 handback (single operator-driven step)
- Phase 10 drift-check (fresh agent, not a swarm pane)
- Mid-session re-rostering (operator decides)
- Anomaly cluster checks (operator inspects manually)

For these, the operator dispatches `MO-*.md` templates directly via `ntm --robot-send` or `dispatch-marching-order.sh`, then records the intervention in the session log.

---

## Pipeline template authoring rules

When extending the pipeline library:

1. Every step must have `id`, `command` or `template`, `after` (or `parallel`).
2. Every step must declare `on_failure` (one of: `abort`, `continue`, `retry:N`, `fallback_to_<x>`).
3. Loops must have `max_iterations` AND `until` condition (no infinite loops).
4. Pane-targeting must use `pane: <id>`, `foreach_pane:`, or `pane_assignment_strategy:` — never hardcoded pane indices outside id 0 (operator pane).
5. Cross-pane parallelism must be `parallel: true`; sequential is the default.
6. Output files must be declared in `outputs:` so `resume-session.sh` can find them.
7. Reuse marching-order templates — don't inline prompts in the pipeline YAML.
8. Agent Mail steps must be explicit pipeline steps when they are part of the method; do not hide registration/reservation side effects inside opaque shell snippets unless the NTM runtime lacks the needed primitive.
9. For foreach sources that come from dynamic commands, keep the item set stable across resume or expect NTM to fail fast on item-fingerprint drift.
