# Phase 2 ready-to-paste prompts

Each file is a short natural-language prompt for one Phase 2 stage. Paste into Claude Code / Codex.

## Index

| File | When to use |
|------|-------------|
| [orient.md](orient.md) | First prompt in a Phase 2 session — load the mental model |
| [intake.md](intake.md) | Accept the Phase 1 handoff bundle |
| [render-config.md](render-config.md) | Render Mattermost + Nginx config |
| [edge.md](edge.md) | Provision Cloudflare DNS + Origin CA |
| [provision.md](provision.md) | SSH to Ubuntu host and base-provision it |
| [deploy.md](deploy.md) | Install Mattermost + Nginx + TLS |
| [verify-live.md](verify-live.md) | HTTPS + WebSocket + SMTP probes |
| [staging.md](staging.md) | Full import dry-run against non-prod |
| [restore.md](restore.md) | Backup-restore drill |
| [ready.md](ready.md) | Compute fail-closed readiness gate |
| [cutover.md](cutover.md) | Production cutover (only after ready=green) |
| [rollback.md](rollback.md) | Restore from backup if cutover failed |
| [cutover-day.md](cutover-day.md) | Full cutover-day sequence with operator pauses |
| [post-cutover.md](post-cutover.md) | T+0 through T+7 day operations |
| [resume.md](resume.md) | Figure out where a paused migration is |
