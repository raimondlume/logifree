<img src="assets/icon.svg" width="64" height="64" alt="">

# logifree

A tiny replacement for Logi Options+, for the handful of things I actually use.
One dependency-free Swift binary, run by launchd, idles in the run loop.

- **Scroll direction:** reverses the main wheel and thumb wheel in the mouse
  firmware (HID++ `0x2121` / `0x2150`), so the trackpad keeps macOS's natural
  scrolling and everything else about scrolling stays native.
- **Gesture button:** click or hold-and-swipe, mapped to actions in
  [`Config.swift`](Sources/logifree/Config.swift).
- **Easy-Switch slots:** `logifree hosts` lists, switches, renames and forgets
  the host slots of the mouse and keyboard.
- Back/forward and everything else are left native.

Works over the Bolt receiver and direct Bluetooth. Devices forget these settings
when they sleep or reconnect, so logifree re-applies them whenever one connects.

## Install

```sh
scripts/install.sh            # build, sign, install the LaunchAgent, start it
tail -f ~/Library/Logs/logifree.log
```

Quit Logi Options+ and OpenLogi first: they change the same device settings.

Permissions (System Settings → Privacy & Security): **Accessibility** for gesture
actions (they send keyboard shortcuts), and possibly **Input Monitoring** if the
log says it can't open HID devices. Grant them to `~/.local/bin/logifree`, then
`launchctl kickstart -k gui/$(id -u)/local.logifree`.

## Use

```sh
logifree hosts                          # list Easy-Switch slots
logifree hosts switch keyboard 2
logifree hosts rename mouse 3 "Work laptop"
logifree hosts forget mouse 3
```

Change mappings in `Sources/logifree/Config.swift`, then rerun `scripts/install.sh`.

Debugging: `LOGIFREE_DEBUG=1 .build/release/logifree` runs the agent in the
foreground and prints every HID++ report.

`scripts/uninstall.sh` removes everything.
