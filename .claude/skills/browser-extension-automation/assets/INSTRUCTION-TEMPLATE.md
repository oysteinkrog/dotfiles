# [Service Name] Setup - Paste-Ready Instructions

## Before Pasting

Replace these placeholders:
- `PLACEHOLDER_1` → Description (e.g., `example-value`)
- `PLACEHOLDER_2` → Description (e.g., `example-value`)

---

## Instructions to Paste

**Step 1: [First Action]**

URL: `https://exact.url.with/query?params=here`

1. Click "[Exact Button Text]" button
2. In "[Field Label]" field, enter: `PLACEHOLDER_1`
3. Select "[Option Text]" from dropdown
4. Click "[Submit Button]"

Expected: [What user should see after this step]

**Step 2: [Second Action]**

URL: `https://next.page.url`

1. [Action 1]
2. [Action 2]
3. [Action 3]

Report back:
- [What to copy] (format: `example-format`)
- [What else to copy] (format: `example-format`)

---

## After User Reports Values

```bash
# 1. Update .env.local
echo "KEY=value" >> .env.local

# 2. Update Vault
vault kv patch secret/project-name KEY="value"

# 3. Update Vercel
echo "value" | vercel env add KEY production
```

## Verification

```bash
# Command to verify setup worked
curl -s "https://api.example.com/check" | jq '.status'
```
