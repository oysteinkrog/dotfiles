Schedule a pending reboot in the next off-hours window.

1. Check `workdir-phase3/reports/latest-update-os.json`. If `reboot_required=no`, tell me and stop.
2. If yes, compute the next window from `REBOOT_WINDOW_DAY` + `REBOOT_WINDOW_HOUR_START/END` (UTC). Tell me what day/time that is in my local timezone and ask me to confirm.
3. On my approval, run `./maintain.sh schedule-reboot`. It uses `at` on the target host to queue the reboot.
4. Post-schedule: append a message for me to put in #ops: "Scheduled Mattermost reboot for [DATE] [TIME] UTC during the maintenance window; expected downtime 1 to 3 minutes."
5. Read `workdir-phase3/reboot-history.json` and summarize the last 5 scheduled reboots.

Never reboot outside the configured window without explicit approval.
