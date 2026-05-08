Use the Phase 2 skill to run the `deploy` stage.

1. Run `./operate.sh deploy`. Based on `DEPLOY_METHOD`: APT installs `mattermost`+`nginx`, Docker pulls `mattermost/mattermost-team-edition:latest`.
2. Known edge case: Ubuntu 25.10 (`questing`) — Mattermost APT repo may lack that codename. If apt fails, switch `DEPLOY_METHOD=docker` and re-run.
3. Install the rendered config.json + nginx.conf. Install TLS cert from `workdir-phase2/rendered/origin.{pem,-key.pem}` (or whatever NGINX_CERT_PATH/NGINX_KEY_PATH point at).
4. Start services (`systemctl enable --now nginx mattermost`). Then pause — `verify-live` is the next stage.
