Run the weekly-sweep: health → update-os → backup → db-health.

This is the Saturday-night routine. It's idempotent and read-heavy. Expected runtime: 15 to 30 minutes.

1. `./maintain.sh weekly-sweep`. The orchestrator runs all four stages in order; a failure in any stage aborts the rest.
2. When done, read all four `latest-*.json` files and produce a one-paragraph status: "Health: ok/yellow/red. OS updates: N installed, reboot required yes/no. Backup: success, X GB uploaded to Y. DB health: overall ok/yellow/red."
3. If any stage was red, walk me through what went wrong and recommend a follow-up.
4. If `reboot_required=yes`, offer to run `./maintain.sh schedule-reboot`.

This is the core of ongoing operations. If you hit a red anywhere, stop and tell me; don't try to fix in place.
