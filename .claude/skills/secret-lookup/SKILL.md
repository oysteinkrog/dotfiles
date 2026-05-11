---
name: secret-lookup
description: >-
  Retrieve API tokens, keys, and credentials Oystein has stored locally. Use
  whenever code, scripts, or shell commands need a secret value: GitHub tokens,
  Cloudflare, HubSpot, Slack, Zendesk, Jira, Sentry, Anthropic, Apify,
  Browserbase, Google OAuth, Huma. Use BEFORE searching shell history, session
  logs, dotfiles, or the filesystem — the canonical store is documented here
  and the values are reachable via two fish helpers. Also use when adding,
  rotating, or removing a credential.
---

# secret-lookup

Oystein's local secrets are in **one file** with **two fish helpers**. Don't grep, don't search `cass`, don't read shell history — start here.

## Where things are

| Path | What |
|---|---|
| `~/.config/secrets/.env` | Primary store, `KEY=VALUE` per line, mode 600. |
| `~/.config/secrets/huma-tokens.json` | Huma HR API bearer tokens. |
| `~/.config/secrets/humahr-cookies.json` | Huma HR session cookies. |
| `~/.config/fish/functions/secret.fish` | The `secret` helper. |
| `~/.config/fish/functions/with-secrets.fish` | The `with-secrets` helper. |
| `~/.config/fish/conf.d/secrets.fish` | Auto-loader (DISABLED — do not re-enable). |
| `~/.config/fish/conf.d/secrets.fish.disabled` | Backup of the old auto-loader (for rollback only). |
| `~/bin/refresh-secrets-list` | Regenerates the key list in `~/.claude/CLAUDE.md`. |

## How to read a secret

```fish
secret CLOUDFLARE_API_TOKEN          # prints value to stdout
secret --list                        # prints all key names, one per line
```

## How to run a command with a secret in its env

```fish
with-secrets CLOUDFLARE_API_TOKEN -- curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/...
with-secrets GITHUB_PERSONAL_ACCESS_TOKEN -- gh api /user
with-secrets ZENDESK_API_TOKEN ZENDESK_EMAIL -- some-script
```

The variables exist only inside CMD. The parent shell never gets them. **This is the only correct way** to give a subprocess a secret.

## Hard rules (these matter)

1. **Never echo a secret value into chat.** Not partial, not "for confirmation," not in test output. The transcript ends up in `cass` and is indexed forever. To verify a secret is loaded, check **length only**:
   ```fish
   secret CLOUDFLARE_API_TOKEN | string length    # prints e.g. 53
   ```
   Never `echo $FOO`, never interpolate `$FOO` into a printed string — even when you "expect" it to be empty. A long-running shell may still have residual env from before the auto-loader was disabled.
2. **Never `set -gx FOO` from the `.env` file.** That recreates the global-export anti-pattern this design was built to remove. If a tool absolutely needs the env var, wrap it in `with-secrets`.
3. **Never commit a secret.** `~/.config/secrets/` is outside any repo. If you see a `.env` line being added to a tracked file, stop and flag it.
4. **Reference by env-var name** in scripts, configs, MCP json, etc. (`$CLOUDFLARE_API_TOKEN`), never by literal value.
5. **Don't search for secrets** in `cass`, shell history, or the filesystem before checking `secret --list`. Almost everything is in `.env`.

## Tool-managed credential stores (do NOT duplicate into `.env`)

These tools manage their own credentials. Leave them alone unless you're explicitly working on that tool's auth:

`~/.ssh/`, `~/.gnupg/`, `~/.config/gh/`, `~/.config/gcloud/`, `~/.azure/`, `~/.docker/config.json`.

If a tool already has its own credential store, prefer that over adding the token to `.env`.

## Adding / rotating / removing

**Add a new credential:**
```fish
echo 'NEW_KEY=value' >> ~/.config/secrets/.env
~/bin/refresh-secrets-list
```
That regenerates the key list in `~/.claude/CLAUDE.md` (and `~/.codex/AGENTS.md` if present).

**Rotate:** edit the value in `~/.config/secrets/.env`. New `with-secrets` calls and new fish sessions pick it up immediately. Long-running shells: `exec fish`. No need to re-run the regenerator (the key didn't change).

**Remove:** delete the line from `~/.config/secrets/.env`, then `~/bin/refresh-secrets-list`.

## Rollback (only if something genuinely broke)

```fish
cp ~/.config/fish/conf.d/secrets.fish.disabled ~/.config/fish/conf.d/secrets.fish
exec fish
```
This restores the old global-export auto-loader. Don't do this casually — the on-demand model exists because globally-exported secrets get inherited by every npm postinstall, MCP server, and subprocess.

## Why this design

The previous setup auto-exported all ~18 tokens into every fish session. Any subprocess — including ones agents spawn — inherited the full set by default. On-demand retrieval cuts the blast radius: a command sees only the keys it asks for. The trade-off is one extra wrapper (`with-secrets KEY -- ...`); the win is that a misbehaving subprocess can't slurp the whole credential set.

## Anti-patterns

- ❌ `cat ~/.config/secrets/.env` and copy a value into chat. Use `secret KEY | string length` to confirm.
- ❌ `set -gx CLOUDFLARE_API_TOKEN (secret CLOUDFLARE_API_TOKEN)` to "make it available for the rest of the session." Wrap the consuming command instead.
- ❌ Grepping `cass`, `~/.bash_history`, `~/.zsh_history`, or random dotfiles for a token. Run `secret --list` first.
- ❌ Adding a token to `.env` that's already managed by `gh`, `gcloud`, `az`, etc. Let those tools own their credentials.
