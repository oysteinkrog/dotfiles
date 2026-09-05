# SaaS Third-Party Ticketing Fork

## Table of Contents

- [Provider Cheatsheet](#provider-cheatsheet)
- [Onboarding Steps](#onboarding-steps)
- [Reply Mechanics](#reply-mechanics)
- [Common Pitfalls](#common-pitfalls)
- [When To Recommend Migrating Off](#when-to-recommend-migrating-off)

<!-- TOC: Provider Cheatsheet | Onboarding Steps | Reply Mechanics | Common Pitfalls | When To Recommend Migrating Off -->

When the project pushes support to a third-party (Zendesk, Intercom, Help Scout, Freshdesk, Crisp, Plain, Linear, Front, Gorgias, HubSpot, Salesforce, Jira Service Management, Zoho Desk, Pylon, etc.). Two integration paths exist for each:

1. **MCP server** — preferred when available; agent calls tools natively
2. **REST API** — fallback; use `curl` against the documented endpoints

The onboarding pass should pick one per provider and document credentials in `07-secrets.md`.

## Provider Cheatsheet

| Provider | Common env vars | MCP server | REST docs |
|---|---|---|---|
| **Zendesk** | `ZENDESK_SUBDOMAIN`, `ZENDESK_EMAIL`, `ZENDESK_API_TOKEN` | community / unofficial | `https://developer.zendesk.com/api-reference/ticketing/tickets/tickets/` |
| **Intercom** | `INTERCOM_ACCESS_TOKEN` | official + community | `https://developers.intercom.com/intercom-api-reference` |
| **Help Scout** | `HELPSCOUT_APP_ID`, `HELPSCOUT_APP_SECRET` (OAuth2) | community | `https://developer.helpscout.com/mailbox-api/` |
| **Freshdesk** | `FRESHDESK_DOMAIN`, `FRESHDESK_API_KEY` | community | `https://developers.freshdesk.com/api/` |
| **Crisp** | `CRISP_IDENTIFIER`, `CRISP_KEY`, `CRISP_WEBSITE_ID` | community | `https://docs.crisp.chat/api/v1/` |
| **Plain** | `PLAIN_API_KEY` | official | `https://www.plain.com/docs/api-reference` |
| **Linear** (used as a support tool) | `LINEAR_API_KEY` | official | `https://developers.linear.app/docs/graphql/working-with-the-graphql-api` |
| **Front** | `FRONT_API_TOKEN` | community | `https://dev.frontapp.com/reference/introduction` |
| **Gorgias** | `GORGIAS_DOMAIN`, `GORGIAS_API_KEY` | community | `https://developers.gorgias.com/reference` |
| **HubSpot Service Hub** | `HUBSPOT_ACCESS_TOKEN` | community | `https://developers.hubspot.com/docs/api/crm/tickets` |
| **Salesforce Service Cloud** | `SALESFORCE_CLIENT_ID`, `SALESFORCE_CLIENT_SECRET`, `SALESFORCE_INSTANCE_URL` | official/community | `https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/` |
| **Jira Service Management** | `JSM_SITE_URL`, `JSM_EMAIL`, `JSM_API_TOKEN`, `JSM_PROJECT_KEY` | Atlassian ecosystem | `https://developer.atlassian.com/cloud/jira/service-desk/rest/` |
| **Zoho Desk** | `ZOHO_DESK_ORG_ID`, `ZOHO_DESK_REFRESH_TOKEN` | community | `https://desk.zoho.com/DeskAPIDocument` |
| **Pylon** | `PYLON_API_KEY` | official/community | `https://docs.usepylon.com/` |

**Always verify the latest provider docs** — APIs and MCP servers churn. The onboarding pass should run fresh web research against official docs before committing to an integration, then record the provider doc URL + access date in `01-architecture.md`. Don't just copy this table; use it as a starting point.

## Onboarding Steps

### 1. Identify The Provider

```bash
# Look for env vars
grep -hE "(ZENDESK|INTERCOM|HELPSCOUT|FRESHDESK|CRISP|PLAIN|LINEAR|FRONT|GORGIAS|HUBSPOT|SALESFORCE|JSM|ZOHO_DESK|PYLON)_" \
  <project>/.env <project>/.env.example <project>/.env.production 2>/dev/null

# Look for SDK imports
rg -l "@zendesk/zendesk|intercom-client|@helpscout|@plain/sdk|crisp-api|@front/client|@hubspot|jsforce|pylon" \
  <project>/package.json <project>/Gemfile <project>/requirements.txt 2>/dev/null

# Look for outbound webhook handlers (project receives events from provider)
rg --files <project>/src -g "*webhook*"
```

### 2. Choose MCP vs REST

```
Owner has an MCP server installed for the provider?
├── Yes → use MCP tools (highest leverage)
└── No  → can the owner install one?
        ├── Yes → install + restart, then use MCP
        └── No  → fall back to REST via curl + documented API
```

### 3. Ask For Credentials (Once)

Use the [POLICY-ELICITATION.md](POLICY-ELICITATION.md) batched prompt format. Example for Zendesk:

```
🔑 ONBOARDING — CREDENTIALS NEEDED

For Zendesk integration, we need three values from your account:

1. Subdomain (the X in https://X.zendesk.com)
2. Admin email (an account with API access — usually yours)
3. API token (Zendesk Admin → Apps and integrations → APIs → Settings)

Once provided, we'll store them in your project's secrets mechanism
(prefer your existing manager — Doppler / 1Password / Vercel envs / .env.local)
and document the env var NAMES (not values) in 07-secrets.md.

Are you OK using the existing secrets mechanism, or want to set one up first?
```

**Never paste the actual key into any tracked file.** Document the env var name only. The project's existing secrets manager owns the value.

### 4. Document API Surface in 01-architecture.md

For each provider integrated, write a short section answering:

- How does a customer message arrive in `<provider>`? (Email forwarding? Widget? Webhook from app?)
- How does a reply leave? (Provider UI? Email-via-provider? API?)
- Are there custom fields (priority tier, plan, etc.) we should set/read?
- Are there macros / saved replies the team uses? Document them so the agent uses the same wording.
- What labels / tags are convention?

### 5. Build A Generic Adapter Snippet

```bash
# Example: Zendesk list-open-tickets
list_zendesk_open() {
  local subdomain="$ZENDESK_SUBDOMAIN" email="$ZENDESK_EMAIL" token="$ZENDESK_API_TOKEN"
  curl -s -u "${email}/token:${token}" \
    "https://${subdomain}.zendesk.com/api/v2/search.json?query=type:ticket+status<solved" \
    | python3 -m json.tool
}

# Example: Intercom list-open-conversations
list_intercom_open() {
  curl -s -H "Authorization: Bearer $INTERCOM_ACCESS_TOKEN" \
       -H "Intercom-Version: 2.11" \
       "https://api.intercom.io/conversations?per_page=50&display_as=plaintext" \
    | python3 -m json.tool
}
```

The onboarding pass writes or edits the right adapter at `<project>/.claude/support-triage/scripts/list-open.sh`. Future sessions just call that. The scaffold leaves a placeholder that exits safely until the adapter is implemented.

## Reply Mechanics

Sending a reply through a third-party tool *will* email the customer (or push to chat). Treat every send as irreversible.

- **Always show the draft to the owner before posting.** No exceptions.
- **Use the provider's "internal note" feature for triage notes** the customer should not see.
- **Respect the team's tone of voice.** If they have macros / saved replies, copy their wording style; don't invent a new voice.

## Common Pitfalls

- **Token scope mismatch.** A read-only token can list tickets but POST/PUT will 403 — easy to miss. Test both paths during onboarding.
- **Pagination.** Zendesk and Intercom paginate aggressively; "list open" without paging only sees the first 50–100. Always loop.
- **Closed conversations get reopened on reply.** That's usually fine, but tell the owner so they're not surprised.
- **Provider rate limits are tight.** Zendesk: 700 req/min on most plans; Intercom: 83/sec. Don't bulk-update without owner approval.
- **Webhook auth.** If the project receives webhooks from the provider (e.g., Zendesk → app), verify the HMAC signature is being checked, not just trusted.

## When To Recommend Migrating Off

If the owner wants more agent-leverage and the third-party tool is a friction point:

- Heavy customization needed → consider switching to `/user-support-ticketing-system-for-saas` for full control
- Cost concerns → custom DB ticketing is much cheaper at scale
- Owner happy with current tool → leave it; integrate well rather than replace
