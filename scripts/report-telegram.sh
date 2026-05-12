#!/usr/bin/env bash
# Queries today's activity from the local SQLite DB and sends a summary
# to Telegram. Credentials come from the macOS Keychain (see telegram-setup.sh).
set -euo pipefail

SERVICE="macusagerep-telegram"
DB="$HOME/Library/Application Support/MacUsageRep/macusagerep.sqlite"

TOKEN=$(security find-generic-password -s "$SERVICE" -a bot  -w 2>/dev/null || true)
CHAT_ID=$(security find-generic-password -s "$SERVICE" -a chat -w 2>/dev/null || true)

if [[ -z "$TOKEN" || -z "$CHAT_ID" ]]; then
    echo "Missing Telegram credentials. Run ./scripts/telegram-setup.sh first." >&2
    exit 1
fi

if [[ ! -f "$DB" ]]; then
    echo "Database not found at $DB — is the agent running?" >&2
    exit 1
fi

DATE=$(date "+%Y-%m-%d")

# seconds → "Hh MMm" / "MMm SSs"
fmt_sec() {
    local s=$1 h m
    h=$((s / 3600))
    m=$(((s % 3600) / 60))
    local r=$((s % 60))
    if (( h > 0 )); then
        printf "%dh %02dm" "$h" "$m"
    elif (( m > 0 )); then
        printf "%dm %02ds" "$m" "$r"
    else
        printf "%ds" "$s"
    fi
}

# Pull raw rows (pipe-separated) from SQLite, single query.
ROWS=$(sqlite3 -separator '|' "$DB" <<SQL
SELECT app_name,
       CAST(SUM(end_ts - start_ts) AS INTEGER),
       SUM(key_count),
       SUM(mouse_count)
FROM active_intervals
WHERE start_ts >= strftime('%s', '$DATE 00:00:00')
  AND start_ts <  strftime('%s', '$DATE 00:00:00', '+1 day')
GROUP BY bundle_id
ORDER BY 2 DESC
LIMIT 10;
SQL
)

TOTAL=$(sqlite3 "$DB" "SELECT CAST(SUM(end_ts - start_ts) AS INTEGER)
                         FROM active_intervals
                        WHERE start_ts >= strftime('%s','$DATE 00:00:00')
                          AND start_ts <  strftime('%s','$DATE 00:00:00','+1 day');")
TOTAL=${TOTAL:-0}

MSG="📊 MacUsageRep — $DATE"$'\n'

if [[ -z "$ROWS" ]]; then
    MSG+=$'\n''No activity recorded today.'
else
    MSG+=$'\n'
    while IFS='|' read -r name sec keys mouse; do
        [[ -z "$name" ]] && continue
        MSG+=$(printf "• %s — %s · %s keys · %s mouse\n" \
            "$name" "$(fmt_sec "$sec")" "$keys" "$mouse")
        MSG+=$'\n'
    done <<< "$ROWS"
    MSG+=$'\n'"Total active: $(fmt_sec "$TOTAL")"
fi

# If an Anthropic key is configured (and the user hasn't opted out via
# MACUSAGEREP_NO_AI=1), replace the plain list with a natural-language summary
# from Claude Haiku 4.5. Failure of the API call keeps the plain list as a
# safe fallback so the cron never goes silent.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "${MACUSAGEREP_NO_AI:-}" != "1" ]] && command -v python3 >/dev/null 2>&1; then
    if AI_MSG=$("$SCRIPT_DIR/anthropic-summary.py" 2>>/tmp/macusagerep-telegram.err.log); then
        if [[ -n "$AI_MSG" ]]; then
            MSG="$AI_MSG"
        fi
    fi
fi

RESPONSE=$(curl -fsS "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${MSG}" \
    --data-urlencode "disable_web_page_preview=true" 2>&1) || {
    echo "Telegram API error: $RESPONSE" >&2
    exit 1
}

echo "Sent."
