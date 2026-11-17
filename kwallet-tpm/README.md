# KWallet TPM Unlock

These files make the KDE wallet `kdewallet` open by itself at autologin on the office desktop.
The wallet's key is sealed with the TPM. The wallet file stays encrypted on disk.

Why it is needed: with autologin there is no password for `pam_kwallet5` to use. It logs
"Couldn't get password (it is empty)" and does nothing, so the Secret Service collection stays
locked and every program that asks for a secret waits for a prompt.

## How it works

`pam_kwallet5` (kwallet-pam 6.8.2) normally does this at a password login:

1. It derives a 56-byte key from the password: PBKDF2-HMAC-SHA512, 50000 rounds, salt from
   `~/.local/share/kwalletd/kdewallet.salt` (56 bytes).
2. It starts `/usr/bin/ksecretd --pam-login <pipe-fd> <socket-fd>` with `PAM_KWALLET5_LOGIN`
   set, and writes the key into the pipe.
3. Later `pam_kwallet_init` sends the session environment to the socket, and ksecretd opens the
   wallet with the key (`KSecretD::pamOpen`).

Here, `seal-kwallet-key` derives the same key once and seals it with
`systemd-creds encrypt --user --with-key=host+tpm2`. At login, D-Bus starts `ksecretd-tpm`
instead of `/usr/bin/ksecretd`. It unseals the key, puts it in a pipe, gives ksecretd an empty
environment on a socket, and starts ksecretd in `--pam-login` mode. The wallet opens with no
prompt.

If unsealing fails for any reason, `ksecretd-tpm` starts plain ksecretd, which asks for the
password as before. It logs one line to the journal with the reason, never the key:

```sh
journalctl --user -t ksecretd-tpm -b
```

A wrong key (for example after a password change) does not show up there: ksecretd starts in
`--pam-login` mode, fails to open the wallet, and the wallet stays locked until you type the
password. Seal the key again to fix it.

To find out whether the sealed key opens the wallet, without a reboot and without touching the
running wallet, run:

```sh
~/.dotfiles/kwallet-tpm/check-kwallet-key
```

It starts the wrapper on a private D-Bus session against a copy of the wallet, with no window.
Exit 0 means the key opens the wallet. Exit 1 with "error code is -9" means the key came from a
different password; run `seal-kwallet-key` again.

## Files

| File | What it does |
|---|---|
| `ksecretd-tpm` | The wrapper D-Bus starts. Python, run with `-I`. |
| `seal-kwallet-key` | Asks for the wallet password, derives the key, seals it into `~/.config/kwallet-tpm/kdewallet.cred` (mode 0600). |
| `check-kwallet-key` | Checks that the sealed key opens a copy of the wallet. Run it after sealing. |
| `install.sh` | Writes two D-Bus service files into `~/.local/share/dbus-1/services`. `--undo` removes them. |

The two service files override `org.kde.secretservicecompat` and
`org.freedesktop.impl.portal.desktop.kwallet` in `/usr/share/dbus-1/services`. Those are the
only two names whose `Exec` is `/usr/bin/ksecretd`. Today xdg-desktop-portal starts ksecretd
through the portal name at login. The user directory wins: dbus-broker reads
`$XDG_RUNTIME_DIR/dbus-1/services`, then `~/.local/share/dbus-1/services`, then
`/usr/share/dbus-1/services`, and keeps the first file for each name. It logs "Ignoring duplicate
name" for the `/usr/share` copy, which is expected.

## Install

1. Install the service files:

   ```sh
   ~/.dotfiles/kwallet-tpm/install.sh
   ```

2. Seal the key. Run this in a terminal and type the wallet password at the hidden prompt
   (twice):

   ```sh
   ~/.dotfiles/kwallet-tpm/seal-kwallet-key
   ```

3. Reboot, or log out and in. The running ksecretd is not changed by steps 1 and 2. The user bus
   lingers (`Linger=yes`), so a log out alone may keep the old ksecretd running. A reboot is the
   sure test.

4. Check after login:

   ```sh
   busctl --user get-property org.freedesktop.secrets \
     /org/freedesktop/secrets/collection/kdewallet org.freedesktop.Secret.Collection Locked
   # b false
   journalctl --user -t ksecretd-tpm -b
   # starting ksecretd with the sealed key
   ```

Seal the key again after you change the wallet password, after a TPM clear, after a
reinstall that changes `/etc/machine-id` or `/var/lib/systemd/credential.secret`, and if the
`kdewallet.salt` file is replaced.

## Undo

```sh
~/.dotfiles/kwallet-tpm/install.sh --undo
rm ~/.config/kwallet-tpm/kdewallet.cred
```

Then reboot. ksecretd starts from `/usr/share/dbus-1/services` again.

## Key choice

`systemd-creds --user` only accepts `host` or `host+tpm2` in user-scoped mode. `tpm2` alone is
refused ("Selected key not available in --uid= scoped mode"). `host+tpm2` is used. The sealed
file opens only with this machine's TPM, the host secret in `/var/lib/systemd/credential.secret`,
this machine id and this user. The decrypt runs through systemd's credential service, so the
user does not need access to `/dev/tpmrm0`.

The key is not bound to any PCR. Secure Boot is off on this machine, so PCR 7 would not tell a
live USB boot apart from a normal one, and binding to boot measurements would break on every
kernel or firmware update.

## Security trade-off

- After login, any process running as oystein can read wallet secrets through the Secret
  Service. That is the same as when you unlock the wallet by hand.
- The sealed key is the wallet key itself, not the password. It cannot be turned back into the
  password, but it opens the wallet.
- The disk is not encrypted. Someone who takes the whole machine (disk and TPM together) can
  boot another OS, read the host secret and the sealed file from the disk, and ask this TPM to
  unseal it. Without this setup they would have to guess the wallet password. Copying the disk
  to another machine is not enough, because the TPM stays behind.
- `seal-kwallet-key` never writes the password or the key to disk or prints them. The wrapper
  holds the key only until it starts ksecretd, which replaces the wrapper's memory.

## Tested

On 2026-11-13, on a private D-Bus session with a throwaway wallet, a test password and the
credential name `kwallet-tpm-test`. The real ksecretd was not touched.

- A correct key: the collection was unlocked and `secret-tool` stored and read an item with no
  prompt, also after a restart with the existing wallet file.
- A wrong key: ksecretd started in `--pam-login` mode and the collection stayed locked.
- A credential with the wrong name, and a missing credential: plain ksecretd started, the
  collection stayed locked, and the journal line gave the reason.
- libgcrypt's `gcry_kdf_derive` (what kwallet-pam and ksecretd use) and Python's
  `hashlib.pbkdf2_hmac` gave the same key for three test inputs.

Not tested: a real reboot with autologin, and the real wallet.
