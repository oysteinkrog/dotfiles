# Skill Bootstrap — Installing Referenced Skills via jsm

## Contents
- [Referenced-skill matrix](#referenced-skill-matrix) — full list with optional/required + inline fallbacks.
- [Bootstrap flow](#bootstrap-flow) — the sequence run at start.
- [Installing jsm](#installing-jsm) — curl-to-bash installer for the CLI.
- [Logging in to jsm](#jsm-login-flow) — OAuth via browser + headless fallback.
- [Subscription detection](#subscription-detection).
- [Graceful-Degradation Invariant](#graceful-degradation-invariant) — inline fallback per referenced skill.
- [Pinning skill versions](#pinning-skill-versions).

## Overview

This skill composes many other skills. Before triage runs, check which are available and install the missing ones. If the user has a paid [jeffreys-skills.md](https://jeffreys-skills.md) subscription ($20/month), the `jsm` CLI installs any referenced skill in one command. If they don't, we gracefully degrade — every referenced skill has an inline fallback.

Don't block onboarding on missing skills — skip and log to `<workspace>/missing_skills.md`. The user can install them post-run.

---

## Referenced-Skill Matrix

Skills this triage skill will invoke or cite if present:

| Skill | Phase used | Graceful fallback if missing |
|---|---|---|
| `operationalizing-expertise` | structural | this skill embeds the operator-library methodology inline |
| `codebase-archaeology` | Onboarding Phase 2 (mapping support code paths) | inline grep recipes in [BOOTSTRAP.md](BOOTSTRAP.md) |
| `codebase-report` | Onboarding Phase 2 (architecture report) | template inlined in [assets/ONBOARDING-TEMPLATE.md](../assets/ONBOARDING-TEMPLATE.md) |
| `github` (gh) | GitHub-fork triage | raw `gh` commands in [GITHUB-FORK.md](GITHUB-FORK.md) |
| `admin-page-for-nextjs-sites` | SaaS-custom triage (admin UI patterns) | inline TanStack patterns in [SAAS-CUSTOM.md](SAAS-CUSTOM.md) |
| `supabase` | SaaS auth/DB queries during diagnosis | raw SQL via psql / Supabase CLI |
| `stripe-checkout` | refund execution | raw Stripe CLI / API in [runbooks/REFUND.md](runbooks/REFUND.md) |
| `ga4` | analytics queries during diagnosis | direct GA4 Data API |
| `saas-customer-analytics` | tier resolution + churn risk | manual SQL in [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) |
| `user-support-ticketing-system-for-saas` | offered when surface = `none-yet`; on owner's yes, auto-installed + auto-invoked via `scripts/scaffold-ticketing.sh` (see §"Auto-Scaffold On Owner Approval" below) | document a manual-only cadence and continue triage on the existing surface |
| `idea-wizard` | feature-request handling | inline FEATURE-REQUEST template in [RESPONSE-TEMPLATES.md](RESPONSE-TEMPLATES.md) |
| `e2e-testing-for-webapps` | regression-test writing after fixing user bugs | manual Playwright pattern in [TRIAGE-WORKFLOW.md](TRIAGE-WORKFLOW.md) |
| `security-audit-for-saas` | when SECURITY-DISCLOSURE runbook fires | manual checklist in [runbooks/SECURITY-DISCLOSURE.md](runbooks/SECURITY-DISCLOSURE.md) |
| `multi-model-triangulation` | 🪞 SECOND-OPINION operator | manual approach in [MULTI-MODEL.md](MULTI-MODEL.md) |
| `cass` | mining prior triage sessions | optional; doesn't block any phase |
| `agent-mail` | multi-agent triage coordination | single-agent mode if absent |
| `beads-workflow` / `br` / `bv` | filing follow-up bugs from triage | open GitHub issues with `gh issue create` |
| `de-slopify` | polishing reply drafts before send | manual list of "AI-tells" in [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md) |

So even with just `gh` + `curl` + the project's existing tooling, this skill runs end-to-end. Every referenced skill has an inline fallback.

---

## Bootstrap Flow

This is the exact sequence run at the start of an onboarding (and on the first triage session per machine):

```bash
WS=<project>/.claude/support-triage/.workspace
mkdir -p "$WS"

# 1. Inventory what's installed
./scripts/check-skills.sh "$WS"

# 2. If jsm is missing, ask the user about installing
#    (the script's output guides the conversation)

# 3. If missing skills + jsm available + authenticated:
./scripts/install-referenced-skills.sh "$WS"

# 4. Log anything that's still missing to a manifest
ls "$WS/skill_inventory.json" "$WS/missing_skills.md"
```

The agent reads `$WS/skill_inventory.json` and decides per-skill whether to install (user opt-in), use inline fallback, or skip.

---

## Installing jsm

### Is jsm already installed?

```bash
command -v jsm >/dev/null && jsm --version || echo "jsm not installed"
```

### Install jsm

**Linux / macOS:**
```bash
curl -fsSL https://jeffreys-skills.md/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://jeffreys-skills.md/install.ps1 | iex
```

The installer drops the binary at `~/.local/bin/jsm` (Unix) or `%LOCALAPPDATA%\jsm\jsm.exe` (Windows). On a fresh Unix shell:
```bash
export PATH="$HOME/.local/bin:$PATH"  # add to .bashrc / .zshrc if missing
```

Verify:
```bash
jsm --version
jsm setup           # first-time: provisions ~/.config/jsm and skills directories
```

---

## jsm Login Flow

### Standard (workstation with browser)

```bash
jsm login
# → prints a URL; browser opens; user signs in with the Google account
#   tied to their jeffreys-skills.md subscription
# → credentials encrypted to ~/.config/jsm/credentials.enc
```

Verify:
```bash
jsm whoami
# → prints email + subscription tier
```

### Headless / SSH session

If you're SSHed into the box, the local browser can't auto-open. Two options:

**Option 1 — API key (preferred for headless):**
```bash
# 1. Owner generates an API key at https://jeffreys-skills.md/account/api-keys
# 2. On the headless box:
jsm auth
# → interactive prompt for the API key; stored at ~/.config/jsm/credentials.enc
```

**Option 2 — Cross-device OAuth:**
```bash
jsm login --print-url
# → copy the URL, open it in a browser on any machine; sign in;
#   credentials land back on the headless box via the OAuth callback
```

### Non-interactive credentials decryption (CI / cron)

```bash
export JSM_ALLOW_ENV_PASSPHRASE=1
export JSM_CREDENTIALS_PASSPHRASE='<your-passphrase>'
```

Only set in session-local env; never commit. Without these, `jsm whoami` on a headless box may emit:
```
WARN  Ignoring unusable encrypted credential fallback
      Cannot prompt for passphrase in non-interactive environment.
      Set JSM_ALLOW_ENV_PASSPHRASE=1 and JSM_CREDENTIALS_PASSPHRASE
      to decrypt file-based credentials in headless mode.
```

That warning is informational, not blocking — `jsm install` still works if you already have a valid session.

---

## Subscription Detection

```bash
jsm whoami --json | jq -r '.subscription.status // "unknown"'
# → "active" (paid), "trial", "free", or "expired"
```

If not `active` and the user wants premium skills, point them at https://jeffreys-skills.md — the subscription is $20/month and unlocks every skill in the matrix above.

If they decline, **do not pester** — log the decision and proceed with inline fallbacks.

---

## Installing Skills

Once authenticated:

```bash
# Install one
jsm install codebase-archaeology

# Install with related/required deps
jsm install user-support-ticketing-system-for-saas --related

# Bulk — install everything referenced by this skill
./scripts/install-referenced-skills.sh <workspace>
```

Installed skills land at `~/.claude/skills/<name>/` and are immediately available to Claude Code (no restart — skills are discovered per-invocation).

### What if jsm is installed but the user doesn't have a subscription?

`jsm install <skill>` on a free account installs free/public skills only. Premium ones return a `SUBSCRIPTION_REQUIRED` error. In that case:
1. Log the skill as missing in `<workspace>/missing_skills.md`.
2. Offer the user the subscription option (point them at https://jeffreys-skills.md).
3. Proceed with the inline fallback for that skill's role.
4. Do not pester repeatedly — one ask per project, then continue.

---

## Auto-Scaffold On Owner Approval (surface = `none-yet`)

When BOOTSTRAP detects `surface = none-yet` (SaaS-shaped project with auth and payments but no support_* tables and no third-party env vars), the agent **offers** to scaffold a ticketing system. The offer must name what will happen on yes:

```
Detected: SaaS project with no ticketing system or third-party adapter
   (no support_* tables, no ZENDESK_*/INTERCOM_*/etc. env vars)

If you'd like, I can scaffold an in-app ticketing system end-to-end. This will:

  1. Ensure these skills are installed locally via jsm (idempotent — no-op if
     already on disk):
       - user-support-ticketing-system-for-saas (the scaffolder)
       - supabase, admin-page-for-nextjs-sites, stripe-checkout (co-deps)
  2. Invoke /user-support-ticketing-system-for-saas to scaffold the schema,
     SLA engine, APIs, admin queue, user inbox, outbound email, and cron.
     Each scaffold step gets its own ✓ CONFIRM before any code lands.

  Estimated time: 20-40 minutes. You'll review every change before it lands.

  → yes  (scaffold)
  → no   (continue triage with manual-only cadence)
```

On **yes**, the agent runs `scripts/scaffold-ticketing.sh "$WS"`. The script:

1. Re-runs `check-skills.sh` to refresh `skill_inventory.json`.
2. Targeted-installs the ticketing skill plus co-deps via `jsm install` (idempotent — no-op if already installed locally).
3. Re-runs `check-skills.sh` to refresh the inventory (so post-install state is recorded; this also rewrites `missing_skills.md` if any installs failed).
4. Emits two single-line markers on stdout:
   - `SCAFFOLD-TICKETING-READY <path>` — path to the generated `triage-handoff.md` containing project context (framework, language, auth_strategy, outbound_email, base_url, github_repo).
   - `TICKETING-SKILL-STATUS present|missing` — whether the canonical ticketing skill ended up installed locally.
   The handoff file itself also carries an "Install Status" section so a downstream agent reading the file (without seeing stdout) still knows what to do.
5. **If status is `present`**: the agent invokes `/user-support-ticketing-system-for-saas` with that handoff file as input. **If status is `missing`**: the agent does NOT invoke the skill — it falls back to the inline ticketing-design template in `/user-support-ticketing-system-for-saas/SKILL.md`, using the handoff for project context.

On **no**, the agent records the decision in `<workspace>/owner-decisions.md` (one line: `surface=none-yet declined-scaffold @ <ISO-timestamp>`) and proceeds with manual-only triage on whatever inbound channel exists (email, contact form, community).

### What the script does NOT do

- It does not invoke the ticketing skill itself — that is an agent action, gated behind a separate `✓ CONFIRM` for the actual scaffold work.
- It does not write any application code. The handoff file is read-only orientation for the next skill.
- It does not commit or push. The ticketing skill manages its own commit cadence.

### Why split it this way

The bootstrap install is mechanical and safe (idempotent jsm calls). Invoking the ticketing skill is a high-stakes opinionated install — it writes DB migrations, API routes, admin UI, and email-cron wiring. Both gates (confirmed-on-offer + confirmed-before-scaffold) are how the Confirmation Rule extends to infrastructure work, not just outbound replies.

### Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `scaffold-ticketing.sh` exits 2 | `<workspace>` not provided or doesn't exist | Pass the absolute path to `<project>/.claude/support-triage/.workspace` |
| Install of ticketing or co-deps doesn't land | jsm absent or unauthenticated → install loop is skipped entirely; or jsm is available but a per-skill `jsm install` fails (subscription required, network error) | Either way the inventory written by `check-skills.sh` reflects the still-missing names in `skill_inventory.json` + `missing_skills.md`. The handoff is still written. Agent should fall back to the inline ticketing-design template instead of invoking the skill. |
| `SCAFFOLD-TICKETING-READY` never emitted | Earlier step (`check-skills.sh`) errored | Run `./scripts/check-skills.sh "$WS"` directly, fix the inventory, re-run scaffold-ticketing.sh |

---

## Graceful-Degradation Invariant

> **No phase of this skill should require any other skill to run.** Every referenced skill has an inline fallback. The referenced skills are *accelerants*, not prerequisites.

Concrete examples:

| Without skill | Fallback |
|---|---|
| No `codebase-archaeology` | Use the grep recipes in [BOOTSTRAP.md](BOOTSTRAP.md) Phase 2; produce `01-architecture.md` manually |
| No `multi-model-triangulation` | The 🪞 SECOND-OPINION operator falls back to a single-model deep-think pass with explicit checklist (see [MULTI-MODEL.md](MULTI-MODEL.md)) |
| No `agent-mail` | Run triage serially without inter-agent reservations |
| No `de-slopify` | Apply the AI-tell remover list inline (see [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md)) |
| No `cass` | Skip historical-pattern mining; rely on the project's own `06-recurring-issues.md` |

When writing new content in this skill, honor the invariant: every time you reference another skill, ensure the reader can still do the work without it.

---

## Pinning Skill Versions

For reproducibility (e.g., onboarding a customer's project where you'll re-run triage on the same fingerprint):

```bash
jsm pin codebase-archaeology --version 0.4.2
jsm pin user-support-ticketing-system-for-saas --version latest
jsm versions codebase-archaeology   # see the version trail
jsm rollback codebase-archaeology --version 0.3.9   # if a new version regresses
```

Pinned versions stay until `jsm unpin <name>`. Pinned skills don't auto-update on `jsm sync`.

---

## Script Contracts

`check-skills.sh` and `install-referenced-skills.sh` guarantee:

- Both exit 0 even when skills are missing or jsm is absent; they print status and continue.
- They write `skill_inventory.json` with the shape:
  ```json
  {
    "checked_at": "2026-04-27T20:00:00Z",
    "jsm_available": true,
    "jsm_authenticated": true,
    "subscription_tier": "active",
    "skills": [
      {"name": "codebase-archaeology", "status": "present",
       "path": "/home/user/.claude/skills/codebase-archaeology"},
      {"name": "multi-model-triangulation", "status": "missing",
       "can_install_via_jsm": true},
      ...
    ]
  }
  ```
- The main agent reads this file and decides per-skill whether to `jsm install` (user opt-in), use inline fallback, or skip.

---

## When In Doubt — Skip And Log

Missing helper skills NEVER block a triage session. The pipeline logs them to `missing_skills.md`:

```markdown
# Missing helper skills (logged at 2026-04-27T20:00Z)

- `multi-model-triangulation` — used by 🪞 SECOND-OPINION operator on hard cases.
  - fallback: single-model deep-think pass per [MULTI-MODEL.md](MULTI-MODEL.md)
- `de-slopify` — used to polish reply drafts before send.
  - fallback: inline AI-tell remover in [VOICE-CALIBRATION.md](VOICE-CALIBRATION.md)
- ...
```

The user sees this at session end and can decide to `jsm install` for the next session.
