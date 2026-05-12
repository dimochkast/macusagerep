#!/usr/bin/env bash
# Interactive setup: stores Telegram bot credentials in the macOS Keychain.
# No plaintext token in config files.
set -euo pipefail

SERVICE="macusagerep-telegram"

cat <<MSG
Telegram report setup
=====================
You will need:
  1. A bot token from @BotFather (create a bot, it gives you a token like
     123456789:AAH...).
  2. Your chat_id — open https://api.telegram.org/bot<TOKEN>/getUpdates after
     sending any message to your bot, find "chat":{"id":...} in the JSON.

PRIVACY NOTE: once enabled, a daily summary of your per-app active time will
be sent to Telegram's servers. Everything else stays local.
MSG

read -r -p "Bot token: " TOKEN
read -r -p "Chat ID:   " CHAT_ID

if [[ -z "$TOKEN" || -z "$CHAT_ID" ]]; then
    echo "Empty token or chat_id, aborting." >&2
    exit 1
fi

security delete-generic-password -s "$SERVICE" -a bot  >/dev/null 2>&1 || true
security delete-generic-password -s "$SERVICE" -a chat >/dev/null 2>&1 || true
security add-generic-password -s "$SERVICE" -a bot  -w "$TOKEN"
security add-generic-password -s "$SERVICE" -a chat -w "$CHAT_ID"

echo
echo "Optional: Anthropic API key for AI-generated summaries."
echo "  With a key set, the daily report will be a natural-language summary"
echo "  from Claude Haiku 4.5 instead of a plain list."
echo "  Leave blank to skip (plain list will be sent)."
read -r -p "Anthropic API key (sk-ant-...): " ANTHROPIC_KEY || true
if [[ -n "${ANTHROPIC_KEY:-}" ]]; then
    security delete-generic-password -s "$SERVICE" -a anthropic >/dev/null 2>&1 || true
    security add-generic-password -s "$SERVICE" -a anthropic -w "$ANTHROPIC_KEY"
    echo "Anthropic key stored."
else
    # If the user is re-running setup and wants to DISABLE AI, clear existing entry.
    security delete-generic-password -s "$SERVICE" -a anthropic >/dev/null 2>&1 || true
    echo "No Anthropic key set — reports will be plain lists."
fi

echo
echo "Stored in Keychain under service '$SERVICE'."
echo "Test delivery now:"
echo "  ./scripts/report-telegram.sh"
echo
echo "To schedule a daily 21:00 report:"
echo "  ./scripts/install-telegram-schedule.sh"
