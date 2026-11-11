<img src="assets/icon.png" width="64" height="64" alt="">

# Logifree

Logifree is a tiny native macOS 27 replacement for Logi Options+, built for the handful of things I actually use. It works with Logitech devices over a Bolt receiver or direct Bluetooth.

A background login item, Logifree Agent, idles at around 4 MB. The SwiftUI settings window only runs when you open it; closing the window quits it. For comparison, Logi Options+ and alternatives like OpenLogi idle at around 150–200 MB.

<img src="https://github.com/user-attachments/assets/44cc101e-62df-4a77-9d0a-b4884829e535" width="540" alt="Logifree window: agent status and the Easy-Switch channels of a mouse and keyboard">

## What it does

- Reverse the scroll wheel and thumb wheel in the mouse firmware, independently of the trackpad.
- Set a minimum distance per scroll-wheel click: macOS default, 2 lines or 3 lines. Faster scrolling keeps macOS's acceleration.
- Map a gesture button click or swipe to Mission Control, App Exposé, desktops, a keyboard shortcut or a shell command.
- See the Easy-Switch channels on your mouse and keyboard, including their computer names and Bolt or Bluetooth connection. Switch, rename or forget channels where the device allows it. The view updates as devices change.
- Remap keys on every keyboard using macOS's own `UserKeyMapping`. The collapsed Advanced section can, for example, turn § into F18 for a global shortcut.
- Quit the agent and settings app together from the window, restoring connected devices.

The agent reapplies device settings when devices reconnect. Back and forward buttons and other native behavior are left alone.

<img src="https://github.com/user-attachments/assets/a937f6ba-076e-4812-a74c-c20942f1a1bd" width="540" alt="Logifree window: scrolling, gesture button and key remap settings">

## Install

There is no notarized release. The easiest way to install is to clone the repo and run the script, or ask your coding agent to do it. You need macOS 27 and Xcode 27 (or its command line tools).

```sh
git clone https://github.com/raimondlume/logifree && cd logifree
scripts/install.sh
```

The script builds and signs the app, installs it in `~/Applications`, and links the CLI. Then in the app:

1. Turn on **Start at login**, and approve it in System Settings if asked.
2. Grant **Input Monitoring** to **Logifree** when asked, so it can find your devices.
3. Grant **Accessibility** to **Logifree Agent**, so gesture actions can send shortcuts and the scroll distance applies. **Grant Access…** opens the list and lets you drag the agent into it.

Quit Logi Options+ and OpenLogi first: they change the same device settings.

The script signs with your first Apple Development certificate, if available. Set `LOGIFREE_CERT` to choose another. Without one, it signs ad hoc; macOS forgets the permissions after each rebuild.

## CLI

```sh
logifree hosts                          # list Easy-Switch channels
logifree hosts switch keyboard 2
logifree hosts rename mouse 3 "Work laptop"
logifree hosts forget mouse 3
```

## How it's built

`Logifree.app` contains a SwiftUI settings app and the headless `Logifree Agent.app` login item, registered with `SMAppService`. They share `LogifreeCore` for HID++ and the settings model. Settings live in `~/Library/Application Support/logifree/settings.json`; a Darwin notification tells the agent to reload them. The agent waits for events rather than polling.

## Development

```sh
swift test
LOGIFREE_DEBUG=1 .build/release/logifree-agent   # foreground agent; prints HID++ reports
log stream --predicate 'subsystem == "dev.raimond.logifree"'   # installed agent's log
```

`scripts/uninstall.sh` removes everything.
