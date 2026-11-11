<img src="assets/icon.svg" width="64" height="64" alt="">

# logifree

A tiny replacement for Logi Options+, for the handful of things I actually use.

- **Scroll direction:** reverses the main wheel and thumb wheel in the mouse
  firmware (HID++ `0x2121` / `0x2150`), so the trackpad keeps macOS's natural
  scrolling and everything else about scrolling stays native.
- **Gesture button:** click or hold-and-swipe, mapped to Mission Control,
  desktops, a keyboard shortcut or a shell command.
- **Easy-Switch slots:** see, switch, rename and forget the host slots of the
  mouse and keyboard.
- Back/forward and everything else are left native.

Works over the Bolt receiver and direct Bluetooth. Devices forget these settings
when they sleep or reconnect, so the agent re-applies them whenever one connects.
macOS 27+.

## How it's built

`Logifree.app` is two programs:

- **`logifree-agent`**: headless, started by launchd at login (registered with
  `SMAppService`). Applies settings, handles the gesture button, idles at ~3 MB
  with nothing polling.
- **`Logifree`**: the SwiftUI settings window. Open it when you want to change
  something; closing it quits it.

They share `LogifreeCore` (HID++ and the settings model) and talk through
`~/Library/Application Support/logifree/settings.json` plus a Darwin
notification that tells the agent to reload.

## Install

```sh
scripts/install.sh      # build, sign, install to ~/Applications, link the CLI
```

Then in the app: turn on **Run in the background**, and grant **Accessibility**
to `logifree-agent` (gesture actions send keyboard shortcuts). Quit Logi
Options+ and OpenLogi first: they change the same device settings.

## CLI

```sh
logifree hosts                          # list Easy-Switch slots
logifree hosts switch keyboard 2
logifree hosts rename mouse 3 "Work laptop"
logifree hosts forget mouse 3
```

## Development

```sh
swift test
LOGIFREE_DEBUG=1 .build/release/logifree-agent   # foreground agent, prints every HID++ report
log stream --predicate 'subsystem == "local.logifree"'   # the installed agent's log
```

`scripts/uninstall.sh` removes everything.
