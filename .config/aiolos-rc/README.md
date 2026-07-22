# aiolos-rc

Run a Claude Code session that shows up as a **remote-control session in your main
claude.ai account** (steerable from your phone/web), while its **inference runs on a
different aiolos account**.

## The problem, and why this shape

Claude Code (>= v2.1.196) disables `/remote-control` client-side when
`ANTHROPIC_BASE_URL` points at anything other than `api.anthropic.com` (a proxy like
aiolos). The obvious workaround, `ANTHROPIC_UNIX_SOCKET`, bypasses that host gate but
flips Claude into "host-managed auth" mode, which then fails the remote-control
subscription check ("subscription auth not active") and hides the command again.

So `aiolos-rc` keeps Claude in its **normal** mode with `ANTHROPIC_BASE_URL` pinned to
`https://api.anthropic.com` (Claude's RC gate `YGn()` requires that exact host;
remote control stays enabled and your team seat is accepted) and instead redirects
**only this process's** traffic to a local shim with a per-process `LD_PRELOAD` that
intercepts `getaddrinfo`/`connect`. No unix socket, no root, no `/etc/hosts`, no
privileged port. The shim terminates TLS with a local `api.anthropic.com` cert
(trusted via `NODE_EXTRA_CA_CERTS`) and splits by path:

| Request | Goes to | Result |
|---|---|---|
| `/v1/messages*` (inference) | aiolos, `x-aiolos-account-id: <X>` (strict) | work runs on account **X** |
| everything else (RC, sessions, oauth, api) | `api.anthropic.com` on your stored **main** login | RC registers under your **main** account |

## Routing modes

- **no-pin** (`--no-pin`): inference goes to aiolos with **no** account header, so
  aiolos load-balances across all your accounts exactly as normal Claude does — plus
  `/remote-control` is enabled. This is the daily-driver mode; `c` / `cc` / `cr` use it.
- **pinned** (default, or `--account <id|email>`): inference is pinned **strictly** to
  one account and fails closed (503) if that account is paused/rate-limited. Use it
  when you specifically want a session's work to run on one chosen account.

## Install / replicate on a new machine

```bash
# 1. dotfiles installer symlinks ~/.config/aiolos-rc -> this dir (it's in config_dirs)
~/.dotfiles/install.sh

# 2. build preload.so + generate machine-local certs and config under
#    ~/.config/secrets/aiolos-rc/ (needs gcc + openssl; idempotent)
~/.config/aiolos-rc/setup.sh

# 3. point Claude at your aiolos instance: add ANTHROPIC_BASE_URL to the env block
#    of ~/.claude/settings.local.json (machine-local, untracked), e.g.
#    { "env": { "ANTHROPIC_BASE_URL": "http://<aiolos-host>:<port>" } }

# 4. (optional) for pinned mode, set DEFAULT_ACCOUNT in
#    ~/.config/secrets/aiolos-rc/config.env
```

Nothing sensitive is tracked: the TLS private keys, the aiolos URL, and the account
id all live outside this dir (`~/.config/secrets/…` and `settings.local.json`).

## Usage

```bash
# daily driver: load-balanced inference + remote-control (what c/cc/cr run):
~/.config/aiolos-rc/aiolos-rc --no-pin

# pinned to the DEFAULT_ACCOUNT from config.env:
~/.config/aiolos-rc/aiolos-rc

# pinned to a specific account by email or id:
~/.config/aiolos-rc/aiolos-rc --account <account-id-or-email>

# extra args pass through to claude (e.g. continue/resume):
~/.config/aiolos-rc/aiolos-rc --no-pin -c

~/.config/aiolos-rc/aiolos-rc --status
~/.config/aiolos-rc/aiolos-rc --stop
```

`c` / `cc` / `cr` (fish) are wired to `aiolos-rc --no-pin [-c|-r]`, so every everyday
session goes through aiolos (load-balanced) and exposes `/remote-control`.

The aiolos URL for the inference leg is read from `ANTHROPIC_BASE_URL` in the current
shell if set, otherwise from `~/.claude/settings.local.json`. Add the dir to PATH for
a bare `aiolos-rc`.

**One shim per session.** Each `aiolos-rc` invocation starts its own shim on a fresh
ephemeral port and tears it down when Claude exits, so multiple concurrent Claude
instances are fully isolated — no shared port, no cross-session restarts, no single
point of failure. `--status` lists running session shims; `--stop` stops all of them.
Registry + per-session logs live under `~/.config/aiolos-rc/shims/`.

## Why `/remote-control` was hidden, and how the override works

Claude's RC command is `isHidden: !Px()`, and `Px()` ultimately requires
`YGn()` — the effective `ANTHROPIC_BASE_URL` host must be `api.anthropic.com`
(or unset). Routing normal Claude through aiolos sets that host to the proxy, so
the command is hidden. `aiolos-rc` needs the opposite for its own process.

The base URL is pinned to aiolos in **`~/.claude/settings.local.json`** (`env`
block), which Claude applies by overwriting `process.env` **unconditionally at
startup** — so a shell env var cannot beat it. Instead, `aiolos-rc` passes
`--settings <file>` with `{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}`.
That maps to Claude's `flagSettings` source, which outranks user/project/local
settings in the precedence order
`["userSettings","projectSettings","localSettings","flagSettings","policySettings"]`
(later wins). So the RC session sees `api.anthropic.com` **without mutating any
shared file** — no concurrent-session hazard, nothing to restore.

Note: the previous global shell export in `~/.config/fish/config.fish` has been
retired; `settings.local.json` is now the sole source that routes normal Claude
through aiolos. Both being set was why an earlier "direct" test still hid the
command (clearing one left the other injecting the proxy host).

## Requirements / caveats

- **Log into your phone/web as your main claude.ai account** — RC is controlled from
  whatever claude.ai identity owns the session, and that is your stored main login here.
- The inference pin is **strict**: if account X is paused/rate-limited the inference
  leg fails closed (503) rather than silently using another account. Change account
  (`--account`) or `--stop` to switch.
- The shim is a **local MITM of this process's Claude traffic** (it terminates TLS to
  route requests). It runs only on this machine, only for `aiolos-rc` sessions.
- The `LD_PRELOAD` interception relies on Claude resolving via glibc `getaddrinfo`
  (verified against the bundled Bun runtime). If a future build switches to its own
  resolver, the redirect would need revisiting.
- `RC_DEBUG=1 aiolos-rc ...` logs one line per request (method, path, upstream) to
  that session's log under `shims/`. No bodies or tokens are ever logged.
- The shim binds an ephemeral port per session (assigned by the OS); there is no
  fixed port to configure.
- Launches the native binary the same way `~/.config/fish/functions/claude.fish` does
  (WSL1 `p_align` patch + `--dangerously-skip-permissions`); override the flag with
  `AIOLOS_RC_SKIP_PERMISSIONS=""`.

## Files

- `aiolos-rc` — launcher (one shim per session; `--status` / `--stop` manage them)
- `shim.py` — path-splitting TLS shim on an ephemeral `127.0.0.1` port
- `preload.c` / `preload.so` — per-process `api.anthropic.com` → shim redirect
- `certs/` — local CA + `api.anthropic.com` leaf (825-day, machine-local)
- `shims/` — per-session registry + logs (auto-managed)
