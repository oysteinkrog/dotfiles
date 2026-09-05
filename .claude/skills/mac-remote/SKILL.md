---
name: mac-remote
description: >-
  Driving a Mac from WSL over ssh: the retry pattern the flaky link needs, how to
  unlock the login keychain, and the wall you hit when a command needs the Mac's
  own login session rather than an ssh one. Use before running anything on the
  Mac, and whenever a remote command fails with "User interaction is not allowed",
  errSecInternalComponent, or an ssh timeout that looks like a command failure.
  Pairs with ios-build-deploy, which uses these scripts.
---

# The Mac, driven from WSL

Three things go wrong here, and each one looks like something else.

## 1. The link drops often

A single `ssh` call is not a reliable test of anything. Roughly one call in three
times out during the banner exchange. When that happens the output is empty and
the exit code is non-zero, which is exactly what a command that ran and printed
nothing looks like.

Use `scripts/mac-ssh`. It retries, and separates the two cases:

```sh
mac-ssh 'xcrun devicectl list devices'
mac-ssh -t 900 'xcodebuild ...'      # longer timeout for a build
mac-ssh -n 6 'something flaky'       # more attempts
```

Exit 69 means it never connected. Any other exit means the remote command ran.

Two habits that save the same trouble without the script:

- Write output to a file on the Mac first, then read the file in a separate
  call. A build that takes four minutes will not survive one ssh session, and
  its log is worth more than its exit code.
- Never conclude "the Mac says X" from one failed call. Check the message for
  `timed out`, `banner exchange` or `connection refused` first.

## 2. The keychain has two locks

```sh
scripts/mac-unlock-keychain
```

It does both halves:

- `security unlock-keychain` opens the keychain.
- `security set-key-partition-list` lets command line tools use a key in it
  without a prompt on screen.

The password comes from the secrets store, is passed on stdin rather than as an
argument, and is never printed.

`set-key-partition-list` is a standing change to the machine. It stops macOS
asking about that key again, for every tool, until the key is replaced. Say so
when you run it. It is the normal developer setup and it is still a change
someone should know was made on their behalf.

## 3. The login session ssh does not have

This is the one that wastes an afternoon.

An ssh session has no GUI security session. Anything that asks the keychain to
hand over a private key fails, however unlocked the keychain is. Code signing is
the case you will meet:

```
codesign ... : errSecInternalComponent
Command CodeSign failed with a nonzero exit code
```

The tell is this line, which you can get on demand:

```sh
mac-ssh 'security show-keychain-info ~/Library/Keychains/login.keychain-db'
# security: ... User interaction is not allowed.
```

Meanwhile `security find-identity -v -p codesigning` lists the identity without
complaint, which is why this reads as a signing configuration problem when it is
a session problem. The identity is fine. The session is not.

The fix is to run the command inside the login session:

```sh
scripts/mac-gui-run -t 1800 'cd /path/to/project && xcodebuild ...'
```

It writes a script on the Mac, has Terminal.app run it, and waits for the exit
code. Terminal is a GUI process, so the command gets the session it needs.

**The first call needs a person at the Mac.** macOS asks whether ssh may control
Terminal, and only someone sitting at the machine can allow it. Until they do,
`mac-gui-run` reports that nothing started rather than hanging. After the one
prompt it is unattended. Ask for that click early rather than after three
diagnostic rounds.

## Symptom to cause

| What you see | Which problem | What to do |
|---|---|---|
| Empty output, non-zero exit, `timed out` or `banner exchange` in the text | The link | Retry, or use `mac-ssh` |
| `User interaction is not allowed` | No login session | `mac-gui-run` |
| `errSecInternalComponent` from codesign | No login session | `mac-gui-run` |
| `The user name or passphrase you entered is not correct` | The keychain is locked | `mac-unlock-keychain` |
| A prompt appeared on the Mac and nothing moved | Waiting on a person | Ask them to allow it |

## Configuration

Host, user, project paths and device identifiers live in
`~/.config/mac-remote.env`, outside this repo, because this repo is public.
Every script here reads it and fails with a clear message when it is missing.
Override the path with `MAC_REMOTE_ENV`.

## File copies

`scp` uses the same connection and drops just as often, so retry it too. For
anything you generate, prefer writing it through `mac-ssh 'cat > /tmp/thing'`
with a heredoc: one round trip, and no second quoting layer to get wrong.
