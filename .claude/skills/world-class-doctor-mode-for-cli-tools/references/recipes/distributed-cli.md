# Recipe — Distributed CLI (Vendor-API Client)

Shape: the CLI is a thin client over a remote service (Cloudflare, Vercel, GitHub, GCP, AWS, OpenAI). State lives both locally (config + auth tokens + cache) and remotely. "Healthy" means *both* are correct AND in sync.

Examples: `wrangler`, `vercel`, `gh`, `gcloud`, `aws`, `supabase` (CLI), `stripe-cli`, `mcp-agent-mail-cli`.

---

## The two-realm model

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│  LOCAL REALM                │         │  VENDOR REALM (remote)      │
│                             │         │                             │
│  ~/.config/<tool>/config    │         │  account.example.com        │
│  ~/.config/<tool>/credentials │  ←sync→ │  - subscription state     │
│  ~/.cache/<tool>/manifest   │         │  - rate-limit budget        │
│  .<tool>/local-manifest     │         │  - resource list            │
└─────────────────────────────┘         └─────────────────────────────┘
                  ▲                                       ▲
                  │                                       │
                  └────────── doctor ───────────┬────────┘
                                                │
                  Default: offline (local realm only)
                  --online: probes vendor realm
```

The doctor splits failures by realm:

- **local-realm-only** failures: config malformed, credential file mode wrong, cache stale.
- **vendor-realm-only** failures: token expired, account suspended, rate-limit exhausted.
- **drift** failures: local cache disagrees with vendor reality (often the messiest class).

---

## Failure-mode classes specific to distributed CLIs

### `auth_state` subsystem

```
fm-auth-state-token-expired-locally
  detector (offline): parse JWT exp; if past, P0.
  fixer: refuse — manual remediation: `<tool> auth login`.

fm-auth-state-token-revoked-server-side
  detector (online-only): probe `<vendor>/whoami`; on 401, P0.
  online_required: true
  fixer: refuse — manual remediation.

fm-auth-state-credentials-too-permissive
  detector: stat ~/.config/<tool>/credentials; if mode & 0o077 != 0, P1.
  fixer: chmod 0600 via mutate() with Op::Chmod.

fm-auth-state-multi-account-conflict
  detector: scan ~/.config/<tool>/{credentials,credentials.<account>};
            if multiple credentials match the same vendor and the user
            hasn't explicitly chosen one, P1.
  fixer: refuse — manual remediation: `<tool> auth select --default <account>`.
```

### `vendor_drift` subsystem

```
fm-vendor-drift-cached-resource-list-stale
  detector (online-only): fetch vendor resource list; diff against cached
                          .<tool>/local-manifest.
  online_required: true
  fixer: rewrite local-manifest from vendor truth via mutate().

fm-vendor-drift-deleted-remote-resource
  detector (online-only): a resource referenced in our local config
                          (e.g., `wrangler.toml::route="..."`) doesn't
                          exist remotely.
  fixer: refuse — could be a deliberate delete the user is undoing or a
                  mistake the user wants to keep. Manual remediation.

fm-vendor-drift-region-mismatch
  detector: local config says region=us-east-1; vendor account is on
            region=eu-west-1. P0 (writes will succeed but reads will
            return empty).
  online_required: true
  fixer: refuse — manual remediation; user must reconcile intent.
```

### `rate_limits` subsystem

```
fm-rate-limits-budget-exhausted
  detector (online-only): query vendor's rate-limit endpoint; if remaining
                          < 5%, P2.
  online_required: true
  fixer: detect-only — wait for window reset.
  remediation: include `reset_at` timestamp in the finding's evidence.

fm-rate-limits-burn-rate-too-high
  detector (online-only): historical rate; if current burn rate would
                          exhaust budget before window end, P2.
  online_required: true
  fixer: detect-only.
```

---

## `--online` semantics, expanded

The `--online` flag has three observable effects:

1. **Network detectors run.** Without `--online`, they're skipped and emit a single `findings_only_offline` aggregate finding listing what wasn't checked.
2. **Online fixers may run.** Most fixers are local-realm; the online ones are typically refusals with `manual_remediation`. A rare exception: a fixer that cancels a runaway resource costs money to leave running — that fixer DOES execute online (with `--yes` confirmation).
3. **Vendor-side records the action.** The agent's audit trail spans realms.

When `--online` is set but the network is unavailable mid-run, individual online detectors degrade gracefully: each emits its own `findings_only_offline` finding rather than wedging the doctor.

---

## Surface additions

```text
<tool> doctor auth-status [--online]
    Local + (with --online) vendor auth check.

<tool> doctor vendor-sync [--online --fix]
    Pull vendor truth and rewrite local-manifest.

<tool> doctor rate-limit-budget --online
    One-shot check; exits 0 if green, 2 if yellow, 4 if red.

<tool> doctor watch-vendor [--online]
    NDJSON stream of vendor health. Long-running; ctrl-C to stop.
```

`<tool> doctor capabilities --json::vendor_apis` lists the vendor endpoints the doctor MAY contact under `--online`:

```jsonc
{
  "vendor_apis": [
    {"name": "cloudflare", "endpoint": "api.cloudflare.com", "purposes": ["auth_check", "resource_list"]},
    {"name": "github", "endpoint": "api.github.com", "purposes": ["rate_limit_check"]}
  ]
}
```

This is the *trust manifest* — agents can confirm the doctor only contacts documented endpoints.

---

## Common pitfalls

- **Implicit network in offline mode.** A detector calls `fetch(...)` without checking `args.online`. The Phase-1 archaeologist's checklist must flag every network call. Use a stubbed network module that panics under offline + `--online=false`.
- **Vendor 5xx wedging the doctor.** Always wrap online detectors in a 10s timeout. On timeout, emit `findings_only_offline`.
- **DNS leaking via reverse-proxied IPs.** If the user's environment routes `api.cloudflare.com` through a corporate proxy, the doctor should respect `HTTPS_PROXY`. Document in capabilities.
- **Storing fresh tokens in `report.json`.** Never include credentials in any artifact. The doctor's `mutate()` chokepoint validates that backups and report.json don't capture credential bytes (regex check on common token patterns; if matched, the report is sanitized to `<redacted-credential-N-bytes>`).
- **Online-fixer that makes the situation worse.** Refusing is almost always correct for vendor-side state changes — they're the user's intent territory. The doctor's role is to *describe* with structured remediation, not to act.

---

## Combining with other patterns

Distributed CLIs are often also installer-bootstrap (Pattern 11) and AI-agent (Pattern 7). The pattern stacks: a CLI like `caam` is Pattern 2 (multi-binary), Pattern 5 (installer), Pattern 7 (AI-agent), and Pattern 9 (distributed). Apply the per-pattern adjustments additively.
