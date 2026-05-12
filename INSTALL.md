# MacUsageRep — installation guide

A macOS background tracker that counts per-application time **only while you
are actually typing or clicking**. No keylogging — it records event counts and
timestamps, never key content. Data stays on the local machine.

## Requirements

- macOS 13 (Ventura) or newer
- Xcode 15 or newer — install from the **Mac App Store**
- After Xcode is installed, accept the license once:
  ```bash
  sudo xcodebuild -license accept
  ```

## One-shot install

From the project folder:

```bash
cd /path/to/macusagerep
./scripts/install.sh
```

The script will:

1. Build release binaries (~1 minute first time).
2. Wrap the menu-bar app into `MacUsageRep.app` and copy it to `/Applications`
   (asks for `sudo`).
3. Copy the background agent to `~/bin/macusagerep-agent`.
4. Install a LaunchAgent at `~/Library/LaunchAgents/com.macusagerep.agent.plist`
   so the agent auto-starts at every login.
5. Launch the menu-bar app.

## First run — grant permissions

macOS will show system dialogs for two permissions. **Both are required —
without them the agent can't count keystrokes or clicks:**

1. **Input Monitoring** — System Settings → Privacy & Security → Input Monitoring → enable `macusagerep-agent`.
2. **Accessibility** — System Settings → Privacy & Security → Accessibility → enable `macusagerep-agent`.

After toggling permissions, reload the agent so it picks up the new grants:

```bash
launchctl kickstart -k gui/$(id -u)/com.macusagerep.agent
```

## Where is what

| Thing | Path |
|---|---|
| Menu-bar app | `/Applications/MacUsageRep.app` |
| Background agent | `~/bin/macusagerep-agent` |
| LaunchAgent plist | `~/Library/LaunchAgents/com.macusagerep.agent.plist` |
| Database | `~/Library/Application Support/MacUsageRep/macusagerep.sqlite` |
| Agent logs | `/tmp/macusagerep-agent.out.log` and `.err.log` |

## Daily usage

- The menu-bar icon (🕒 with a checkmark) lives in the top-right bar.
- Click it → **Today — top 5** panel with per-app active time.
- **Dashboard** button → window with three tabs:
  - **Today** — bar chart + table of active time per app since midnight.
  - **Week** — the same for the last 7 days.
  - **Resources** — average and peak CPU% plus average and peak RAM per app,
    sampled every 10 seconds by the agent.
- **Quit** stops only the menu-bar app; the agent keeps recording in the
  background.

## What is actually collected

| Source | What | How often |
|---|---|---|
| `CGEventTap` | key-down / mouse-down / scroll / significant mouse move — **counts only, no key codes or payload** | real time |
| `NSWorkspace` | which app is frontmost | on switch |
| `IOKit HIDIdleTime` | system idle time (second opinion for idle detection) | every second |
| `proc_pidinfo` | per-process CPU time + resident memory, grouped by bundle_id | every 10 seconds |

An **active interval** is written only when the user actually produces input
in the focused app within the 30-second idle cutoff. Walk away → the interval
closes, and its end time is clamped to the last real input. Wall-clock time
with no typing never counts.

## Privacy

- The agent stores **counts only** (how many key events, how many mouse
  events) and timestamps. It never records which keys were pressed.
- Database is on your Mac. Nothing is sent anywhere.
- To stop recording for specific apps, add their bundle IDs to the `apps`
  table with `excluded = 1`:
  ```bash
  sqlite3 ~/Library/Application\ Support/MacUsageRep/macusagerep.sqlite \
      "INSERT OR REPLACE INTO apps (bundle_id, display_name, excluded) VALUES ('com.1password.1password', '1Password', 1);"
  ```

## Daily Telegram report (optional)

Sends a plain-text summary of today's top 10 apps to your Telegram every
evening. **Opt-in** — the default install is local-only.

### Setup

1. Create a bot via [@BotFather](https://t.me/BotFather) → copy the token.
2. Send any message to your bot, then open
   `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser and find
   `"chat":{"id":...}` — that's your chat_id.
3. (Optional) Get an Anthropic API key from
   [console.anthropic.com](https://console.anthropic.com) → API Keys → Create Key.
   With a key configured, the daily report becomes a natural-language summary
   written by Claude Haiku 4.5 instead of a plain list. Costs roughly fractions
   of a cent per day.
4. Store all credentials in the macOS Keychain:
   ```bash
   ./scripts/telegram-setup.sh
   ```
   The prompt will ask for the Anthropic key last — leave blank to skip.
5. Test delivery:
   ```bash
   ./scripts/report-telegram.sh
   ```
6. Schedule daily at 21:00 (or pick your hour/minute):
   ```bash
   ./scripts/install-telegram-schedule.sh         # 21:00 by default
   ./scripts/install-telegram-schedule.sh 9 30    # 09:30
   ```

To force the plain list even when an Anthropic key is set:
`MACUSAGEREP_NO_AI=1 ./scripts/report-telegram.sh`.

If the Claude call fails for any reason (network, invalid key, API outage),
the script automatically falls back to the plain list so the daily cron never
goes silent. Errors land in `/tmp/macusagerep-telegram.err.log`.

### What gets sent

**Without an Anthropic key** — plain English list:

```
📊 MacUsageRep — 2026-04-17

• Terminal  — 2h 50m  · 1485 keys · 6131 mouse
• Safari    —   42m 13s  · 128 keys · 1034 mouse
...

Total active: 4h 09m
```

**With an Anthropic key** — Claude-generated Russian summary with a 1-2
sentence narrative ("В основном работа в терминале, немного браузера и
Telegram…") plus the top-5 list and total.

No keystroke content, no CPU/RAM details — only app names, active time and
event counts. Data goes to Telegram's servers; with the AI summary enabled,
the same numbers are also sent to Anthropic's servers. Turn either off if
that isn't acceptable.

### Uninstall Telegram part only

```bash
launchctl unload ~/Library/LaunchAgents/com.macusagerep.telegram.plist
rm ~/Library/LaunchAgents/com.macusagerep.telegram.plist
security delete-generic-password -s macusagerep-telegram -a bot
security delete-generic-password -s macusagerep-telegram -a chat
security delete-generic-password -s macusagerep-telegram -a anthropic  # only if set
```

## Uninstall

```bash
./scripts/uninstall.sh
```

Removes the agent, LaunchAgent plist, and `/Applications/MacUsageRep.app`.
Keeps the database — delete it manually if you want a clean slate:

```bash
rm -rf ~/Library/Application\ Support/MacUsageRep
```

## Troubleshooting

- **No menu-bar icon:** launch once from `/Applications/MacUsageRep.app`.
  SwiftUI `MenuBarExtra` needs the real `.app` bundle — `swift run` won't
  register the icon.
- **Menu shows "No activity yet" even after a while:** permissions probably
  weren't granted. Check Privacy & Security → Input Monitoring + Accessibility.
  After enabling, run
  `launchctl kickstart -k gui/$(id -u)/com.macusagerep.agent`.
- **Agent not running:** `ps aux | grep macusagerep-agent`. If missing,
  reload: `launchctl load ~/Library/LaunchAgents/com.macusagerep.agent.plist`.
- **Check stored data manually:**
  ```bash
  # Active time per app
  sqlite3 ~/Library/Application\ Support/MacUsageRep/macusagerep.sqlite \
      "SELECT app_name, CAST(SUM(end_ts - start_ts) AS INTEGER) AS sec,
              SUM(key_count) AS keys, SUM(mouse_count) AS mouse
       FROM active_intervals GROUP BY bundle_id ORDER BY sec DESC;"

  # CPU / RAM per app today
  sqlite3 ~/Library/Application\ Support/MacUsageRep/macusagerep.sqlite \
      "SELECT app_name,
              ROUND(AVG(cpu_percent),1) AS avg_cpu,
              ROUND(MAX(cpu_percent),1) AS peak_cpu,
              ROUND(AVG(memory_bytes)/1048576.0,0) AS avg_mb
       FROM resource_samples
       WHERE timestamp > strftime('%s','now','start of day')
       GROUP BY bundle_id ORDER BY avg_cpu DESC LIMIT 20;"
  ```
