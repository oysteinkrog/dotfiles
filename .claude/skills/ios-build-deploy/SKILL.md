---
name: ios-build-deploy
description: >-
  Build, sign, install and test an iOS app on a Mac driven from WSL, without a
  person at the keyboard. Covers the simulator-first rule, the code signing
  failure that is really a session problem, why installing over Wi-Fi never
  works, and what each devicectl error code means. Use when building or
  deploying the phone app, when a build fails at CodeSign, when an install fails
  with 0xE8000003 or 0xE8000004, or when setting up automated phone testing.
  Depends on the mac-remote skill for the connection.
---

# Building and deploying the iOS app

Read `mac-remote` first if you have not. Every command here goes through its
scripts, and two of the three failures below are connection or session problems
wearing an Xcode error message.

## The order that saves time

```sh
ios-build sim        # does the code compile
ios-test             # do the tests pass
ios-build device     # does it sign
ios-install          # does it reach the phone
```

**Build for the simulator before the device, always.** It is the same compiler
over the same sources with none of the signing machinery. A simulator build that
succeeds proves the code is fine, so a device build that then fails is a signing
or session problem and you can stop reading Swift. Skipping this step turns a
five minute problem into an hour of reading the wrong log.

## Code signing failures

```
codesign ... : errSecInternalComponent
Command CodeSign failed with a nonzero exit code
```

This is not about certificates. An ssh session has no GUI security session, so
the keychain will not hand over the private key however unlocked it is.
`security find-identity -v -p codesigning` lists the identity perfectly, which
is what makes this so misleading.

```sh
mac-unlock-keychain      # both halves: unlock, and allow tools to use the key
ios-build device         # goes through mac-gui-run, which has the session
```

`ios-build device` already routes through the login session, so once the
keychain is set up it works unattended. The first time, macOS asks a person at
the Mac whether ssh may control Terminal. Ask for that click early.

## Install failures and the cable

```
ERROR: A connection to this device could not be established. (error 4000)
       Could not allocate a resource. (com.apple.mobiledevice error
       -402653181 (0xE8000003))
```

The device is connected over Wi-Fi. Check it directly:

```sh
mac-ssh 'xcrun devicectl device info details --device <udid> | grep -i transport'
# transportType: localNetwork      <- this never installs
# transportType: wired             <- this does
```

Installing a development build across the local-network tunnel fails every
time. Retrying does nothing. `ios-install` checks the transport first and waits
for USB rather than retrying something that cannot work, so you can start it
before the cable is plugged in and let it finish on its own.

## Error codes

| What you see | What it is | What to do |
|---|---|---|
| `errSecInternalComponent` at CodeSign | No GUI session | `mac-unlock-keychain`, then build via `mac-gui-run` |
| `0xE8000003`, "Could not allocate a resource" | Device is on Wi-Fi | Plug in the cable |
| `0xE8000004`, `12040`, `12010` | Developer disk image did not mount | Unlock the phone, replug, retry |
| "Developer Mode disabled" | Developer Mode off | Settings, Privacy and Security, Developer Mode |
| `devicectl` exits 0 but nothing installed | It does that | Read the output text, never the exit code |
| Empty test summary | The build failed before any test ran | `grep error: /tmp/ios-test.log` |

**`xcrun devicectl device install app` has exited 0 on a failed install.** Never
trust its exit code. `ios-install` greps the output, and so should anything else
that calls devicectl.

## Fully unattended runs

Everything except two one-time human actions:

- allowing ssh to control Terminal, once, at the Mac
- plugging the phone into USB, whenever it has been unplugged

After those, the four commands at the top run start to finish with nobody
watching. For a loop that reacts to the cable appearing, start `ios-install`
in the background before asking for the cable; it polls the transport and
installs the moment USB shows up.

## Things worth knowing

- **One derived data tree per destination:** sharing a tree between device and
  simulator makes each build rebuild the world. The config keeps them apart.
- **Write build output to a file on the Mac, then read the file.** A four minute
  build does not survive one ssh session, and the log outlives the connection.
- **`grep -c error:` on the log separates a compile failure from everything
  else.** Zero errors plus BUILD FAILED means the failure came after
  compilation, which is nearly always signing.
- Device identifiers, project paths and the simulator name live in
  `~/.config/mac-remote.env`, outside this repo, because this repo is public.
