#!/bin/bash
# Build Logifree.app (settings window + embedded agent), sign it, install it to
# ~/Applications, link the CLI and restart the agent if it's enabled.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Logifree.app"
STAGE=.build/Logifree.app
AGENT=local.logifree.agent

swift build -c release

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" "$STAGE/Contents/Library/LaunchAgents"
cp .build/release/Logifree .build/release/logifree-agent "$STAGE/Contents/MacOS/"
cp scripts/Info.plist "$STAGE/Contents/"
cp scripts/$AGENT.plist "$STAGE/Contents/Library/LaunchAgents/"
cp assets/AppIcon.icns "$STAGE/Contents/Resources/"

# A stable signing identity keeps macOS permission grants across rebuilds.
CERT="${LOGIFREE_CERT:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)}"
CERT="${CERT:--}"
codesign --force --sign "$CERT" --identifier "$AGENT" "$STAGE/Contents/MacOS/logifree-agent"
codesign --force --sign "$CERT" "$STAGE"
[ "$CERT" = "-" ] && echo "Ad-hoc signed: permissions must be re-granted after each rebuild."

mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto "$STAGE" "$APP"

mkdir -p "$HOME/.local/bin"
ln -sf "$APP/Contents/MacOS/logifree-agent" "$HOME/.local/bin/logifree"

# Pick up the new binary if the agent is already enabled (no-op otherwise).
launchctl kickstart -k "gui/$(id -u)/$AGENT" 2>/dev/null || true

echo "Installed $APP"
open "$APP"
