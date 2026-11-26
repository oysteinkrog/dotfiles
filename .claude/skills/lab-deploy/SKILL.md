---
name: lab-deploy
description: >-
  Reach the office test PCs, the Windows machines trd-pc-1-lab (the lab PC, formerly
  trd-lab-pc and Hawk) and trd-pc-2-lowend (formerly trd-lab-pc2) in the Trondheim office:
  log in over ssh from anywhere through Headscale, run PowerShell there, copy a build or file
  to them, and pull the newest Swing Catalyst logs back. Use when the user mentions the lab
  PC, the test PCs, the low-end PC, trd-pc-1-lab, trd-pc-2-lowend, their old names, testing on
  the lab rig, or wants logs from the lab.
---

# Office test PCs

The full description of both PCs (access, rules, specs, how to add a PC) is in the monorepo's
`tools/qa/lab/LAB-PCS.md`. The short version:

| | `trd-pc-1-lab` | `trd-pc-2-lowend` |
|---|---|---|
| Login | `ssh trd-pc-1-lab` (old: `labpc`, `hawk`), user `trondheim golfsenter`, key `~/.ssh/labpc_ed25519` | `ssh trd-pc-2-lowend` (old: `labpc2`), user `labqa`, key `~/.ssh/labpc2_ed25519` |
| Network | Headscale 100.64.0.9 (`tag:trd-pc`, only Oystein's devices), office LAN 192.168.1.160 | Headscale 100.64.0.8 (`tag:trd-pc`, only Oystein's devices), office LAN 192.168.1.189 |
| Who uses it | People, with hardware connected | Agents; `labqa` logs on by itself |
| Windows password | `LAB_PC_LOGIN_PASSWORD` (same value as `LAB_DEPLOY_PASSWORD`) | `LAB_PC2_LOGIN_PASSWORD` |

Both: keys only (`PasswordAuthentication no`), remote shell `cmd`, app in
`C:\Program Files\Initial Force\Swing Catalyst`, logs in `C:\ProgramData\Swing Catalyst\logs`
(`log.txt`, `log.YYYYMMDD.txt`, `log_error.txt`, `log_hwreport.txt`).

## Script

`~/.claude/skills/lab-deploy/lab-deploy.sh` works on `trd-pc-1-lab`. Set
`LAB_SSH_HOST=trd-pc-2-lowend` for the other PC:

```sh
lab-deploy.sh run 'Get-Process MotionCatalyst* | Select Id,StartTime'   # PowerShell on the lab PC
lab-deploy.sh push ./SwingCatalystSetup.exe                             # to C:/lab-drop
lab-deploy.sh push ./build-dir 'C:/lab-drop/26.2.3'                     # folder, chosen dir
lab-deploy.sh logs 3                                                    # newest 3 logs -> ~/.lab-logs/<timestamp>/
```

`run` sends the script as `-EncodedCommand`, so quotes, `$` and backslashes need no escaping.

## Rules

- **People use trd-pc-1-lab.** Someone may be running Swing Catalyst with hardware connected. Never
  stop or restart the app, install over it, or reboot without asking the user first.
- **Test a fix or feature from a branch build, not an installer.** Oystein, 2026-10-14: waiting
  for a merge plus a ~20 min CI installer "slows everything down massively". Build the branch here
  in a grove lane and push it:
  `git -C <lane> checkout --detach <PR head>`, then
  `heavy-build ./build.sh build --target wine --config ReleaseInternal`, then
  `python3 tools/qa/lab/labqa.py ri-push src/motioncatalyst/BUILD/x64_ReleaseInternal_win-x64`
  (about 4 min and 20 s). `ri-push` swaps the Wine bridges (FLIR_GenTL_v140.cti, Bertec ftd2xx.dll)
  for the Windows originals; a build copied any other way hangs at the Spinnaker start. Run it in a
  test hive like any `C:\LabQa\ri` build. Use a CI installer only when the installer itself is
  under test (`desktop-classic-release-installers` finds the link, then `push`).
  `ri-push --name <name>` installs under `C:\LabQa\ri\<name>`, so several builds can sit side by side.
- **Portable tools are fine on the test PCs without asking.** Oystein, 2026-10-20: a self-contained
  tool you copy in and can delete again (a signed Sysinternals exe, a static binary) goes in
  `C:\LabQa\perf\tools` or another `C:\LabQa` task folder. Download it from the vendor's site,
  check the Authenticode signature (`(Get-AuthenticodeSignature <exe>).Status` must be `Valid`)
  and report the path. Installers, services, drivers and registry changes still need a yes.
  RAMMap64.exe is already at `C:\LabQa\perf\tools` (startup timing cold-cache runs).
- **The Windows password is only for someone sitting at the PC,** or for RDP to
  trd-pc-2-lowend. Never put it in a file or a command line.
- **Adding a key:** append it to `C:\ProgramData\ssh\administrators_authorized_keys` (the account
  is an admin, so `~\.ssh\authorized_keys` is ignored). The file must allow only SYSTEM and
  Administrators: `icacls <file> /inheritance:r /grant "*S-1-5-32-544:F" /grant "SYSTEM:F"`.
- **Restarting sshd:** run `Restart-Service sshd -Force` directly and reconnect. A detached
  `Start-Process` that restarts it dies with the session and does nothing.
