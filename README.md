# macusagerep

macOS Active-Usage Tracker — per-application time measured only while the
keyboard or mouse is actually being used. See `Docs/concept.pdf` for the
design paper.

## Layout

```
Package.swift
Sources/
  MacUsageRepCore/         # Core library: models, DB, collectors, aggregator, reporting
    Models/                ActiveInterval, EventRecord, AppMetadata
    Collector/             CGEventTap, NSWorkspace, IOKit idle
    Aggregator/            Heartbeat algorithm
    Store/                 GRDB + SQLite schema
    Reporting/             Today/week queries + CSV/JSON export
    TrackerService.swift   Wiring for the agent
  MacUsageRepAgent/        LaunchAgent executable (background daemon)
  MacUsageRepApp/          SwiftUI menu-bar app + dashboard
Tests/MacUsageRepCoreTests # XCTest for the aggregator state machine
Resources/                 LaunchAgent plist template
```

## Build

```bash
# first time on a fresh macOS
sudo xcodebuild -license

swift build
swift test
```

Run the agent (will prompt for **Input Monitoring** and **Accessibility**
permissions on first launch):

```bash
swift run macusagerep-agent
```

Run the menu-bar app in parallel:

```bash
swift run macusagerep
```

## Install as LaunchAgent

```bash
swift build -c release
sudo install -m 755 .build/release/macusagerep-agent /usr/local/bin/
cp Resources/com.macusagerep.agent.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.macusagerep.agent.plist
```

## Data location

`~/Library/Application Support/MacUsageRep/macusagerep.sqlite`

Retention defaults: raw events 7 days, intervals 180 days, daily totals kept
indefinitely. Change in `Config.default`.

## Status

Skeleton is complete: heartbeat aggregator, event tap, workspace monitor,
idle monitor, SQLite store with migrations, reporting engine, SwiftUI
menu-bar shell. Not yet done: settings UI, exclusion management UI,
SQLCipher build, window-title capture, iCloud sync, Shortcuts integration.
