#!/bin/bash
# Build Logifree.app (settings window + embedded Logifree Agent.app), sign it, install it to
# ~/Applications and restart the agent if it's enabled.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Logifree.app"
STAGE=.build/Logifree.app
AGENT=dev.raimond.logifree.agent
HELPER="$STAGE/Contents/Library/LoginItems/Logifree Agent.app"

swift build -c release

rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" "$STAGE/Contents/Library/LaunchAgents" \
  "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"
cp .build/release/Logifree "$STAGE/Contents/MacOS/"
cp .build/release/logifree-agent "$HELPER/Contents/MacOS/"
cp scripts/Info.plist "$STAGE/Contents/"
cp scripts/Agent-Info.plist "$HELPER/Contents/Info.plist"
cp scripts/$AGENT.plist "$STAGE/Contents/Library/LaunchAgents/"
# Compile the Icon Composer icon: Assets.car for macOS 27, AppIcon.icns as fallback.
xcrun actool assets/AppIcon.icon --compile "$STAGE/Contents/Resources" \
  --app-icon AppIcon --platform macosx --minimum-deployment-target 27.0 \
  --output-partial-info-plist .build/AppIcon-partial.plist >/dev/null
# actool exits 0 even when it compiles nothing.
[ -f "$STAGE/Contents/Resources/Assets.car" ] || { echo "actool didn't compile assets/AppIcon.icon" >&2; exit 1; }
cp "$STAGE/Contents/Resources/"{Assets.car,AppIcon.icns} "$HELPER/Contents/Resources/"

# A stable signing identity keeps macOS permission grants across rebuilds.
CERT="${LOGIFREE_CERT:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)}"
CERT="${CERT:--}"
codesign --force --sign "$CERT" "$HELPER"
codesign --force --sign "$CERT" "$STAGE"
[ "$CERT" = "-" ] && echo "Ad-hoc signed: permissions must be re-granted after each rebuild."

mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto "$STAGE" "$APP"


# Pick up the new binary if the agent is already enabled (no-op otherwise).
launchctl kickstart -k "gui/$(id -u)/$AGENT" 2>/dev/null || true

echo "Installed $APP"
open "$APP"
