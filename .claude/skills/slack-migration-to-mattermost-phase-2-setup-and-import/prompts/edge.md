Use the Phase 2 skill to run the `edge` stage.

Only applicable if `CLOUDFLARE_ENABLED=1`. In `plan` mode this prints what would be done without calling the API; in `execute` mode it actually provisions.

1. First run with `CLOUDFLARE_MODE=plan` and show me the plan. I want to eyeball the DNS records + origin CA cert before we execute.
2. If plan looks right, switch to `CLOUDFLARE_MODE=execute` and re-run. Confirm: A record orange-clouded, origin CA cert saved to `workdir-phase2/rendered/origin.{pem,-key.pem}`.
3. If `CALLS_HOSTNAME` is set, confirm it's grey-clouded (Cloudflare can't proxy the UDP that Calls needs).
