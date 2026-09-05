# API-SECURITY-COMMAND-WHITELIST.md — Defense-in-Depth for Experiment Execution

<!-- TOC: Why command whitelisting | The whitelist | Path injection prevention | Timing-safe secret comparison | Information hiding (404 not 403) | Per-environment hardening | The pen-test checklist | Anti-patterns | Cross-references -->

Brennerbot's `/api/experiments` endpoint executes shell commands. Without strict input validation, this is a remote-code-execution surface — an attacker who reaches the endpoint can run arbitrary code as the brennerbot process.

Brennerbot defends with a **strict command whitelist + path-injection prevention + timing-safe HMAC + 404-not-403 information hiding**. This file specifies each defense and how they compose.

Mined from `/dp/brenner_bot/README.md § API Security Architecture` and `CHANGELOG.md` v0.3.0.

---

## Why command whitelisting

Three failures of permissive command execution:

1. **Arbitrary code execution** — `command: "rm -rf /"` runs as brennerbot
2. **Path injection** — `command: "./malicious.sh"` bypasses naive whitelist
3. **Privilege escalation** — chained commands leverage system tools to escalate

Three benefits of strict whitelisting:

1. **Bounded attack surface** — only known-safe commands accepted
2. **Path-rejection** — `/` or `\` in command name → rejected
3. **Defense-in-depth** — even with auth bypass, command list limits damage

---

## The whitelist

Per `/dp/brenner_bot/README.md § Experiments API Command Whitelist`:

```typescript
const ALLOWED_COMMANDS = new Set([
  // Package managers / runners
  "bun", "bunx", "npm", "npx", "yarn", "pnpm", "node", "deno",

  // Python
  "python", "python3", "pip", "pip3", "poetry", "uv",

  // Testing frameworks
  "pytest", "vitest", "jest", "mocha",

  // Build tools
  "make", "cargo", "go", "rustc",

  // Version control
  "git",

  // Shell (requires lab mode auth)
  "bash", "sh",

  // Safe utilities
  "echo", "cat", "ls", "pwd", "which", "env", "printenv",
  "date", "wc", "head", "tail", "grep", "find", "diff", "sort", "uniq",
]);
```

The list is:
- **Deliberate** — each command is curated for legitimate experiment workflows
- **Bounded** — no `eval`, `system`, `exec`, `kill`, `rm`, `chmod`, `sudo`
- **Auth-gated** — `bash`/`sh` require lab mode auth (per LAB-MODE-AUTHORIZATION.md)

Adding new commands requires a security review (per `/dp/brenner_bot/AGENTS.md` security-review process).

---

## Path injection prevention

A naive whitelist check (`is "rm" allowed?`) can be bypassed:

```bash
# Naive whitelist sees "ls"; allows
command: "./malicious"

# Naive whitelist sees "git"; allows
command: "/path/to/evil"
```

The brennerbot defense: **commands containing `/` or `\` are rejected** before whitelist check:

```typescript
function isCommandSafe(command: string): boolean {
  // Path injection check
  if (command.includes("/") || command.includes("\\")) {
    return false;  // reject before whitelist
  }
  // Whitelist check
  return ALLOWED_COMMANDS.has(command);
}
```

This means:
- `bash` is allowed (in whitelist; no path)
- `bash -c "..."` is allowed (only the first token is checked)
- `./bash` is rejected (path injection)
- `/bin/bash` is rejected (path injection)
- `\\bash` is rejected (path injection on Windows)

The `PATH` environment variable handles command resolution; the user can't bypass with explicit paths.

---

## Timing-safe secret comparison

Per LAB-MODE-AUTHORIZATION.md, secret comparison must be timing-safe to prevent byte-by-byte extraction.

The brennerbot implementation uses **HMAC normalization** before comparison:

```typescript
function safeEquals(a: string, b: string): boolean {
  // HMAC normalizes both inputs to fixed-length buffers,
  // eliminating timing leaks from length differences
  const hmacKey = "brenner-auth-compare";
  const hmacA = createHmac("sha256", hmacKey).update(a).digest();
  const hmacB = createHmac("sha256", hmacKey).update(b).digest();
  return timingSafeEqual(hmacA, hmacB);
}
```

Why HMAC normalization?

- **Length-independent** — both inputs hash to fixed 32-byte SHA-256
- **Constant-time comparison** — `timingSafeEqual` doesn't short-circuit
- **Hash-collision irrelevant** — the operator's secret is the input; collisions don't bypass auth

The HMAC key (`"brenner-auth-compare"`) is **public** — security comes from the secret comparison, not the HMAC key. The key prevents accidental hash-collision-based timing differences.

---

## Information hiding (404 not 403)

Per LAB-MODE-AUTHORIZATION.md and `/dp/brenner_bot/README.md`:

> Failed authentication returns HTTP 404 (not 401/403) to prevent endpoint enumeration

Why?

- **401**: tells attacker "endpoint exists; you need auth"
- **403**: tells attacker "endpoint exists; you have insufficient permissions"
- **404**: tells attacker "no such endpoint"

For unauthenticated brennerbot.org visitors, every protected endpoint returns 404. The orchestration features genuinely don't exist for them — for an authorized user, they would.

This is **information hiding**: surface area visible to attackers shrinks.

In practice:

```
GET /sessions/new (with no auth)
→ HTTP/1.1 404 Not Found
→ Content-Type: text/html
→ <body>Page not found</body>

GET /sessions/new (with valid auth)
→ HTTP/1.1 200 OK
→ <session orchestration form>
```

Same URL; different responses; attacker can't tell from the 404 whether the endpoint exists.

---

## Server-side analytics rate limiting

Per `/dp/brenner_bot/README.md § Server-Side Analytics`:

```typescript
// Rate limit configuration
const RATE_LIMIT_WINDOW_MS = 60 * 1000;  // 1 minute window
const RATE_LIMIT_MAX_REQUESTS = 60;       // 60 requests per window
const MAX_MAP_SIZE = 10000;               // max tracked IPs
```

Rate limiting prevents:
- **Brute-force secret extraction** — even with timing-safe comparison, throttling caps attempts
- **DoS via repeated POST** — rate limit per IP

**Critical**: rate limiting uses `X-Real-IP` (set by Vercel edge, not spoofable by clients), not `X-Forwarded-For` (which can be manipulated). Per CHANGELOG.md v0.3.0:

> Rate-limited server-side analytics (60 req/min per IP) to bypass ad blockers while preventing abuse

The pattern:
- **Server-side analytics** for reliability (bypasses ad-blockers)
- **Rate-limited** for safety
- **Spoof-resistant** via `X-Real-IP`

---

## Payload validation

Per `/dp/brenner_bot/README.md`:

| Measure | Implementation |
|---------|----------------|
| Payload size | Max 32KB |
| Events per request | Max 10 |
| Parameter count | Max 25 per event |
| String truncation | Max 100 chars |
| Prototype pollution | Blocked (`__proto__`, `constructor`, `prototype`) |

Each measure prevents a specific attack vector:
- **Size** — DoS via large payloads
- **Event count** — amplification attacks
- **Parameter count** — schema-pollution
- **String truncation** — injection vectors via long strings
- **Prototype pollution** — JavaScript object-prototype attacks

---

## Per-environment hardening

| Environment | Required defenses |
|-------------|---------------------|
| Local dev | Lab mode + shared secret + timing-safe comparison |
| Internal staging | + Cloudflare Access + rate limiting |
| Production | + monitoring + audit logs + rate limiting + WAF |
| Public brennerbot.org | NO orchestration; demo mode only |

Per DESIGN-PRINCIPLES-CLI-FIRST.md Principle 3 (Fail-Closed Security): each environment requires *more* defenses, never fewer.

---

## The pen-test checklist

Before exposing brennerbot to a non-trusted network:

- [ ] `BRENNER_LAB_MODE` only set when needed
- [ ] Auth method configured (Cloudflare Access XOR shared secret)
- [ ] Timing-safe comparison verified (no naive `==`)
- [ ] Path-injection check verified (`/` and `\` rejected)
- [ ] All auth failures return 404 (not 401/403)
- [ ] Rate limiting on `/sessions/new` and `/api/experiments`
- [ ] No path-injection in command-whitelist
- [ ] No secret in source-control
- [ ] Secret rotation procedure documented
- [ ] Demo mode auto-detects public host
- [ ] WAF / monitoring deployed
- [ ] Audit logs reviewed weekly
- [ ] Penetration test by third party (T4+ stakes)

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Allow arbitrary commands "for flexibility" | Whitelist exists for a reason |
| Skip path-injection check | `./bash` bypasses whitelist |
| Use `==` for secret comparison | Timing side-channel |
| Return 401/403 for protected endpoints | Information leakage |
| Trust `X-Forwarded-For` for rate limiting | Client-spoofable |
| Skip rate limiting "for performance" | DoS / brute-force vectors |
| Hardcode HMAC key in env | Key is public; secret is input |
| Skip payload validation | Size/count/string limits prevent attacks |
| Add `eval`/`exec` to whitelist | RCE; defeats whitelist purpose |
| Bypass auth for "internal" endpoints | All endpoints behind auth (per fail-closed) |

---

## Composition with brennerbot

API security integrates with:

- **DESIGN-PRINCIPLES-CLI-FIRST.md** Principle 3 (Fail-Closed Security): the architectural foundation
- **LAB-MODE-AUTHORIZATION.md**: 4-layer auth pattern
- **EXPERIMENT-CAPTURE-AND-RESULT-ENCODING.md**: command execution surface
- **OPERATOR-INTERVENTION-RECORDING.md**: high-severity interventions logged
- **BRENNERBOT-AT-SCALE.md**: production deployment patterns

---

## Cross-references

- [LAB-MODE-AUTHORIZATION.md](LAB-MODE-AUTHORIZATION.md) — 4-layer auth
- [DESIGN-PRINCIPLES-CLI-FIRST.md](DESIGN-PRINCIPLES-CLI-FIRST.md) — fail-closed principle
- [EXPERIMENT-CAPTURE-AND-RESULT-ENCODING.md](EXPERIMENT-CAPTURE-AND-RESULT-ENCODING.md) — command execution context
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — production hardening
- [OPERATOR-INTERVENTION-RECORDING.md](OPERATOR-INTERVENTION-RECORDING.md) — audit trail
- /dp/brenner_bot/README.md § API Security Architecture — original source
- /dp/brenner_bot/CHANGELOG.md v0.3.0 § Security — implementation milestone
