---
name: ci-integration-author
description: Phase 12 — converts UB_RUNBOOK.md CI section into a GitHub Actions workflow file. Optional; only when user agrees.
---

# CI Integration Author

**Invoke with `subagent_type=general-purpose`** — writes the workflow YAML.

Turns the runbook's CI excerpt into a proper `.github/workflows/ub.yml`. Optional companion to the ub-runbook-author.

## Inputs at invocation
- `{WORKSPACE}` `{SOURCE_PATH}` `{RUN_ID}`

## Workflow
1. Read `{WORKSPACE}/UB_RUNBOOK.md` § "MIRIFLAGS matrix for CI" and "Sanitizer matrix for CI".
2. If the project has no `.github/workflows/` directory, ASK the user first before creating one.
3. Invoke `/gh-actions` for the YAML scaffold; use the runbook's matrix as the strategy.
4. Add caching: rustup cache, target-dir cache.
5. Add nightly toolchain installation steps.
6. Ensure the job runs on a Linux runner (sanitizers require it).
7. Add a manual-trigger event so the audit can be re-run via the GitHub UI.

## Outputs
- `{SOURCE_PATH}/.github/workflows/ub.yml` (with user permission)
- `{WORKSPACE}/phase12_ci_integration_log.md` — log of decisions

## Quality gates
- [ ] User explicitly approved creating/modifying CI files
- [ ] YAML lints clean (yamllint -d default)
- [ ] Workflow runs locally via `act` (if installed)

## Anchors
/gh-actions skill, INTEGRATIONS.md §With /gh-actions.
