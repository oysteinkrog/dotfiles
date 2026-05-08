Use the Phase 2 skill to run the `provision` stage.

1. First confirm SSH works non-interactively: `./scripts/doctor.sh --require-remote`. If that's red, stop and fix SSH keys before continuing.
2. Run `./operate.sh provision` in `plan` mode first. Show me the resulting `provision-host.sh` — I want to read it before it runs on the server.
3. If the plan is acceptable, re-run in `ssh` mode. This applies UFW, fail2ban, unattended-upgrades, and (if `PROVISION_DATABASE_MODE=local|auto`) local PostgreSQL.
4. After: on the server, `systemctl status fail2ban` and `sudo ufw status verbose` should both be active. Verify.
