#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.macusagerep.agent.plist"
if [[ -f "$PLIST" ]]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
fi

rm -f "$HOME/bin/macusagerep-agent"

if [[ -d "/Applications/MacUsageRep.app" ]]; then
    sudo rm -rf "/Applications/MacUsageRep.app"
fi

pkill -f macusagerep-agent || true
osascript -e 'quit app "MacUsageRep"' 2>/dev/null || true

echo "Removed binaries, LaunchAgent and app."
echo "Database kept at ~/Library/Application Support/MacUsageRep/"
echo "Delete it manually if you want a clean slate:"
echo "  rm -rf ~/Library/Application\\ Support/MacUsageRep"
