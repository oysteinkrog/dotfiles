# Bootstrap & Detection

## What detect-support-surface.sh Looks For

```
SaaS custom DB:
  rg -l "support_tickets|supportTickets|support_messages" src/ db/
  ls src/app/api/admin/support 2>/dev/null
  ls src/app/admin/support 2>/dev/null
  rg -l "ticketPriorityEnum|slaStatusEnum" src/

SaaS third-party (any of):
  grep -E "(ZENDESK|INTERCOM|HELPSCOUT|FRESHDESK|CRISP|PLAIN|LINEAR|FRONT|GORGIAS|HUBSPOT|SALESFORCE|JSM|ZOHO_DESK|PYLON)_" .env .env.example .env.production 2>/dev/null
  rg -l "@zendesk/zendesk|intercom-client|@helpscout|@plain/sdk" package.json
  rg -l "ZendeskClient|IntercomClient|HelpScoutApi" src/

GitHub-only:
  ls .github/ 2>/dev/null
  test -f LICENSE  # OSS signal
  gh repo view --json visibility -q .visibility 2>/dev/null  # public?

None-yet (SaaS but no ticketing):
  has Next.js / Rails / Django + auth + payments
  no support_* tables
  no third-party env vars
  → offer /user-support-ticketing-system-for-saas
  → if owner says yes:
       ./scripts/scaffold-ticketing.sh "$WS"   # auto-installs ticketing
                                                # + supabase
                                                # + admin-page-for-nextjs-sites
                                                # + stripe-checkout
                                                # then prints a handoff line
                                                # the agent uses to invoke
                                                # /user-support-ticketing-system-for-saas
       (idempotent; jsm install is a no-op when a skill is already on disk)
```

The detector writes a JSON manifest used by every other phase. Shape:

```text
{
  "project_path": "/data/projects/foo",
  "surfaces": ["github-only"] | ["saas-custom"] | ["saas-third-party","github-only"] | ["none-yet"],
  "framework": "nextjs|rails|django|sveltekit|laravel|other",
  "language": "ts|py|rb|php|go|rust|other",
  "auth_strategy": "supabase|clerk|nextauth|custom",
  "third_party_provider": "zendesk|intercom|helpscout|freshdesk|crisp|plain|linear|front|gorgias|hubspot|salesforce|jira-service-management|zoho-desk|pylon" | null,
  "outbound_email": "resend|sendgrid|postmark|ses|mailgun|smtp" | null,
  "base_url": "https://example.com" | null,
  "github_repo": "owner/name" | null,
  "github_visibility": "PUBLIC|PRIVATE|INTERNAL|unknown",
  "missing_skills": ["github","admin-page-for-nextjs-sites","supabase","..."]
}
```

## Scope / Maturity Assessment

After detecting surfaces, classify the support workflow on two separate axes.
Do not force every project into a single maturity ladder.

| Axis | Low | Medium | High |
|---|---|---|---|
| Infrastructure | Email/GitHub only; no SLA fields | Custom or third-party queue with status and owner | Queue, SLA, admin UI, audit, provider integrations |
| Process | Owner answers ad hoc | Decision matrix and templates exist | Evidence anchors, drills, outcomes, retros, metrics |

Use the assessment to avoid overbuilding:

- **Low infra / low process:** onboard docs first; do not build automation until
  the owner confirms channels and policy.
- **Low infra / medium process:** GitHub or email may be enough; add adapter and
  templates before proposing a full ticketing system.
- **Medium infra / low process:** map the queue and write policy/runbooks before
  adding AI assist or scheduled triage.
- **High infra / low process:** the risk is false confidence; prioritize
  validators, fire drills, and owner confirmation gates.
- **High infra / high process:** scheduled no-send triage and outcome mining may
  be appropriate after adapter validation.

The assessment should change scope, not become a bureaucracy. If a 2-person
project has 3 support items per month, a clean adapter plus owner-approved
templates may deliver more value than a seven-phase support build.

## Bootstrap Helper Skills

Skill bootstrap mirrors `/documentation-website-for-software-project` Phase 0.5:

```bash
./scripts/check-skills.sh <project>/.claude/support-triage/.workspace
# → prints inventory table; writes skill_inventory.json

./scripts/install-referenced-skills.sh <project>/.claude/support-triage/.workspace
# → reads inventory, runs `jsm install <name>` for each missing skill
```

If `jsm` is not installed and the user wants premium skills:

```bash
# Linux / macOS
curl -fsSL https://jeffreys-skills.md/install.sh | bash

# Windows
irm https://jeffreys-skills.md/install.ps1 | iex

# Then: jsm login (browser OAuth)
```

Premium skills require an active jeffreys-skills.md subscription. **Missing skills are non-blocking** — fall through to inline guidance and continue.

## Policy Defaults

Until the owner has answered the policy elicitation, the skill defaults to:

| Question | Default |
|---|---|
| Send email without approval? | NO — always confirm |
| SLA on P2 first response | 48h |
| Refunds within 14 days | Owner approves each |
| Stale GitHub issues (pre-2025) | Close with stale-template comment |
| PR contributions on OSS | Decline politely, mine for ideas |
| Feature requests | Acknowledge + log; no implementation without owner direction |

These defaults live in [POLICY-ELICITATION.md](POLICY-ELICITATION.md). Onboarding Step 4 replaces them with project-specific answers.
