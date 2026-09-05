# LAB-MODE-AUTHORIZATION.md — Defense-in-Depth for Orchestration Features

<!-- TOC: Why fail-closed | The 4 security layers | Environment variables | Authentication methods | Information hiding (404 not 401) | Timing-safe comparison | When to enable | Per-environment configuration | Anti-patterns | Cross-references -->

Brennerbot can dispatch agents, mutate artifacts, and coordinate across panes. In production deployments, this orchestration capability must NOT be accessible without explicit authentication. The lab mode authorization implements **defense-in-depth** — multiple security layers, each redundant, all fail-closed by default.

This file specifies the layers, the environment variables, the authentication methods, and the information-hiding pattern.

Mined from `/dp/brenner_bot/README.md § Lab Mode Authorization` and `/dp/brenner_bot/CHANGELOG.md` v0.3.0 § Security.

---

## Why fail-closed

Three failures of fail-open or single-layer security:

1. **Misconfigured deployments leak orchestration** — public endpoint accidentally enables session-create
2. **Single layer = single point of failure** — auth bypass = full compromise
3. **Information leakage via 401 Unauthorized** — attackers learn that endpoint exists; surface area mapped

Three benefits of multi-layer fail-closed:

1. **Default-off** — features unavailable until explicit opt-in
2. **Multiple layers must align** — env var + auth + secret = three barriers
3. **404 hides existence** — failed auth returns 404, not 401; attackers see "no such endpoint"

---

## The 4 security layers

```
1. ENVIRONMENT GATE
   ↓ pass: BRENNER_LAB_MODE=1
   ↓ fail: 404 (lab mode not enabled)

2. AUTHENTICATION
   ↓ pass: Cloudflare Access JWT OR shared secret
   ↓ fail: 404

3. TIMING-SAFE COMPARISON
   ↓ pass: secret matches in constant time
   ↓ fail: 404

4. INFORMATION HIDING
   All failures return 404 (not 401/403)
```

Each layer is checked independently. A request must pass *all four* to reach orchestration.

---

## Environment variables

Per `/dp/brenner_bot/README.md`:

| Variable | Purpose | Required for prod |
|----------|---------|---------------------|
| `BRENNER_LAB_MODE` | Enable lab mode (`1` or `true`) | ✓ |
| `BRENNER_LAB_SECRET` | Shared secret for local auth | (one of two) |
| `BRENNER_TRUST_CF_ACCESS_HEADERS` | Trust Cloudflare Access JWT headers | (one of two) |
| `BRENNER_PROJECT_KEY` | Default project key for Agent Mail (absolute path) | recommended |
| `BRENNER_AGENT_NAME` | Default agent name for session pages | recommended |
| `BRENNER_PUBLIC_BASE_URL` | Public base URL for fetching corpus/assets | optional |

**Critical:** `BRENNER_LAB_MODE=1` is the **first gate**. Without it, all orchestration endpoints return 404 regardless of authentication. This prevents accidental exposure on misconfigured deployments.

---

## Authentication methods

Two methods are supported; **one** must be configured:

### Method 1: Cloudflare Access (recommended for production)

Deploy behind Cloudflare Access. Set:

```bash
BRENNER_LAB_MODE=1
BRENNER_TRUST_CF_ACCESS_HEADERS=1
```

Cloudflare validates the user via Cloudflare Access (SSO, etc.); the JWT headers (`Cf-Access-Authenticated-User-Email`, `Cf-Access-Jwt-Assertion`) are forwarded to brennerbot. The brennerbot server trusts these headers (because `BRENNER_TRUST_CF_ACCESS_HEADERS=1` was explicitly set).

**Why "explicitly set"?** Without the explicit env var, brennerbot does NOT trust the headers — even if they're present. This prevents header-injection attacks where someone sends fake CF-Access headers to a brennerbot not behind Cloudflare.

### Method 2: Shared secret (for local development)

Set:

```bash
BRENNER_LAB_MODE=1
BRENNER_LAB_SECRET=<your-secret-here>
```

Pass the secret via either:
- HTTP header: `X-Brenner-Lab-Secret: <your-secret-here>`
- Cookie: `brenner_lab_secret=<your-secret-here>`

The server compares using **timing-safe comparison** (HMAC-based; constant time). Per `/dp/brenner_bot/CHANGELOG.md` v0.3.0:

> Defense-in-depth authentication with HMAC-based timing-safe secret comparison

Why timing-safe? Naive `string == string` comparison can leak information via timing side-channel — early-byte mismatch returns faster than late-byte mismatch, allowing an attacker to extract the secret one byte at a time. Timing-safe comparison takes the same wall-time regardless of where the mismatch is.

---

## Information hiding (404 not 401)

When auth fails, brennerbot returns **404 Not Found**, not 401 Unauthorized:

```
GET /sessions/new
→ HTTP/1.1 404 Not Found
→ Content-Type: text/html
→ <body>Page not found</body>
```

Why?

- **401** tells the attacker: "this endpoint exists; you need to authenticate"
- **404** tells the attacker: "no such endpoint"

For a public-facing brennerbot (e.g., demo mode at brennerbot.org for unauthenticated users), 404 is the correct response — the orchestration features genuinely don't exist for that user. They might exist for an authorized user, but the attacker can't tell.

This is **information hiding**: the surface area visible to attackers shrinks.

---

## Timing-safe comparison

```typescript
function timingSafeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}
```

The function:
- Always iterates the full length (no early exit)
- Uses XOR + OR to accumulate; constant time per character
- Returns at the end with the result

Per `/dp/brenner_bot/CHANGELOG.md`: this prevents byte-by-byte secret extraction via timing analysis.

---

## When to enable

Lab mode should be enabled:

- **Local dev**: `BRENNER_LAB_MODE=1` + `BRENNER_LAB_SECRET=<dev-secret>` (shared secret method)
- **Internal staging**: lab mode + Cloudflare Access (CF-Access method)
- **Production**: lab mode + Cloudflare Access + monitoring + rate-limiting (per `/dp/brenner_bot/CHANGELOG.md` v0.3.0)

Lab mode should **never** be enabled:

- **Public brennerbot.org**: demo mode only; no orchestration; per `/dp/brenner_bot/CHANGELOG.md` v0.3.0 § Demo Mode
- **Public CI**: orchestration in CI is fine via direct CLI; web app should remain disabled
- **Untrusted deployments**: until you can guarantee auth + monitoring, keep it off

Per DESIGN-PRINCIPLES-CLI-FIRST.md Principle 3 (Fail-Closed Security): default-off; explicit opt-in.

---

## Per-environment configuration

### Local development

```bash
# .env.local
BRENNER_LAB_MODE=1
BRENNER_LAB_SECRET=dev-secret-only-for-local-dev
BRENNER_PROJECT_KEY=/path/to/local/repo
BRENNER_AGENT_NAME=YourLocalAgent
```

### Internal staging (with Cloudflare Access)

```bash
BRENNER_LAB_MODE=1
BRENNER_TRUST_CF_ACCESS_HEADERS=1
BRENNER_PROJECT_KEY=/data/projects/staging
BRENNER_PUBLIC_BASE_URL=https://staging.example.com
# (NO secret env var; CF Access handles auth)
```

### Production

```bash
BRENNER_LAB_MODE=1
BRENNER_TRUST_CF_ACCESS_HEADERS=1
BRENNER_PROJECT_KEY=/data/projects/production
BRENNER_PUBLIC_BASE_URL=https://brennerbot.example.com
# Plus rate-limiting middleware + monitoring
```

### Public brennerbot.org (demo mode)

```bash
# Lab mode NOT set; orchestration unavailable
# Demo mode auto-detects public host (per CHANGELOG.md v0.3.0)
BRENNER_PUBLIC_BASE_URL=https://brennerbot.org
```

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Set `BRENNER_LAB_MODE=1` in public production without auth | Orchestration exposed |
| Trust CF-Access headers without `BRENNER_TRUST_CF_ACCESS_HEADERS=1` | Header-injection attack possible |
| Use `==` for secret comparison | Timing side-channel; secret extractable |
| Return 401 instead of 404 for auth failure | Information leakage; surface area mapped |
| Hardcode secret in config | Use env vars; rotate without redeployment |
| Skip rate-limiting on lab mode endpoints | Brute-force secret extraction; per CHANGELOG.md v0.3.0 |
| Default `BRENNER_LAB_SECRET` | If unset and env-mode is on: refuse to start |
| Mix Cloudflare and secret methods (both enabled) | Either + secret means lower-bar wins; pick one |
| Skip path-injection checks (per CHANGELOG.md v0.3.0) | Command-whitelist bypass |

---

## Composition with brennerbot

Lab mode authorization integrates with:

- **DESIGN-PRINCIPLES-CLI-FIRST.md** Principle 3 (Fail-Closed Security): the architectural principle this implements
- **OPERATOR-INTERVENTION-RECORDING.md**: human-operator interventions logged per session
- **BRENNERBOT-AT-SCALE.md**: production rollout patterns
- **DEPLOYMENT-RUNBOOK** (per /dp/brenner_bot/specs/deployment_runbook_v0.1.md): step-by-step deployment

---

## Pen-testing checklist

Before exposing brennerbot to any non-trusted network:

- [ ] `BRENNER_LAB_MODE` only set when needed
- [ ] One auth method configured (CF-Access XOR shared secret)
- [ ] Timing-safe comparison verified (no naive `==`)
- [ ] All auth failures return 404 (not 401/403)
- [ ] Rate-limiting on `/sessions/new` and other orchestration endpoints
- [ ] No path-injection in command-whitelist
- [ ] No secret in source-control
- [ ] Secret rotation procedure documented
- [ ] Demo mode auto-detects public host

---

## Cross-references

- [DESIGN-PRINCIPLES-CLI-FIRST.md](DESIGN-PRINCIPLES-CLI-FIRST.md) — fail-closed security principle
- [OPERATOR-INTERVENTION-RECORDING.md](OPERATOR-INTERVENTION-RECORDING.md) — audit trail of authorized actions
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — production deployment patterns
- [BRENNERBOT-DOCTOR-RUBRIC.md](BRENNERBOT-DOCTOR-RUBRIC.md) — Pillar 1 lab-mode check
- /dp/brenner_bot/README.md § Lab Mode Authorization — original source
- /dp/brenner_bot/CHANGELOG.md v0.3.0 § Security — implementation milestone
- /dp/brenner_bot/specs/deployment_runbook_v0.1.md — deployment procedures
