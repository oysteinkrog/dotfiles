---
name: lab-deploy
description: >-
  Reach the lab PC, the Windows machine "Hawk" at 192.168.1.143 in the Trondheim
  office: log in over ssh, run PowerShell there, copy a build or file to it, and pull
  the newest Swing Catalyst logs back. Use when the user mentions the lab PC, the lab
  machine, Hawk, testing on the lab rig, or wants logs from the lab.
---

# Lab PC (Hawk)

| | |
|---|---|
| Address | `192.168.1.143`, office LAN only. Not on Tailscale, so it is unreachable from outside the office network |
| Login | `ssh labpc` (alias `hawk`), user `trondheim golfsenter`, key `~/.ssh/labpc_ed25519` |
| Auth | Keys only. sshd has `PasswordAuthentication no`. Backup config: `C:\ProgramData\ssh\sshd_config.bak-2026-09-29` |
| Remote shell | `cmd`. Run PowerShell through the script below rather than quoting it by hand |
| Installed app | `C:\Program Files\Initial Force\Swing Catalyst` (plus an old `Swing Catalyst Alpha` from 2026-06) |
| Logs | `C:\ProgramData\Swing Catalyst\logs` (`log.txt`, `log.YYYYMMDD.txt`, `log_error.txt`, `log_hwreport.txt`) |

## Script

`~/.claude/skills/lab-deploy/lab-deploy.sh`:

```sh
lab-deploy.sh run 'Get-Process MotionCatalyst* | Select Id,StartTime'   # PowerShell on Hawk
lab-deploy.sh push ./SwingCatalystSetup.exe                             # to C:/lab-drop
lab-deploy.sh push ./build-dir 'C:/lab-drop/26.2.3'                     # folder, chosen dir
lab-deploy.sh logs 3                                                    # newest 3 logs -> ~/.lab-logs/<timestamp>/
```

`run` sends the script as `-EncodedCommand`, so quotes, `$` and backslashes need no escaping.

## Rules

- **People use this PC.** Someone may be running Swing Catalyst with hardware connected. Never
  stop or restart the app, install over it, or reboot without asking the user first.
- **This machine cannot build Swing Catalyst** (Linux, no `cmd.exe`). Get an installer from CI
  (the monorepo's `release-installers` skill finds the download link), then `push` it.
- **The Windows password is only for someone sitting at the PC.** It is `LAB_DEPLOY_PASSWORD`
  in the secrets file. Never put it in a file or a command line.
- **Adding a key:** append it to `C:\ProgramData\ssh\administrators_authorized_keys` (the account
  is an admin, so `~\.ssh\authorized_keys` is ignored). The file must allow only SYSTEM and
  Administrators: `icacls <file> /inheritance:r /grant "*S-1-5-32-544:F" /grant "SYSTEM:F"`.
- **Restarting sshd:** run `Restart-Service sshd -Force` directly and reconnect. A detached
  `Start-Process` that restarts it dies with the session and does nothing.
