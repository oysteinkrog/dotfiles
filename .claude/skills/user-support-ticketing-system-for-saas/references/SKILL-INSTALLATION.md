# Skill Bootstrap — Installing Companion Skills via jsm

This skill calls into other skills, most importantly **`/de-slopify`**, which is a Hard Invariant (every customer-facing reply MUST run through it). Before any of the EXACT PROMPTS, run the bootstrap to ensure the companion skills are present.

## TL;DR

```bash
# 1. Inventory what's installed (non-mutating)
./scripts/check-companion-skills.sh

# 2. Install missing ones via jsm (requires a paid jeffreys-skills.md account)
./scripts/install-companion-skills.sh
```

If `/de-slopify` ends up missing and can't be installed, **stop**. Fix that first — the skill cannot meet its Hard Invariant otherwise.

## What gets installed

| Skill | Requirement | Why this skill needs it |
|---|---|---|
| `de-slopify` | **REQUIRED** | Every customer-facing reply runs through it (Hard Invariant) |
| `user-support-triage-for-saas-and-open-source-projects` | optional | Operates the queue this skill builds; shares handoff contract |
| `admin-page-for-nextjs-sites` | optional | The admin cockpit this skill plugs into |
| `supabase` | optional | Default DB / auth stack |
| `stripe-checkout` | optional | Tier resolution for SLA tiers |
| `vercel` | optional | Default deploy/cron host |
| `e2e-testing-for-webapps` | optional | Reply-flow integration tests |
| `testing-real-service-e2e-no-mocks` | optional | Mock-free reply tests against real DB/email |
| `security-audit-for-saas` | optional | Pre-launch sweep on the new admin endpoints |
| `ga4` | optional | Funnel events for ticket-create / reply / resolution |
| `saas-customer-analytics` | optional | MRR/churn/behavior signals tied to tickets |

`check-companion-skills.sh` writes `<workspace>/skill_inventory.json`. `install-companion-skills.sh` consumes that and runs `jsm install <name>` for each missing entry.

## Search paths

The check script looks for installed skills in this order:
1. `$CLAUDE_SKILLS_PATH` (if set)
2. `~/.claude/skills/<name>/SKILL.md`
3. `.claude/skills/<name>/SKILL.md` (project-local)

## Installing jsm (the CLI)

If `jsm` isn't on `PATH`:

```bash
curl -fsSL https://jeffreys-skills.md/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"   # add to .bashrc / .zshrc
jsm --version
jsm doctor        # non-destructive health check
jsm doctor --fix  # auto-repair PATH shims, config dirs
```

Installer drops the binary at `~/.local/bin/jsm` (Unix) or `%LOCALAPPDATA%\jsm\jsm.exe` (Windows).

## Authenticate

`jsm login` opens a browser tab for Google OAuth and writes encrypted credentials to `~/.config/jsm/credentials.enc`.

```bash
jsm login
jsm whoami
```

### Headless / SSH sessions

If a browser won't open on the host, two options:

**Option A — API key from dashboard:**
```bash
jsm auth                       # interactive prompt for API key
# Get one at https://jeffreys-skills.md/account
```

**Option B — print URL, open elsewhere:**
```bash
jsm login --print-url          # paste URL into a desktop browser
```

### Env-passphrase fallback

```bash
export JSM_ALLOW_ENV_PASSPHRASE=1
export JSM_CREDENTIALS_PASSPHRASE='<your-passphrase>'
jsm whoami     # should now succeed silently in scripts
```

## Subscription

`/de-slopify` and several others are premium skills on jeffreys-skills.md ($20/month). `jsm whoami --json` reports subscription status. If unsubscribed:

- `de-slopify` install will fail with `subscription required`.
- The doctor will keep failing the `de-slopify-installed` required check.
- The skill cannot meet its Hard Invariant. Either subscribe or do the slopification work inline by hand against every customer-visible reply (much more error-prone).

## What happens if /de-slopify isn't installed

Two failure modes:

1. **doctor.sh fails the `de-slopify-installed` required check** — exits 1, blocks the EXACT PROMPTS.
2. **install-companion-skills.sh exits 1** — required skill couldn't be installed. The log at `<workspace>/skill_inventory_install.md` records the reason (subscription / network / not-in-catalog).

In either case, fix before shipping. A built ticketing system without `/de-slopify` will leak LLM tells to customers and torch trust faster than any other failure mode in this skill.

## What happens for missing optional skills

The build proceeds. Each missing optional skill degrades gracefully:

- **No triage skill** → handoff artifacts still produced; nobody reads them yet
- **No supabase / stripe-checkout / vercel** → use FRAMEWORK-PORTABILITY.md / PROVIDER-PORTABILITY.md fallbacks
- **No e2e testing skills** → integration tests still pass; no agent to refine them
- **No ga4 / saas-customer-analytics** → ticket-driven funnel/churn loops dormant; can be re-enabled later

`<workspace>/skill_inventory_install.md` lists which fallbacks are in play so the build is auditable.

## Re-running

The bootstrap is idempotent. Re-run `check-companion-skills.sh` whenever:
- New skill version released (re-install with `jsm install <name> --force`)
- Subscription changed
- A new project is using this skill

## Troubleshooting

| Symptom | Fix |
|---|---|
| `jsm: command not found` | Run the installer; add `~/.local/bin` to PATH |
| `jsm whoami` says "Not logged in" | `jsm login` (or `jsm auth` for headless) |
| `jsm install de-slopify` fails with "subscription required" | Subscribe at https://jeffreys-skills.md or apply slopification inline |
| `jsm install` works but doctor still flags missing | `$CLAUDE_SKILLS_PATH` mismatch — see "Search paths" above |
| Headless host with encrypted credentials | Set `JSM_ALLOW_ENV_PASSPHRASE` / `JSM_CREDENTIALS_PASSPHRASE` |
| `jsm doctor` reports config drift | `jsm doctor --fix` |
