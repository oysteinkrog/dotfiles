Use the Phase 2 skill to run the `render-config` stage.

1. Run `./operate.sh render-config`. This emits `workdir-phase2/rendered/config.json` + `mattermost.nginx.conf` and validates both.
2. Open `workdir-phase2/reports/config-validation.json`. Confirm `"status": "ready"`.
3. Specifically verify: `MaxPostSize=16383`, `EnableOpenServer=true`, `RequireEmailVerification=false`, SMTP block populated from config.env, nginx vhost has the `/api/v[0-9]+/(users/)?websocket$` Upgrade block.
4. Any red item: tell me which config.env field to change and re-run.
