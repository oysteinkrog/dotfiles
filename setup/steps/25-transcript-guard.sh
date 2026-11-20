# Claude transcripts must never be lost (Oystein, 2026-11-20).
# 1. claude-transcript-vault.timer (user unit, enabled in the services step) hard-links every
#    transcript into ~/.local/share/claude-transcript-vault.
# 2. transcript-delete-trace (system unit, here) logs which process deletes or renames a .jsonl
#    file, to /var/log/transcript-deletes.log.

step "transcript guard"
if command -v bpftrace >/dev/null; then
  sudo install -m 0644 "$SETUP/system/transcript-delete-trace.bt" /usr/local/share/transcript-delete-trace.bt
  sudo install -m 0644 "$SETUP/system/transcript-delete-trace.service" /etc/systemd/system/transcript-delete-trace.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now transcript-delete-trace.service
  sudo systemctl restart transcript-delete-trace.service
else
  warn "bpftrace missing; transcript-delete-trace not installed"
fi
