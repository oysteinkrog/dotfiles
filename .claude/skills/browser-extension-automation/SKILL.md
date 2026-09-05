---
name: browser-extension-automation
description: >-
  Bypass bot detection via browser extension. Use when Google blocks Playwright,
  OAuth flows fail, or "browser may not be secure" errors appear.
---

<!-- TOC: Pattern | Quick Start | Instruction Template | Anti-Patterns | Workflow | References -->

# browser-extension-automation — Claude Browser Extension

> **Core Pattern:** Don't automate programmatically → provide *exact* paste-ready instructions for Claude browser extension in real Chrome.

## The Problem

```
Playwright/Puppeteer → Google OAuth → "This browser or app may not be secure" ✗
Claude Extension     → Google OAuth → Works normally ✓
```

**Why:** Bot detection flags WebDriver. Real browsers with AI extensions pass.

## Quick Start

```
1. Research exact steps (URLs, element names, values)
2. Format as paste-ready instructions (see template below)
3. User pastes into Claude browser extension on Mac Mini
4. User reports output (credentials, IDs)
5. Agent updates configs programmatically
```

## Instruction Template

**Copy this structure exactly:**

```markdown
**Step N: [Action Name]**
URL: `https://exact.url.with/all/segments?project=ACTUAL_ID`

1. Click "[Exact Button Text]" button
2. In "[Field Label]" field, enter: `exact value`
3. Select "[Exact Option Text]" from dropdown
4. Click "[Submit Button Text]"

Expected: [What user should see]
Report back: [What to copy/paste back]
```

**Critical rules:**
- Include FULL URLs with query params (`?project=xyz`)
- Use EXACT element text (copy from UI)
- Specify WHAT to report back

## When to Use

| Site | Symptom | This Skill? |
|------|---------|-------------|
| Google Cloud Console | "Browser may not be secure" | Yes |
| Stripe Dashboard | Bot detection, CAPTCHA | Yes |
| OAuth flows | Automation blocked | Yes |
| 2FA/CAPTCHA required | Can't automate | Yes |
| Simple API calls | Works with curl | No - use curl |

## Anti-Patterns

| Don't | Why | Do Instead |
|-------|-----|------------|
| `playwright` over SSH | No display + bot detection | Paste-ready instructions |
| xvfb for OAuth | User can't interact with 2FA | Real browser via extension |
| Vague: "click the button" | Which button? | `Click "Create credentials"` |
| Assume user knows IDs | They don't have context | `project=my-project-123` |
| Skip query params | Wrong page loads | Full URL always |

## Connecting to Mac Mini

```bash
# Find Mac on Tailscale
tailscale status | grep mac

# SSH in
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 <user>@<tailscale-ip>
```

## After User Reports Credentials

```bash
# Supabase
curl -X PATCH -H "Authorization: Bearer $TOKEN" \
  "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -d '{"external_google_client_id": "...", "external_google_secret": "..."}'

# Vault
vault kv patch secret/project KEY="value"

# Vercel
echo "value" | vercel env add VAR_NAME production
```

## Pre-Flight Checklist

- [ ] URLs verified (open in browser, correct page loads)
- [ ] Element names match current UI exactly
- [ ] All identifiers included (project IDs, refs)
- [ ] Clear "report back" instructions
- [ ] Programmatic update commands ready

## References

| Example | File |
|---------|------|
| Google OAuth setup | [GOOGLE-OAUTH.md](references/GOOGLE-OAUTH.md) |
| Stripe webhooks | [STRIPE-WEBHOOKS.md](references/STRIPE-WEBHOOKS.md) |
