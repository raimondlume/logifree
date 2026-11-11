#!/bin/bash
# Stop the agent and remove the app and its settings.
set -euo pipefail
launchctl bootout "gui/$(id -u)/dev.raimond.logifree.agent" 2>/dev/null || true
rm -rf "$HOME/Applications/Logifree.app" "$HOME/Library/Application Support/logifree"
echo "Removed. Optionally remove Logifree and Logifree Agent from System Settings → Privacy & Security."
