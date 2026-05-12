#!/usr/bin/env bash
# Installs a LaunchAgent that runs report-telegram.sh every day at 21:00.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
PLIST="$HOME/Library/LaunchAgents/com.macusagerep.telegram.plist"

HOUR=${1:-21}
MINUTE=${2:-0}

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.macusagerep.telegram</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$ROOT/scripts/report-telegram.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>$HOUR</integer>
        <key>Minute</key><integer>$MINUTE</integer>
    </dict>
    <key>StandardOutPath</key><string>/tmp/macusagerep-telegram.out.log</string>
    <key>StandardErrorPath</key><string>/tmp/macusagerep-telegram.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Scheduled daily Telegram report at ${HOUR}:$(printf '%02d' "$MINUTE")."
echo "Plist: $PLIST"
echo "Logs:  /tmp/macusagerep-telegram.{out,err}.log"
echo
echo "Change time by re-running:  ./scripts/install-telegram-schedule.sh 9 30"
echo "Uninstall:                  launchctl unload $PLIST && rm $PLIST"
