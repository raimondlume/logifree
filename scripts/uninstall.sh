#!/bin/bash
set -euo pipefail
LABEL=local.logifree
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/logifree"
echo "Removed. Optionally delete logifree from System Settings → Privacy & Security."
