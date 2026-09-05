# Leak Taxonomy

Beyond the basic `signing-*.key` / `*.pem` / `id_rsa` patterns in FILE-SMELLS.md, real secret leaks span many categories. This reference is the comprehensive catalog the leak-scanner subagent uses at Phase 2.5.

---

## Categories

### 1. Asymmetric private keys

| Pattern | Filename rules | Content fingerprint |
|---------|----------------|----------------------|
| RSA private | `id_rsa`, `*.pem` (with private content), `*.key` | First line: `-----BEGIN RSA PRIVATE KEY-----` |
| Ed25519 private | `id_ed25519`, `signing-*.key`, `*.key` (32 or 64 bytes) | 32 bytes raw OR 64 bytes raw, base64-decodable, NOT all-printable-ASCII |
| ECDSA private | `id_ecdsa`, `*.pem` | First line: `-----BEGIN EC PRIVATE KEY-----` |
| DSA private | `id_dsa`, `*.pem` | First line: `-----BEGIN DSA PRIVATE KEY-----` |
| OpenSSH format | `id_*` | First line: `-----BEGIN OPENSSH PRIVATE KEY-----` |
| PKCS#12 | `*.p12`, `*.pfx` | Binary file with magic bytes; password-protected |
| JKS keystore | `*.jks`, `*.keystore` | Java keystore magic bytes |

**Rotation procedure:** generate new key with same algorithm; update consumers (every public-key recipient); revoke old key from authorization systems.

**Blast radius:** anyone with the file can sign on behalf of the original holder. Revocation is non-retroactive (already-signed artifacts may have been forged in the exposure window).

### 2. SSH and OpenSSH

| Pattern | Filename rules | Content |
|---------|----------------|---------|
| SSH private (user) | `id_rsa`, `id_ed25519`, `id_ecdsa`, `id_dsa` | private key contents |
| SSH host key | `ssh_host_*_key` | private host key (typically in `/etc/ssh/`; rarely in repo) |
| Authorized keys (multiplied) | `authorized_keys` | list of allowed public keys; not a secret per se but reveals who has access |

**Rotation:** rotate user keys via `ssh-keygen` + update on all servers. Host keys: re-generate via OpenSSH.

### 3. Cloud credentials

| Pattern | Filename rules | Content fingerprint |
|---------|----------------|----------------------|
| AWS credentials | `~/.aws/credentials`, `aws_credentials*`, `.env` with AWS_ACCESS_KEY_ID | `AKIA[0-9A-Z]{16}` (access key) + `[A-Za-z0-9/+=]{40}` (secret) |
| GCP service account | `*credentials*.json`, `service-account*.json`, `gcp-key*.json` | JSON: `{"type": "service_account", "private_key": "-----BEGIN PRIVATE KEY-----..."}` |
| Azure service principal | `azure-credentials*.json`, `*.azureauth` | JSON with `clientId`, `clientSecret`, `tenantId` |
| Cloudflare API token | `.cloudflare/credentials`, `wrangler.toml` (with token) | `[A-Za-z0-9_-]{40}` (varies) |
| DigitalOcean | `~/.config/doctl/config.yaml` | `dop_v1_<long-string>` |

**Rotation:** revoke from cloud console; generate new; update CI/CD vars.

**Blast radius:** depending on permissions, can access entire cloud account, including production data.

### 4. OAuth / API tokens

| Service | Pattern | Content fingerprint |
|---------|---------|----------------------|
| GitHub Personal Access Token | `.env`, `.npmrc`, anywhere | `ghp_[A-Za-z0-9]{36}` or `github_pat_[A-Za-z0-9_]{80,}` |
| GitHub OAuth app token | similar | `gho_[A-Za-z0-9]{36}` |
| GitHub installation token | similar | `ghs_[A-Za-z0-9]{36}` |
| Slack bot token | `.env`, `slack-config.json` | `xoxb-[0-9]+-[A-Za-z0-9]+` |
| Slack user token | similar | `xoxp-[0-9]+-...` |
| Slack webhook URL | `.env`, anywhere | `https://hooks.slack.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+` |
| Discord bot token | `.env` | base64-decodable; matches `[A-Za-z\d]{24}\.[\w-]{6}\.[\w-]{27}` |
| Stripe live key | `.env`, `stripe-config.json` | `sk_live_[0-9a-zA-Z]{24}` |
| Stripe test key | similar | `sk_test_[0-9a-zA-Z]{24}` |
| Stripe webhook secret | similar | `whsec_[0-9a-zA-Z]{32+}` |
| OpenAI API key | `.env` | `sk-[A-Za-z0-9]{40,}` or `sk-proj-[A-Za-z0-9_-]{40,}` |
| Anthropic API key | `.env` | `sk-ant-[A-Za-z0-9_-]{40,}` |
| Google API key | `.env` | `AIza[0-9A-Za-z_-]{35}` |
| Twilio API | `.env` | `AC[a-z0-9]{32}` (account SID) + `[a-z0-9]{32}` (auth token) |
| SendGrid | `.env` | `SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}` |

**Rotation:** revoke from service's console; generate new; update CI/CD.

**Blast radius:** read/write access to that service's API on behalf of the token holder.

### 5. Database credentials

| Pattern | Filename rules | Content fingerprint |
|---------|----------------|----------------------|
| PostgreSQL connection string | `.env`, `database.yml`, `.pgpass` | `postgres://user:password@host:port/db` (with embedded password) |
| MySQL connection string | `.env`, `database.yml`, `~/.my.cnf` | `mysql://user:password@host:port/db` |
| Redis URL with auth | `.env`, `redis.conf` | `redis://[user:]password@host:port` |
| MongoDB URI with auth | `.env`, `mongodb.conf` | `mongodb://user:password@host:port/db?authSource=admin` |

**Rotation:** generate new password in DB; update consumers; revoke old.

**Blast radius:** read/write access to the database.

### 6. Webhook secrets and signing keys

| Pattern | Filename rules | Content fingerprint |
|---------|----------------|----------------------|
| Stripe webhook secret | `.env` | `whsec_[a-zA-Z0-9]{32,}` |
| GitHub webhook secret | `.env`, `webhook-config.json` | random string (length varies) |
| Slack signing secret | `.env` | `[a-f0-9]{64}` (32-byte hex) |
| HMAC signing key | `.env` | random string, often base64 |

**Rotation:** generate new secret in service config; update receivers.

**Blast radius:** anyone with the secret can forge webhooks (or, conversely, consume webhooks).

### 7. JWT signing keys and OAuth client secrets

| Pattern | Filename rules | Content fingerprint |
|---------|----------------|----------------------|
| JWT signing key (HS256) | `.env`, `jwt-config.json` | random base64 string |
| RSA JWT signing private | `.env`, `*.pem` | RSA private key |
| OAuth2 client secret | `.env`, `oauth-config.json` | random string |
| OAuth2 refresh tokens | rare in repo; caching layer | long random string |

**Rotation:** generate new; update all consumers; existing JWTs become invalid.

### 8. Configuration files with embedded secrets

| Pattern | Filename rules | Content fingerprint |
|---------|----------------|----------------------|
| `.env` | exact filename `.env` (NOT `.env.example`) | KEY=VALUE pairs; values usually non-placeholder |
| `.npmrc` with `_authToken=` | `.npmrc` (not `.npmrc.example`) | `_authToken=[A-Za-z0-9_-]{20,}` |
| `.pypirc` with `password = ` | `.pypirc` | `password = <real-password>` |
| `bashrc/zshrc` with exported tokens | rare in repo | `export *_TOKEN=...` |
| `wrangler.toml` with API token | `wrangler.toml` | `account_id` + token field set |
| `vercel.json` with token | rare | tokens in `env` or `build.env` |

### 9. Encrypted secret files (still surface as suspect)

These are encrypted, so they're "safe" to commit, BUT the skill should still flag them so the user confirms:

| Pattern | What to confirm |
|---------|-----------------|
| `*.gpg`, `*.gpg.encrypted` | Confirm GPG encryption is to a key the team controls |
| `secrets.yaml.enc` (sops format) | Confirm sops policy / KMS key is correct |
| `*.age` (age encryption) | Confirm recipient identity is correct |
| `*.kms` (AWS KMS-encrypted) | Confirm KMS policy is correct |
| Mozilla SOPS files | Look for `sops:` metadata block |

The skill's default verdict for encrypted-but-suspect files is `surface-to-user` with a recommendation: "verify the encryption recipient is still correct."

---

## Detection priority

Phase 2.5 checks in this order:

1. **Filename match** against any filename rule above. If no match → skip to next file.
2. **Content fingerprint** against the matched category's fingerprints.
3. **Both match** → flag as `secret-leak` (real secret) → halt and escalate to `harden-secret-leak`.
4. **Filename match only** (e.g., 0-byte placeholder, `.pub` without `.key`) → flag as `secret-suspect` → surface at Phase 5.
5. **Content match only** (e.g., a `.env` file that wasn't named `.env`) → unusual; flag as `secret-suspect-by-content` → surface at Phase 5.

---

## Per-category rotation procedure

The secret-rotator subagent (or the user, manually) follows the category-specific rotation:

| Category | Rotation steps |
|----------|----------------|
| Asymmetric private key | 1) generate new keypair; 2) distribute new public key to recipients; 3) revoke old public key on key servers / authorization systems; 4) re-sign anything that was signed with the old key (if applicable) |
| SSH key | 1) generate new keypair via `ssh-keygen`; 2) update on all servers (`ssh-copy-id` or directly edit `~/.ssh/authorized_keys`); 3) remove old key from authorized_keys |
| Cloud credentials | 1) revoke from cloud console; 2) generate new; 3) update CI/CD environment variables; 4) audit recent activity for unauthorized actions |
| OAuth / API token | 1) revoke from service console; 2) generate new; 3) update everywhere (CI, deploys, dev machines, .env templates) |
| Database password | 1) `ALTER USER ... WITH PASSWORD ...` to set new; 2) update connection strings everywhere; 3) drop old user if safe |
| Webhook secret | 1) generate new in service config; 2) update receiver code/env; 3) old webhooks signed with old secret will fail signature check (intentionally) |

---

## Force-add bypass detection

When `.gitignore` already contains the leaked filename pattern, the skill records this as `force-add bypass` in `secret_findings.tsv`:

```
path                       smell        rotation_status  force_add_detected  notes
signing-cafef00d.key       ed25519-key  PENDING          true                gitignore had `signing-*.key` rule; user used git add -f
```

The mitigation in INCIDENT-PLAYBOOK Step 7 (install pre-commit hook) is mandatory for force-add cases. It's optional but recommended for non-bypass cases.

---

## Public components are safe

These are SAFE to keep in the repo (don't escalate them):

| Pattern | Why |
|---------|-----|
| `*.pub` (without companion `.key`) | Public key; designed to be shared |
| `*.pem` containing `BEGIN PUBLIC KEY` only | Public key |
| `.env.example`, `.env.template`, `.env.sample` | Templates; values should be placeholders |
| `tests/fixtures/test-key.pem` (clearly a test fixture, all-ASCII content like "test-key-content") | Documented test fixture |
| `manifest.public.json` (Cloudflare Pages routes/headers) | Public configuration |

The leak-scanner verifies these explicitly to suppress false positives.

---

## Quick rotation checklist (for `harden-secret-leak` mode)

When a real secret is found:

- [ ] **Step 0 — Halt and confirm.** Skill surfaces the finding with provenance.
- [ ] **Step 1 — Mirror backup.** `git clone --mirror . /tmp/<repo>-backup-<TS>.git`
- [ ] **Step 2 — Verify origin sync.** `git rev-list --count <branch> == git rev-list --count origin/<branch>`. If not, `git update-ref refs/heads/<branch> refs/remotes/origin/<branch>`.
- [ ] **Step 3 — User rotates the key.** (User-driven; skill cannot do this.) Get new key on all consumers FIRST.
- [ ] **Step 4 — Run filter-repo.** `git filter-repo --invert-paths --path 'path/to/secret' --force`
- [ ] **Step 5 — Verify removal.** `git log --all --oneline -- 'path/to/secret'` should be empty.
- [ ] **Step 6 — Re-add origin and force-with-lease push.** `git push --force-with-lease origin <branch>` AND any synonyms (e.g., `master` if mirror).
- [ ] **Step 7 — Verify origin clean.** `git log origin/<branch> -- 'path/to/secret'` empty.
- [ ] **Step 8 — Broaden `.gitignore`.** Add patterns covering this category (and adjacent categories).
- [ ] **Step 9 — Install `.githooks/pre-commit`.** Smoke-test with a fake key.
- [ ] **Step 10 — Document in AGENTS.md.** Add a note about the new pre-commit guard.
- [ ] **Step 11 — Cross-reference incident.** Beads issue + Agent Mail + handoff report.

INCIDENT-PLAYBOOK.md has the full prose; this is the checklist.

---

## When the secret was committed only locally (never pushed)

Less serious but still requires:
- Rotate the key (treat as compromised because the user's machine may not be the only one with it).
- `git filter-repo` locally + delete the local clone (the only place it ever existed).
- No force-push needed (origin doesn't have it).

The skill detects this via `git log origin/<branch> -- <path>` being empty initially.

---

## When the secret was committed and pushed to a public repo

Maximum severity:
- ASSUME COMPROMISED. Anyone watching public Git activity for the org has potentially seen it.
- Rotation is mandatory and immediate (don't wait for the cleanup to finish).
- Consider notifying security teams (depending on org policy).
- The `harden-secret-leak` flow is only the technical mitigation; the operational mitigation (rotation, audit log review, monitoring) is on the user.
