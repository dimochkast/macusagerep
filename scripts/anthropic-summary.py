#!/usr/bin/env python3
"""Generate a natural-language daily activity summary via Claude API.

Reads today's activity from the local SQLite DB, sends it to Claude Haiku 4.5,
prints the summary to stdout. Stdlib only — no pip dependencies.

Exit codes:
  0  ok (summary printed)
  1  configuration error (missing key / missing DB)
  2  API error
  3  unexpected response shape
"""
import json
import os
import sqlite3
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

KEYCHAIN_SERVICE = "macusagerep-telegram"
DB_PATH = Path.home() / "Library/Application Support/MacUsageRep/macusagerep.sqlite"
MODEL = "claude-haiku-4-5"
MAX_TOKENS = 1024
API_URL = "https://api.anthropic.com/v1/messages"

SYSTEM_PROMPT = """Ты пишешь краткую сводку продуктивности за день для личного macOS-трекера.
На входе — JSON с приложениями, активным временем в секундах, счётчиками нажатий клавиш и событий мыши.

Формат ответа (русский):
1) Первая строка: 📊 MacUsageRep — <дата>
2) Пустая строка
3) 1-2 предложения живым языком: чем пользователь занимался (опирайся на приложения с наибольшим временем; выводы должны логично следовать из данных).
4) Пустая строка
5) Маркированный список топ-5 приложений в формате:
   • <App> — <время> · <N> keys · <M> mouse
6) Пустая строка
7) Последняя строка: "Всего активно: <время>"

Формат времени: "2h 15m", "45m 12s" или "23s".
Будь краток и конкретен. Ничего не выдумывай сверх входных данных. Только сводку, без вступлений типа «вот ваш отчёт»."""


def keychain_secret(account: str) -> str | None:
    try:
        out = subprocess.check_output(
            ["security", "find-generic-password",
             "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
            stderr=subprocess.DEVNULL,
        )
        return out.decode().strip() or None
    except subprocess.CalledProcessError:
        return None


def fetch_activity(db_path: Path, day: date) -> dict:
    start = datetime.combine(day, datetime.min.time()).timestamp()
    end = datetime.combine(day + timedelta(days=1), datetime.min.time()).timestamp()
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            """
            SELECT app_name,
                   CAST(SUM(end_ts - start_ts) AS INTEGER),
                   SUM(key_count),
                   SUM(mouse_count)
            FROM active_intervals
            WHERE start_ts >= ? AND start_ts < ?
            GROUP BY bundle_id
            ORDER BY 2 DESC
            LIMIT 10
            """,
            (start, end),
        ).fetchall()
        total_row = conn.execute(
            "SELECT CAST(SUM(end_ts - start_ts) AS INTEGER) "
            "FROM active_intervals WHERE start_ts >= ? AND start_ts < ?",
            (start, end),
        ).fetchone()
    finally:
        conn.close()

    total = int(total_row[0] or 0)
    return {
        "date": day.isoformat(),
        "total_active_seconds": total,
        "apps": [
            {
                "app": r[0],
                "active_seconds": int(r[1] or 0),
                "keys": int(r[2] or 0),
                "mouse": int(r[3] or 0),
            }
            for r in rows
        ],
    }


def call_claude(api_key: str, activity: dict) -> str:
    body = {
        "model": MODEL,
        "max_tokens": MAX_TOKENS,
        "system": SYSTEM_PROMPT,
        "messages": [{
            "role": "user",
            "content": "Данные за сегодня:\n\n" + json.dumps(activity, ensure_ascii=False, indent=2),
        }],
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"Claude API HTTP {e.code}: {err_body}", file=sys.stderr)
        sys.exit(2)
    except urllib.error.URLError as e:
        print(f"Claude API network error: {e.reason}", file=sys.stderr)
        sys.exit(2)

    for block in payload.get("content", []):
        if block.get("type") == "text":
            text = block.get("text", "").strip()
            if text:
                return text
    print(f"Claude returned no text block: {json.dumps(payload)[:300]}", file=sys.stderr)
    sys.exit(3)


def main() -> None:
    api_key = os.environ.get("ANTHROPIC_API_KEY") or keychain_secret("anthropic")
    if not api_key:
        print("ANTHROPIC_API_KEY not in env or Keychain — run telegram-setup.sh",
              file=sys.stderr)
        sys.exit(1)
    if not DB_PATH.exists():
        print(f"DB not found at {DB_PATH}", file=sys.stderr)
        sys.exit(1)

    activity = fetch_activity(DB_PATH, date.today())
    if not activity["apps"]:
        print(f"📊 MacUsageRep — {activity['date']}\n\nСегодня активности не зафиксировано.")
        return

    print(call_claude(api_key, activity))


if __name__ == "__main__":
    main()
