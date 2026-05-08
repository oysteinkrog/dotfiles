# Migration Threat Model

The migration touches high-value secrets and sensitive content.

## Assets

- raw Slack exports
- member directory CSVs
- sidecar archives
- SMTP credentials
- Mattermost admin credentials
- Cloudflare / R2 credentials
- staging and production import ZIPs

## Trust Boundaries

- local operator workstation
- staging environment
- production Mattermost host
- Slack admin plane
- Cloudflare and storage providers

## Adversarial Concerns

- token leakage in logs or shell history
- importing the wrong workspace bundle
- staging shortcuts accidentally targeting production
- permissive activation settings left enabled after cutover
- evidence packs shared without redaction

## Required Countermoves

- hash everything
- stage before production
- quarantine intake artifacts
- fail closed on config and cutover gates
- revoke temporary credentials after cutover
