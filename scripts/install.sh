#!/bin/bash
# Build, sign, install to ~/.local/bin/logifree and (re)start the LaunchAgent.
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL=local.logifree
BIN="$HOME/.local/bin/logifree"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/logifree.log"

swift build -c release
mkdir -p "$(dirname "$BIN")" "$(dirname "$PLIST")"
cp .build/release/logifree "$BIN"

# A stable signing identity keeps macOS permission grants across rebuilds.
CERT="${LOGIFREE_CERT:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)}"
if [ -n "$CERT" ]; then
    codesign --force --sign "$CERT" --identifier "$LABEL" "$BIN"
    echo "Signed with: $CERT"
else
    codesign --force --sign - --identifier "$LABEL" "$BIN"
    echo "Ad-hoc signed: you'll need to re-grant permissions after each rebuild."
fi

sed -e "s|__BIN__|$BIN|" -e "s|__LOG__|$LOG|" scripts/$LABEL.plist > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Running. Logs: tail -f $LOG"
