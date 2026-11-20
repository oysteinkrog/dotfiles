---
name: krdp-troubleshooting
description: Find and fix why an RDP client cannot connect to KRDP (the KDE RDP server) on one of Oystein's Linux desktops, or connects to a black picture. Covers wrong user name, mstsc sending no password, the PAM lockout, the missing portal permission, and the resize hook asking for a monitor mode the NVIDIA driver cannot drive. Use when the user says RDP, remote desktop, mstsc or KRDP "is not working", "won't log in", "never asks for a password" or "shows a black screen", or when setting up a new RDP client machine.
---

# KRDP troubleshooting

The runbook, with the exact commands, log patterns and the per-machine details, is in the
Life repo: `docs/computers/linux-setup.md`, sections "RDP troubleshooting" and
"RDP from the Windows laptop" (`~/projects/life` at home, `~/work/life` at the office).
Read those sections first. This file holds only the order of work.

1. **Read the server log before touching the client.** `journalctl --user -u
   app-org.kde.krdpserver.service`. Each failure leaves a different trace, and the table in
   the runbook maps the trace to the cause. No `New client connected` line at all means the
   client aims at the wrong address.
2. **Fix the client over SSH, not by dictating steps.** If the client is a Windows machine
   without SSH, have Oystein run the one-time OpenSSH setup from the runbook, then work on it
   yourself. A saved RDP password is invisible to an SSH session; the runbook shows how to
   read the real list.
3. **Do not count on a password prompt from mstsc.** KRDP in PAM mode has no NLA, so mstsc
   sends only a saved password. Oystein saves it with `cmdkey /generic:TERMSRV/<host>
   /user:oystein /pass`. Never ask for or store the password yourself.
4. **Three failures lock the account for 10 minutes.** Clear it with
   `sudo faillock --user oystein --reset` before the next try, or the right password fails too.
5. **A black picture after login is usually the monitor mode.** Add the client's size to the
   EDID override with `edid-add-mode`, test that KWin keeps the mode, and make it permanent in
   the host profile and the boot unit.
6. **Ask before changing a login password or anything in `/etc/shadow`.** Back up the old
   hash first, as the runbook shows.
7. **Write down what you learned** in the runbook section, not here. Keep hostnames, IPs and
   user names out of this file: the dotfiles repo is public.
