# Mattermost Licensing Guide

> Edition comparison, pricing, and the licensing-as-design-decision argument.
> Updated for Mattermost 10.x (2025-2026).

---

## Edition Overview

Mattermost ships three editions. The open-source core is the same binary -- features are
unlocked by license key. You can start on Team Edition and upgrade in place.

| Edition | Target | Price | License |
|---------|--------|-------|---------|
| Team Edition | <250 users, hobbyists, personal use | Free | MIT (open source) |
| Enterprise E10 (Professional) | Mid-size orgs needing SSO/compliance | ~$10/user/year | Commercial |
| Enterprise E20 (Enterprise) | Large orgs, HA, advanced security | Contact sales (~$8-12/user/year at scale) | Commercial |

Note: Mattermost has rebranded E10 as "Professional" and E20 as "Enterprise" in their marketing,
but the E10/E20 designations are still used in documentation and config flags.

---

## Feature Comparison

| Feature | Team (Free) | Professional (E10) | Enterprise (E20) |
|---------|-------------|---------------------|-------------------|
| Unlimited message history | Yes | Yes | Yes |
| Unlimited teams & channels | Yes | Yes | Yes |
| File sharing & search | Yes | Yes | Yes |
| Integrations (webhooks, slash commands) | Yes | Yes | Yes |
| Plugins (Jira, GitHub, etc.) | Yes | Yes | Yes |
| Mobile & desktop apps | Yes | Yes | Yes |
| Guest accounts | No | Yes | Yes |
| AD/LDAP authentication | No | Yes | Yes |
| SAML 2.0 SSO (Okta, OneLogin, ADFS) | No | Yes | Yes |
| MFA enforcement | Basic TOTP | Full (TOTP + enforcement policies) | Full |
| Advanced permissions & roles | No | Yes | Yes |
| Read-only channels | No | Yes | Yes |
| Channel moderation | No | Yes | Yes |
| Compliance export (CSV, Actiance, GlobalRelay) | No | No | Yes |
| Custom data retention policies | No | No | Yes |
| High Availability (multi-node) | No | No | Yes |
| Horizontal scaling | No | No | Yes |
| Elasticsearch (dedicated search) | No | No | Yes |
| Custom terms of service | No | No | Yes |
| ID-only push notifications | No | No | Yes |
| Advanced audit log | No | No | Yes |
| Dedicated RTCD server for Calls | Community plugin | Community plugin | Official support |

---

## When to Choose Each

### Team Edition (Free)

Use when:
- Under 250 users (Mattermost positions this as the intended audience)
- Personal / homelab / family chat server
- Open-source project communication
- Evaluating Mattermost before committing to a license
- Budget is zero and SSO is not required

Limitations that matter in practice:
- No SAML/LDAP -- every user manages their own password
- No compliance exports -- if legal/audit needs arise, you are stuck
- No HA -- single-node only, planned downtime for upgrades
- No guest accounts -- external collaborators get full member access or nothing

### Professional (E10)

Use when:
- Organization has an existing identity provider (Okta, Azure AD, Google Workspace SAML)
- You need guest accounts for external contractors/partners
- Compliance requirements exist but do not mandate data retention policies
- 250-2000 users on a single node

This is the sweet spot for most companies migrating from Slack. SSO alone justifies
the cost -- managing passwords for 1000 users without it is an operational nightmare.

### Enterprise (E20)

Use when:
- You need HA (zero-downtime deployments, multi-node)
- Compliance requires custom data retention (auto-delete messages after N days)
- Regulated industry (finance, healthcare) with audit log requirements
- 2000+ concurrent users (requires horizontal scaling)
- You need Elasticsearch for search across millions of messages

---

## Pricing Estimates

Mattermost does not publish fixed prices for Enterprise tiers. These are estimates
based on publicly available information and typical negotiation outcomes:

| Users | Professional (E10) | Enterprise (E20) |
|-------|---------------------|-------------------|
| 100 | ~$1,000/year ($10/user) | ~$1,500/year ($15/user) |
| 500 | ~$4,500/year ($9/user) | ~$6,000/year ($12/user) |
| 1,000 | ~$8,000/year ($8/user) | ~$10,000/year ($10/user) |
| 5,000 | ~$35,000/year ($7/user) | ~$40,000/year ($8/user) |

Volume discounts apply. Multi-year commitments reduce cost further.
Academic and non-profit discounts are available (typically 50% off).

**Free trial:** Mattermost offers a 30-day Enterprise trial directly from the System Console.
No sales call required. Use this to evaluate HA and compliance features before purchasing.

```
System Console → Edition and License → Start Trial
```

---

## Licensing as a Design Decision

For any organization with 1000+ users, treat the license tier as an architectural input,
not an afterthought. The license determines:

1. **Whether HA is possible.** If your uptime SLA requires >99.9%, you need E20.
   There is no workaround -- HA is a license-gated feature.

2. **Whether you can use Elasticsearch.** Full-text search on Team/E10 uses the database
   (PostgreSQL `ILIKE` queries). This works for <500K messages. Beyond that, search
   performance degrades and Elasticsearch (E20 only) becomes necessary.

3. **Whether SSO is available.** If your org uses Okta/Azure AD, deploying on Team Edition
   means every user creates a separate password. This is a security regression from Slack
   (which likely already uses SSO). Budget for E10 minimum.

4. **Whether data retention is automated.** Without E20, old messages persist forever.
   For GDPR compliance or storage management, manual deletion is the only option.

**The recommendation for a 1000-user Slack migration:**

Start with Professional (E10) as the baseline. This gives you SSO and guest accounts.
Budget for Enterprise (E20) if any of these apply:
- Uptime SLA requires HA
- Industry compliance requires retention policies or audit logs
- Expected message volume will exceed 1M messages within 2 years
- You need Elasticsearch for search quality

Apply for the 30-day E20 trial during migration to test HA and compliance features.
Make the purchasing decision before cutover, not after.

---

## License Installation

```bash
# Via System Console (web UI)
# System Console → Edition and License → Upload License

# Via mmctl (CLI)
mmctl license upload /path/to/license.mattermost-license

# Via config.json (rarely used)
# Not recommended -- use System Console or mmctl

# Verify license
mmctl license info
```

After uploading a license, Mattermost restarts automatically.
All E10/E20 features become available immediately -- no data migration required.

---

## Downgrade Path

If you decide to stop paying for Enterprise:
- Mattermost continues to function on Team Edition
- Enterprise features (HA, compliance, SAML) stop working
- Data is preserved -- nothing is deleted
- Users who authenticated via SAML will need to set passwords
- If you were running HA, you must designate a single node

This makes the upgrade low-risk: you can always go back to free.
