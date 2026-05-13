# macusagerep

macOS active-usage tracker — Swift Package, который считает время в
приложениях **только пока пользователь реально печатает или кликает**,
а не пока окно просто открыто.

Состоит из трёх частей: фоновый агент (LaunchAgent), SQLite-хранилище
и menu-bar приложение на SwiftUI.


## Stack

- Swift 5.10, macOS 13+
- GRDB 6.29 поверх SQLite (`Database.swift`, `Schema.swift`)
- SwiftUI `MenuBarExtra` + Swift Charts (Dashboard)
- AppKit / CoreGraphics: `CGEventTap` для глобальных HID-событий
- IOKit для системного idle time
- LaunchAgent через launchd (фоновый запуск)


## Команды

```bash
swift build               # debug-сборка
swift build -c release    # release
swift test                # unit-тесты (Tests/MacUsageRepCoreTests)
./scripts/install.sh      # упаковка в .app + установка LaunchAgent
./scripts/make-app-bundle.sh  # только пересобрать MacUsageRep.app
```

Расположения после install:
- `/Applications/MacUsageRep.app` — menu-bar UI
- `~/bin/macusagerep-agent` — фоновый агент
- `~/Library/LaunchAgents/com.macusagerep.agent.plist` — автозапуск
- `~/Library/Application Support/MacUsageRep/macusagerep.sqlite` — БД


## Архитектура

```
CGEventTap ──┐
NSWorkspace ─┼──► InputCounters ──► SessionAggregator ──► Database (SQLite)
IOKit idle ──┘                       (heartbeat 1s,         events
                                      flush 30s)            active_intervals
ResourceSampler ─────────────► resource_samples              resource_samples
                                                             apps
ReportingEngine ◄──────────── Database
   │
   ├─► MenuBarView (today top-5)
   ├─► DashboardView (Today / Week / Resources tabs)
   └─► scripts/report-telegram.sh + anthropic-summary.py
```

Ключевые файлы:
- `Sources/MacUsageRepCore/Aggregator/SessionAggregator.swift` — main loop
- `Sources/MacUsageRepCore/Collector/` — все источники сигналов
- `Sources/MacUsageRepCore/Store/Schema.swift` — миграции (v1, v2, v3)
- `Sources/MacUsageRepAgent/AgentMain.swift` — entry point демона


## Конвенции

- **Conventional Commits:** `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`.
- **Ветки:** `feat/...`, `fix/...`, `chore/...`, `docs/...`.
- **PR:** squash merge через `gh pr merge --squash --delete-branch`.
- **Тесты** обязательны для логики в `SessionAggregator` и `Database`.
  Расположение: `Tests/MacUsageRepCoreTests/`.
- **Не коммитить:** `.build/`, `.swiftpm/`, `Package.resolved`,
  `__pycache__/`, `*.pyc` (в `.gitignore`).


## Доменные термины

- **Active interval** — непрерывный отрезок времени, пока (a) фронтальное
  приложение не менялось и (b) в течение последних 30 секунд (`idleCutoff`)
  был хотя бы один HID-эвент.
- **Heartbeat** — таймер на 1 секунду, который сводит drain-счётчики
  и состояние workspace в открытый интервал.
- **Flush** — периодическая запись открытого интервала в БД для
  crash-safety. Должна быть **UPDATE существующей строки**, не INSERT
  (см. ниже).


## Важные нюансы и инварианты

### SessionAggregator FLUSH = UPDATE, не INSERT
До миграции v3 каждый flush делал `INSERT`, что давало N строк с
одинаковым `start_ts` и растущим `end_ts`. `SUM(end_ts - start_ts)` потом
double-counted активное время (×N по числу flushes за сессию).

Фикс: `IntervalSink.persist` возвращает row id; агрегатор запоминает его
и переиспользует. Миграция `v3_dedupe_flush_duplicates` чистит историю.

**Никогда** не возвращайся к INSERT в `flush`. Регрессионный тест:
`testFlushDoesNotCreateDuplicateRows` в `SessionAggregatorTests.swift`.

### IDLE_CUTOFF = 30 секунд
Компромисс между «реальным временем» (10 с — пропустит чтение) и
расслабленностью (60 с — раздуется). 30 с зашит в `Config.default` и
тестах. Менять — только с обновлением всех тестов.

### Mouse threshold = 4 пикселя
Случайные подёргивания мыши не считаются за активность. Порог в
`Config.mouseMoveThreshold`.

### Privacy
- Никакого keylogging. Записываем только **счётчики** событий и timestamp.
- Конкретные нажатия клавиш или текст никогда не покидают `CGEventTap`.
- Bundle ID можно исключить через таблицу `apps` (поле `excluded`).


## Telegram-отчёты и Claude API

`scripts/report-telegram.sh` шлёт ежедневную сводку в Telegram.
Креды (bot token, chat_id, Anthropic API key) — в Keychain под service
`macusagerep-telegram`. Установка: `./scripts/telegram-setup.sh`.

Если есть Anthropic API key — `scripts/anthropic-summary.py` (stdlib, без pip)
вызывает Claude Haiku 4.5 и присылает natural-language сводку вместо
плоского списка. При сбое — fallback на простой список, cron не молчит.

Расписание: `./scripts/install-telegram-schedule.sh [HOUR] [MINUTE]`
(дефолт 21:00) — ставит LaunchAgent.


## Permissions (TCC)

Агент требует:
- **Input Monitoring** — для `CGEventTap` (отслеживание HID-эвентов)
- **Accessibility** — для того же
- *(опционально)* **Screen Recording** — для window-level granularity
  (не реализовано, в roadmap)


## Roadmap

- Settings UI (исключения, retention) — сейчас только через SQL
- Window-title capture (нужен Screen Recording permission)
- SQLCipher build (опционально, ключ в Keychain)
- iCloud sync
- Shortcuts / CLI для интеграций
