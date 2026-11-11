#!/bin/bash
# Stop the agent and remove the app, CLI link and settings.
set -euo pipefail
launchctl bootout "gui/$(id -u)/dev.raimond.logifree.agent" 2>/dev/null || true
rm -rf "$HOME/Applications/Logifree.app" "$HOME/.local/bin/logifree" "$HOME/Library/Application Support/logifree"
echo "Removed. Optionally delete logifree-agent from System Settings → Privacy & Security."
