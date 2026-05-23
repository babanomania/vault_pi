#!/bin/bash
# Telegram notification helper. Sourced by the other scripts.
# Reads bot token + chat id from Docker secret files; silently no-ops if
# either is missing or empty.

notify() {
  local msg="$1"
  local token_file=/run/secrets/telegram_token
  local chatid_file=/run/secrets/telegram_chatid

  if [ ! -s "$token_file" ] || [ ! -s "$chatid_file" ]; then
    echo "[notify] (telegram not configured) $msg"
    return 0
  fi

  local token chatid host
  token="$(cat "$token_file")"
  chatid="$(cat "$chatid_file")"
  host="$(hostname)"

  # Telegram has occasional transient 5xx; don't let a notify failure kill
  # the actual backup.
  curl -s --max-time 15 -X POST \
       --data-urlencode "chat_id=${chatid}" \
       --data-urlencode "text=[${host}] ${msg}" \
       "https://api.telegram.org/bot${token}/sendMessage" \
       >/dev/null 2>&1 || true

  echo "[notify] ${msg}"
}
