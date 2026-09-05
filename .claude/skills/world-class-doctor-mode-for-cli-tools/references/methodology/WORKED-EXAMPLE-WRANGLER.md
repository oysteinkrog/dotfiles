# Worked Example — Applying the Skill to `wrangler` (distributed-CLI)

A second worked example. While [WORKED-EXAMPLE.md](WORKED-EXAMPLE.md) covers `br` (Pattern 2 multi-binary, state-owning), this one covers a **distributed CLI** (Pattern 9): a tool that's a thin client over a remote vendor service. `wrangler` is the example, but the same shape applies to `vercel`, `gh`, `gcloud`, `aws`, `stripe-cli`, `supabase` CLI.

This is illustrative — wrangler doesn't currently have a doctor. The numbers are realistic for what such a doctor would look like.

---

## Intake

```
Target: /home/user/projects/my-worker (a wrangler project)
Project URL: <none — this is a Cloudflare Worker app>
Binaries: wrangler (single binary; the Cloudflare CLI)
Mode: add (no existing wrangler doctor)
Operating location: in-place (the wrangler binary is system-installed; we're
  adding a wrapper script `<my-tool>-doctor` that probes wrangler's state)
Patterns: 9 (distributed-CLI), 4 (sometimes; wrangler dev runs a daemon)
Triangulation: peer-claude
CASS: deep
Online: online-allowed (this is a vendor-API client; --online is the point)
Must-not-touch: wrangler.toml in the user's project (read-only)
```

**Special note:** since wrangler is third-party, we can't modify its source. We're building a sibling tool `<my-tool>-doctor` that wraps wrangler invocations. This is **Cookbook Pattern 8** combined with Pattern 9.

---

## Phase 0 — Bootstrap

`scripts/discover-cli.sh /home/user/projects/my-worker --probe-doctor`:

```jsonc
{
  "target": "/home/user/projects/my-worker",
  "default_branch": "main",
  "language": "typescript",
  "build_system": "npm",
  "binaries": ["wrangler"],
  "existing_doctor_subcommand": "",
  "probe_doctor": 1
}
```

CASS mining for "wrangler" yields ~120 quotes:

- 28 SYMPTOM (incl. "EADDRINUSE", "auth invalid", "deploy went to wrong env")
- 18 ROOT_CAUSE
- 22 MANUAL_FIX (gold)
- 12 INCIDENT
- 40 WISH_THIS_EXISTED ("wrangler should warn me before deploying production from a feature branch")

The MANUAL_FIX set surfaces strong candidates for absorption into the wrapper doctor.

---

## Phase 1 — Failure-Mode Inventory (parallel by subsystem)

Subsystems mapped:

- `auth_state` — `wrangler auth login` token, account ID, scope.
- `wrangler_toml` — the project's wrangler.toml: env definitions, route binding, KV namespace IDs, Durable Object bindings.
- `vendor_drift` — local cached account info vs. live vendor state.
- `daemon_state` — `wrangler dev`'s local server (port, watcher, listener).
- `branch_env_safety` — the deploy-from-non-main-to-production class.
- `rate_limits` — vendor budget.

Sample FMs:

```markdown
# FM-fm-auth-state-token-expired
severity: P0
symptoms:
  - `wrangler whoami` returns invalid
  - All deploy attempts fail with 401
root_cause: |
  Wrangler's OAuth token expired. The local `~/.config/wrangler/...` still has the
  old token; user assumes everything is fine because previous commands worked.
observable_signals:
  - file:line — `~/.config/.wrangler/config/default.toml::api_token` (presence vs validity)
  - online: GET https://api.cloudflare.com/client/v4/user → 401
prior_incidents: 14 cass quotes
currently_auto_detected: no
currently_auto_fixed: no (auth login is user action)

# FM-fm-vendor-drift-resource-deleted-remotely
severity: P1
symptoms:
  - wrangler.toml references a KV namespace ID that doesn't exist remotely
  - Deploy succeeds but at runtime, KV ops return 404
root_cause: |
  The KV namespace was deleted via the dashboard or another wrangler invocation;
  local wrangler.toml is stale.
observable_signals:
  - online: GET /accounts/<id>/storage/kv/namespaces vs. wrangler.toml
currently_auto_detected: no
currently_auto_fixed: no (re-creating is user intent)

# FM-fm-branch-env-safety-deploy-from-non-main
severity: P0
symptoms:
  - User runs `wrangler deploy --env production` from a feature branch
  - Production gets dev-branch code
root_cause: |
  Wrangler doesn't refuse this; it's the user's responsibility.
prior_incidents: 8 cass quotes (the most-cited "I shipped to prod from the wrong branch")
currently_auto_detected: no
currently_auto_fixed: no (this is a refuse-with-redirect, not a fix)

# FM-fm-daemon-state-port-conflict
severity: P1
symptoms:
  - `wrangler dev` exits 1 with EADDRINUSE
root_cause: |
  Port 8787 is held by a forgotten previous wrangler dev (or another tool).
currently_auto_detected: no
currently_auto_fixed: no (killing another process is user action)

# FM-fm-wrangler-toml-malformed
severity: P0
symptoms:
  - `wrangler` exits with TOML parse error
root_cause: |
  Manual edit broke the file.
currently_auto_detected: yes (wrangler reports it)
currently_auto_fixed: no (semantic intent unknown)

# FM-fm-rate-limits-budget-exhausted
severity: P2
symptoms:
  - 429 from API
root_cause: |
  Recent deploy spam hit the rate limit window.
currently_auto_detected: no (would need online probe)
currently_auto_fixed: no (wait for window reset)
```

Total inventory: 16 FMs.

---

## Phase 2 — Repair Specs

Each FM gets a spec. Several spec themes:

- Auth-state FMs: detect-only; manual remediation cites `wrangler auth login`.
- Vendor-drift FMs: detect online (with `--online`); refuse to auto-reconcile (intent ambiguity).
- Branch-env-safety: detect via git+args; refuse if dangerous; offer `--allow-non-main` escape.
- Daemon-state: detect via socket probe; refuse to kill; emit holder PID.

Sample spec for the highest-leverage FM:

```markdown
# RS-fm-branch-env-safety-deploy-from-non-main

severity: P0
currently_auto_detected: no
currently_auto_fixed: no  (refuse-with-redirect)

## Detector (pure)
fn detect_branch_env_unsafe_deploy(repo, args):
    if args.subcommand != "deploy": return None
    target_env = args.flags.get("--env")
    if target_env != "production": return None
    branch = git_current_branch(repo)
    if branch == "main": return None  # or = the project's documented production branch
    return Finding {
        id: "fm-branch-env-safety-deploy-from-non-main",
        severity: P0,
        evidence: { branch: branch, target_env: target_env },
        remediation: {
            command_or_instruction: "git switch main && my-tool-doctor wrangler deploy --env production",
            override: "Add --allow-non-main if you really mean to deploy from this branch (requires --yes)",
            auto_fixable: false,
        },
    }

## Fixer
None — refuse-with-redirect. Manual remediation only.

## Backup spec
None — no mutations.

## Inverse
None — no mutations to undo.

## Idempotence proof sketch
Pure read; running twice gives the same finding.

## Fixture spec
tests/doctor_fixtures/fm-branch-env-safety-deploy-from-non-main/:
- corrupt.sh: in a feature branch, attempt `<my-tool>-doctor wrangler deploy --env production`
- assert.sh: assert exit 4; assert stderr mentions "switch to main" or "--allow-non-main"
```

This is one of the most-valued additions. The FM's frequency in cass is high; the cost when it fires is "production incident".

---

## Phase 3 — Synthesis

Synthesizer produces:

- **dependency_graph.json**: auth-state must be valid before any vendor-drift detector can run; wrangler.toml must parse before any other detector that reads it.
- **conflict_matrix.md**: branch-env-safety and `--allow-non-main` are mutually exclusive at runtime (the user explicitly opts out of the safety).
- **safety_envelope.md**:
  - Write scopes: `<repo>/.wrangler/` (wrangler's local cache), `~/.config/wrangler/` (only with explicit user authorization to mutate).
  - The wrapper NEVER edits the user's `wrangler.toml` (read-only).
  - The wrapper NEVER triggers vendor-side mutations without explicit `--apply` flag.

- **playbook.md**: three chapters per template. The "what doctor will and will not do" includes:
  - WILL detect token expiry, refuse risky deploys, probe vendor for resource drift.
  - WILL NOT log in as you, create resources, or auto-fix wrangler.toml.

---

## Phase 4 — Implementation

Implemented as a TypeScript wrapper (`@my-tool/wrangler-doctor` npm package) since the project already uses Node.

The chokepoint: `mutate(path, op)` for the few cases the wrapper does mutate (e.g., `~/.config/wrangler/<our-cache-file>`).

```typescript
// crates/<my-tool>-doctor/src/main.ts
import { Command } from "commander";
import { mutate, Op } from "./mutate.js";

const program = new Command("<my-tool>-doctor");

program.command("wrangler [args...]")
    .description("Run wrangler-doctor checks before forwarding to wrangler")
    .option("--allow-non-main", "Override branch-env-safety check", false)
    .option("--yes", "Required with --force/--allow-non-main", false)
    .action(async (args, opts) => {
        const findings = await runDetectors(process.cwd(), args, opts);
        if (findings.some(f => f.severity === "P0" && !f.remediation.auto_fixable)) {
            console.error(JSON.stringify({ exit_code: 4, findings }));
            process.exit(4);
        }
        // forward to actual wrangler
        const result = spawnSync("wrangler", args, { stdio: "inherit" });
        process.exit(result.status ?? 0);
    });

program.parseAsync(process.argv);
```

The detectors live in `src/detectors/<fm-id>.ts`. Each is a pure function. The "fixers" (mostly refusals) live in `src/fixers/<fm-id>.ts`.

The doctor `--json` output for diagnose mode follows the standard schema. The `--robot-triage` mega-command is implemented.

---

## Phase 5 — Safety Harness

For the mutating fixers (only ~3 in this project — most are refuse-with-redirect):

- **fm-secrets-credentials-perms-too-permissive**: chmods `~/.config/wrangler/*` if mode > 0600. Reversibility test: ✓. Idempotence: ✓. Crash-recovery: trivial (chmod is atomic). Concurrency: lock acquired.

- **fm-cache-stale-completion-script**: rewrites `~/.zsh_completions/_wrangler` if stale. All five verifiers: ✓.

- **fm-our-config-cache-version-mismatch**: rewrites `~/.config/<my-tool>-doctor/cache.json` on schema bump. All five verifiers: ✓.

For the refuse-only "fixers", the safety harness is degenerate — they never mutate, so reversibility/idempotence are trivial.

---

## Phase 6 — Scorecard

```
Aggregate score: 805
Per-FM medians (top 5):
  fm-branch-env-safety-deploy-from-non-main         900   (high blast radius; handles P0 cleanly)
  fm-auth-state-token-expired-locally               850   (offline detect; manual fix is OK)
  fm-wrangler-toml-malformed                        820   (wrangler reports it; we surface clearly)
  fm-vendor-drift-resource-deleted-remotely         750   (online detect; refuse-fix; hint to user)
  fm-daemon-state-port-conflict                     720   (detect-only; PID identification is the value)

Heatmap weakness: automation_degree (median 600 for this project; many findings are
manual-remediation-only).
```

This is acceptable for a distributed CLI. The doctor's automation ceiling is bounded by the vendor-side intent ambiguity; refusing is the right behavior. Score ≥ 800 with manual_remediations correctly listed in capabilities is the design's success metric.

---

## Phase 7-10

(Same shape as the br worked example. Fresh-eyes catches a bug in the OAuth token validity detector — it was treating expired-but-not-revoked tokens as valid; fixed in round 2. Phase 9 fixture suite has 16 fixtures + 4 combinatorial pairs.)

---

## What's different about distributed-CLI doctors

- **More refuse-with-redirect, less auto-fix.** Vendor-side state is the user's intent territory.
- **`--online` is more central.** Roughly half the detectors need network.
- **The trust manifest** is a key concept (Pattern 11 + Pattern 9) — the doctor's bundled CA bundles for vendor TLS validation, the bundled signature for self-update.
- **Pre-deploy hooks are valuable.** A `<tool> doctor predeploy` mega-command run as a pre-deploy hook is high-leverage.

---

## What's the same

- The kernel's 17 universal axioms still hold; mature distributed doctors also need the 7 stretch axioms.
- The mutate() chokepoint is still load-bearing for the few mutating fixers.
- Phase 5 safety harness still applies (just to fewer fixers).
- The scorecard rubric and Polish Bar are unchanged.

---

## When to apply this exemplar

Use this worked example as a template when applying the skill to:

- `vercel` CLI doctor
- `gh` (GitHub) CLI doctor
- `gcloud` CLI doctor
- `aws` CLI doctor
- `stripe-cli` doctor
- `supabase` CLI doctor
- `mcp-agent-mail` CLI doctor
- Any CLI that's primarily a vendor-API client.

The bones of the methodology are identical; only the FM enumeration and the auth/vendor/rate-limit subsystems differ.
