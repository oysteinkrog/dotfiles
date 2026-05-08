Use the Phase 2 skill to run the `verify-live` stage.

1. Run `./operate.sh verify-live`. This runs three probes with retry: /api/v4/system/ping, WebSocket upgrade against /api/v4/websocket, SMTP STARTTLS handshake.
2. If `CLOUDFLARE_ENABLED=1`, also runs `verify-cloudflare-edge.py`.
3. Read `workdir-phase2/reports/live-stack.md`. Common failures:
   - WebSocket fails → nginx Upgrade block missing → re-run `render-config` + `deploy`.
   - SMTP fails → provider blocking port 587, wrong creds, or SMTP_USERNAME missing. Test with `swaks` to isolate.
4. Everything green = proceed to `staging`.
