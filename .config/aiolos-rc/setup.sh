#!/usr/bin/env bash
# aiolos-rc setup — run once per machine (idempotent).
#
# Builds the LD_PRELOAD redirect and generates the machine-local TLS certs +
# config that live OUTSIDE this tracked dir, under ~/.config/secrets/aiolos-rc
# (override with AIOLOS_RC_SECRETS). Nothing secret is ever written into the repo.
#
#   ./setup.sh
#
# After running, set DEFAULT_ACCOUNT in the generated config.env if you want a
# pinned-mode default, and make sure ~/.claude/settings.local.json's env block
# has ANTHROPIC_BASE_URL pointing at your aiolos instance.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"   # physical path (resolve symlink)
SECRETS="${AIOLOS_RC_SECRETS:-$HOME/.config/secrets/aiolos-rc}"
CERTS="$SECRETS/certs"

echo "=== aiolos-rc setup ==="
echo "code dir : $DIR"
echo "secrets  : $SECRETS"

# 1. Build the LD_PRELOAD redirect (arch-specific; never committed).
if command -v gcc >/dev/null 2>&1; then
  gcc -shared -fPIC -O2 -o "$DIR/preload.so" "$DIR/preload.c" -ldl
  echo "built preload.so"
else
  echo "WARNING: gcc not found — install it, then re-run to build preload.so" >&2
fi

# 2. Generate the local api.anthropic.com CA + leaf (trusted only on this machine
#    via NODE_EXTRA_CA_CERTS). Skipped if a leaf chain already exists.
mkdir -p "$CERTS"
chmod 700 "$SECRETS" "$CERTS" 2>/dev/null || true
if [ -f "$CERTS/leaf-chain.pem" ] && [ -f "$CERTS/leaf.key" ] && [ -f "$CERTS/ca.pem" ]; then
  echo "certs present — leaving as-is"
elif command -v openssl >/dev/null 2>&1; then
  printf '%s\n' \
    '[req]' 'distinguished_name=dn' 'req_extensions=v3' '[dn]' '[v3]' \
    'subjectAltName=DNS:api.anthropic.com' > "$CERTS/leaf.cnf"
  openssl genrsa -out "$CERTS/ca.key" 2048
  openssl req -x509 -new -nodes -key "$CERTS/ca.key" -sha256 -days 825 \
    -subj "/CN=aiolos-rc local CA" -out "$CERTS/ca.pem"
  openssl genrsa -out "$CERTS/leaf.key" 2048
  openssl req -new -key "$CERTS/leaf.key" -subj "/CN=api.anthropic.com" \
    -out "$CERTS/leaf.csr" -config "$CERTS/leaf.cnf"
  openssl x509 -req -in "$CERTS/leaf.csr" -CA "$CERTS/ca.pem" -CAkey "$CERTS/ca.key" \
    -CAcreateserial -days 825 -sha256 -extfile "$CERTS/leaf.cnf" -extensions v3 \
    -out "$CERTS/leaf.pem"
  cat "$CERTS/leaf.pem" "$CERTS/ca.pem" > "$CERTS/leaf-chain.pem"
  chmod 600 "$CERTS/ca.key" "$CERTS/leaf.key"
  echo "generated certs (825-day, SAN=api.anthropic.com)"
else
  echo "WARNING: openssl not found — install it, then re-run to generate certs" >&2
fi

# 3. Seed the machine-local config (account id for pinned mode).
if [ ! -f "$SECRETS/config.env" ]; then
  cp "$DIR/config.env.example" "$SECRETS/config.env"
  chmod 600 "$SECRETS/config.env"
  echo "seeded config.env — edit DEFAULT_ACCOUNT if you want a pinned default"
fi

# 4. Ensure ~/.config/aiolos-rc points at this dir (install.sh also links it).
LINK="$HOME/.config/aiolos-rc"
if [ ! -e "$LINK" ] || { [ -L "$LINK" ] && [ "$(readlink "$LINK")" != "$DIR" ]; }; then
  ln -sfn "$DIR" "$LINK"
  echo "linked $LINK -> $DIR"
fi

echo "=== done ==="
