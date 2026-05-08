Run `./maintain.sh update-os` against the live host.

1. Before running, tell me the OS_UPDATE_POLICY setting and what it will do.
2. Run the stage. Show me the key output (upgradable count, security count, whether autoremove removed anything).
3. Read `workdir-phase3/reports/latest-update-os.json`. If `reboot_required=yes`, tell me when the next scheduled reboot window falls per `REBOOT_WINDOW_*` config, and offer to run `./maintain.sh schedule-reboot` now.

Do not reboot immediately. Never run `./maintain.sh schedule-reboot` without my explicit go-ahead.
