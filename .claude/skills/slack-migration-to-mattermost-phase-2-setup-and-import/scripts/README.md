# Phase 2 Scripts

| Script | Inputs | Outputs | Exit Behavior | When To Run |
|--------|--------|---------|---------------|-------------|
| `doctor.sh` | `config.env` + PATH | human text or `--json` health report | nonzero on missing required items | at session start, and with `--require-remote` / `--require-mcp` before remote/MCP-driven stages |
| `bootstrap-tools.sh` | host platform | installs mmctl, jq, psql, Python deps | nonzero on install failure | remediation after `doctor.sh` reports required items missing |
| `install-mcp-servers.sh` | `config.env` admin token | Mattermost + Playwright MCP registered in Claude Code / Codex | nonzero on missing node/npx or unknown `--include` | once per workstation; re-run after rotating the admin PAT |
| `../operate.sh` | `config.env` + handoff/import/config inputs | staged Phase 2 reports and rendered configs | nonzero on missing prerequisites or failed stage | default orchestration path |
| `render-nginx-config.sh` | domain + upstream settings | nginx config to stdout | nonzero on bad args | before proxy setup |
| `materialize-mattermost-config.py` | site URL + DB DSN + SMTP/CORS settings | rendered `config.json` | nonzero on missing inputs | before proxy/config validation |
| `provision-mattermost-host.sh` | mode + target host | provisioning plan/report | nonzero on invalid mode or execution failure | host prep/hardening |
| `deploy-mattermost-stack.sh` | mode + rendered config + rendered nginx | deploy plan/report | nonzero on missing inputs or execution failure | stack installation (`apt` service path or real `docker` host-network container path, both fronted by Nginx) |
| `monitor-import.sh` | optional job id | watch log / snapshot via env | nonzero on error, stall, cancel, timeout | while import job runs |
| `verify-mattermost-live.py` | Mattermost URL + optional SMTP host/port | live verification JSON/MD | nonzero on failed HTTP/WS/SMTP checks | after deploy / before import |
| `validate-mattermost-config.py` | `config.json` + expectations | config report JSON | nonzero on import-critical config failure | before staging and production import |
| `build-phase2-intake-manifest.py` | handoff and server-side inputs | intake manifest JSON | nonzero on missing file | before intake validation |
| `validate-phase2-intake.py` | `handoff.json` + optional intake manifest | intake validation report | nonzero on bundle mismatch | before upload/import |
| `run-staging-rehearsal.sh` | staging URL + import ZIP + credentials | staging summary JSON/MD | nonzero on unsafe target or failed rehearsal | before production import; uses the SSH-backed server-side `mmctl` wrapper when `ENABLE_LOCAL_MODE=1` + `TARGET_HOST` are set |
| `run-import-smoke-tests.py` | handoff JSON + Mattermost DB URL/DSN | observed imported-object counts + smoke report JSON/MD | nonzero on failed DB/service checks | after staging or production import; can query via SSH when the DB is not exposed to the workstation |
| `reconcile-handoff-vs-import.py` | handoff JSON + observed counts JSON | delta report JSON | nonzero on missing inputs | after staging or production import |
| `verify-user-activation.sh` | Mattermost URL + test email | activation proof JSON/MD | nonzero on failed reset-flow trigger | before or after cutover |
| `restore-drill.sh` | DB backup + scratch DB URL | restore drill JSON/MD | nonzero on unsafe target or restore failure | before production cutover |
| `validate-cutover-readiness.py` | reports from handoff/config/staging/restore | readiness gate JSON | nonzero when cutover must stop | immediately before cutover |
| `generate-readiness-score.py` | validation reports | score JSON/optional MD | nonzero on missing reports | final decision support |
| `generate-phase2-readiness.py` | handoff + validation reports | readiness summary MD | nonzero on missing reports | before war-room review |
| `execute-production-cutover.sh` | production URL + import ZIP + creds + handoff | cutover status JSON/MD + smoke/reconcile/activation artifacts | nonzero on failed import or post-import gates | production execution |
| `rollback-cutover.sh` | DB backup + DB URL + rollback env | rollback JSON/MD | nonzero on missing confirmation or restore failure | abort/rollback execution |
| `run-e2e-rehearsal.sh` | none or `E2E_REHEARSAL_ROOT` | full local exact-flow rehearsal bundle | nonzero on any Phase 1/2 regression | exact-flow integration proof |
