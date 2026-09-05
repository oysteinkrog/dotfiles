# Runbook: SECURITY-DISCLOSURE

A user reports a vulnerability via DM, email, GitHub issue, or contact form. **Stakes are extreme.** Mishandle this and you blow the embargo, lose the CVE assignment, anger the researcher, or expose unpatched users.

## Trigger Conditions

- "I found a vulnerability"
- "There's a CVE in your..."
- "Possible XSS / SQL injection / CSRF / SSRF / auth bypass / privilege escalation"
- A vuln-scanner output (Burp / Nuclei / OWASP ZAP) attached
- An open GitHub issue containing security details (redact/move private fast)
- An email to `security@` from a known security-research handle
- A bug-bounty platform notification (HackerOne, Bugcrowd)

## First 60 Minutes (Critical)

1. **STOP all public discussion.** If the report came in publicly, ack publicly with no substance ("we'll respond privately") and move it private. If it's in a GitHub issue with details, preserve the original in a private advisory/internal note, then redact the public body to a neutral placeholder ("Reported privately, see security advisory soon"). Get owner approval for any irreversible platform action.
2. **Acknowledge to the reporter within 24 hours.** Even if you can't fix yet. Use the SECURITY-ACK template below.
3. **Verify reporter identity (lightly).** If they have a public profile and prior disclosures, they're real. If it's a script-output spam, lower priority but still triage.
4. **Capture the report.** Save:
   - Reporter handle + email + (optional) PGP key
   - Original message verbatim
   - Any attachments / PoC code
   - Screenshots
   - Affected versions / endpoints
5. **Assess severity (rough CVSS).** Use the [NIST CVSS calculator](https://nvd.nist.gov/vuln-metrics/cvss/v3-calculator). Most useful: AV (network/local/physical), AC (low/high), PR (none/low/high), UI (none/required), S (unchanged/changed), C/I/A impact.

## Real-vs-Spam Signals

| Signal | Real | Spam |
|---|---|---|
| Has a reproducer / PoC | Almost always | Almost never |
| Cites exact version | Yes | "Your website" |
| Includes proposed CVSS | Often | Rarely |
| Asks for embargo / coordinated disclosure | Yes | No |
| Output looks like raw `nuclei` / `nikto` | Maybe (still triage) | Common |
| References public CVE without testing | Spam-ish | Real CVE researchers test |
| Demands payment up front | Strong spam signal | Real researchers ask after triage |

## Coordinated Disclosure Process

**Standard timeline (Project Zero model):**
- Day 0: receipt + ack within 24h
- Day 1-3: reproduce + assess severity
- Day 4-14: develop fix
- Day 15-89: test, deploy, notify customers if needed
- Day 90: public disclosure + CVE published

If a deadline passes without coordination, the researcher MAY publish unilaterally. Stay in touch and ask for an extension if you genuinely need more time — researchers are usually accommodating.

## CVE Assignment

Two paths:

1. **GitHub Security Advisories** (easiest if your repo is on GitHub):
   - Repo → Security → Advisories → Draft new
   - Fill out details; GitHub reserves a CVE-ID via the GHSA program
   - Publish when ready

2. **MITRE direct request**:
   - https://cveform.mitre.org/
   - Use if your codebase isn't on GitHub or if you want a CVE before code review
   - Slower (days)

3. **Numbering Authority (CNA)** if you're large enough — apply via MITRE.

## security.txt (RFC 9116)

Every SaaS / OSS project should have one at `/.well-known/security.txt`:

```
Contact: mailto:security@<domain>
Contact: https://<domain>/.well-known/security
Expires: 2027-01-01T00:00:00.000Z
Encryption: https://<domain>/.well-known/pgp-key.asc
Preferred-Languages: en
Canonical: https://<domain>/.well-known/security.txt
Policy: https://<domain>/security/policy
Acknowledgments: https://<domain>/security/hall-of-fame
```

If yours is missing, add it during onboarding (it's a 5-minute task and doubles disclosure quality).

## Drafts

### SECURITY-ACK (within 24h, before you've even started reproducing)

```
Thanks for the report. We received it at <timestamp> and are taking it
seriously.

Process: we'll reproduce within 72 hours and respond with our severity
assessment + remediation timeline. We use a coordinated-disclosure
process (90-day embargo standard) — we'll work with you on timing.

If you'd prefer encrypted communication, our PGP key is at <URL>.

Please don't post details publicly until we've coordinated. We'll
acknowledge your contribution publicly when the fix ships (or on a
schedule you prefer).
```

### SECURITY-CONFIRMED (after reproducing)

```
We've reproduced the issue. Our assessment:

Severity: <Critical | High | Medium | Low> (CVSS <score>)
Affected: <versions / endpoints>
Exposure: <what data / capability is at risk>

Our timeline:
- Fix in development now; targeting <date> for deployment
- Notification to affected customers if any: <date>
- Public disclosure: <date> (coordinated with you)

Anything you'd like us to know before we proceed? And — thanks again
for the responsible disclosure.
```

### SECURITY-FIXED

```
Update: the fix shipped on <date> in version <X>. CVE-<ID> has been
assigned. Public advisory at <URL>.

We've credited you in our security hall-of-fame at <URL> (let us know
if you'd prefer to be anonymous).

Genuinely appreciated.
```

### SECURITY-DECLINED (not actually a vuln)

```
Thanks for the report. We looked at it carefully and don't believe it
constitutes a vulnerability. Specifically:

<one-paragraph technical explanation, e.g., "the endpoint requires an
authenticated session and the rate-limit prevents enumeration in
practice">

If you can demonstrate exploitation (e.g., a PoC that works without
the assumed pre-conditions), we'd absolutely re-open. Otherwise, thanks
for the second look.
```

## Handling Common Vuln Classes

| Class | First-pass questions |
|---|---|
| **XSS** | Reflected / stored / DOM? Where? CSP in place? `httpOnly` cookies? |
| **SQL injection** | Parameterized queries everywhere? ORM in use? |
| **CSRF** | SameSite cookies? CSRF tokens on state-changing endpoints? |
| **SSRF** | URL fetcher accept localhost / 169.254.169.254 / file://? |
| **Auth bypass** | JWT verification correct? Token confusion? IDOR? |
| **Subdomain takeover** | Dangling DNS records pointing at provider you don't own? |
| **Open redirect** | Whitelist or open `?redirect=`? |
| **Privilege escalation** | Authorization checks at every endpoint? RLS? |
| **Secrets in client bundle** | API keys / DB connection in JS source? |
| **Account takeover via email** | Email verification on update? |

## After-Action

- Log the incident: severity, time-to-fix, root cause class.
- Add a regression test covering the class.
- If it ships in production, post-mortem with the team (blameless format).
- If many customers were affected, send a coordinated notification.
- Update `06-recurring-issues.md` with the class so future triage spots variants.

## Anti-Patterns

| Don't | Why |
|---|---|
| Reply publicly with substance | Embargo blown; CVE assignment compromised; all unpatched users at risk |
| Refuse to assign a CVE | Bad faith with researchers; they'll publish unilaterally |
| Quibble over severity to lower CVSS | Researchers compare notes; reputation hit |
| Ship the fix without telling customers if data was exposed | Legal exposure (GDPR breach notification 72h) |
| Delete the original report after fix | You need it for the post-mortem and any future CVE refinement |
| Rate-limit / IP-block the researcher | Some have done this; legendarily bad faith |
| Treat the spam-shape report dismissively | One in 50 is real; respond to all (terse template OK for spam) |
