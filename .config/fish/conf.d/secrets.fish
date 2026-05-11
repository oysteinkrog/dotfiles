# DISABLED 2026-05-11 — secrets are no longer globally exported.
#
# Use the on-demand helpers instead (see ~/.config/fish/functions/):
#   secret KEY                    -> print value to stdout
#   secret --list                 -> list available keys
#   with-secrets KEY [...] -- CMD -> run CMD with named keys in its env
#
# The original auto-loader is preserved at:
#   ~/.config/fish/conf.d/secrets.fish.disabled
# To roll back, copy it back over this file:
#   cp ~/.config/fish/conf.d/secrets.fish.disabled ~/.config/fish/conf.d/secrets.fish
# Source of truth: ~/.config/secrets/.env
