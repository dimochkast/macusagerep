#!/usr/bin/env bash
# One-shot installer: builds everything, wraps the menu-bar app into a proper
# .app bundle, copies it to /Applications, installs the agent binary to
# ~/bin and registers it as a LaunchAgent that starts at login.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if ! command -v swift >/dev/null 2>&1; then
    echo "Swift not found. Install Xcode from the App Store, then run:" >&2
    echo "  sudo xcodebuild -license accept" >&2
    exit 1
fi

if ! swift --version >/dev/null 2>&1; then
    echo "Xcode license not accepted. Run:" >&2
    echo "  sudo xcodebuild -license accept" >&2
    exit 1
fi

echo "==> Building release binaries (this takes ~1 minute the first time)"
swift build -c release

echo "==> Packaging MacUsageRep.app"
"$ROOT/scripts/make-app-bundle.sh"

echo "==> Installing MacUsageRep.app to /Applications (will ask for sudo)"
sudo rm -rf "/Applications/MacUsageRep.app"
sudo cp -R "$ROOT/.build/MacUsageRep.app" "/Applications/MacUsageRep.app"

echo "==> Installing agent binary to ~/bin/macusagerep-agent"
mkdir -p "$HOME/bin"
cp "$ROOT/.build/release/macusagerep-agent" "$HOME/bin/macusagerep-agent"
chmod +x "$HOME/bin/macusagerep-agent"

echo "==> Installing LaunchAgent plist to ~/Library/LaunchAgents"
PLIST="$HOME/Library/LaunchAgents/com.macusagerep.agent.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.macusagerep.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/bin/macusagerep-agent</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>/tmp/macusagerep-agent.out.log</string>
    <key>StandardErrorPath</key><string>/tmp/macusagerep-agent.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "==> Launching menu-bar app"
open "/Applications/MacUsageRep.app"

cat <<DONE

Installed.

What happens now:
  * Background agent is running and will auto-start at every login.
  * Menu-bar icon (clock with checkmark) is in the top-right of the screen.
  * On first run, macOS will ask for Input Monitoring and Accessibility
    permissions. Grant both — the agent cannot count keystrokes/clicks
    without them.

Data location:
  ~/Library/Application Support/MacUsageRep/macusagerep.sqlite
  Agent logs: /tmp/macusagerep-agent.{out,err}.log

Uninstall: run scripts/uninstall.sh

DONE
