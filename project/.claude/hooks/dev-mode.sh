#!/usr/bin/env bash
# UserPromptSubmit hook: если промпт начинается с /dev — включает замок.
# Смысл: замок больше не зависит от того, вспомнит ли модель его создать.
# Содержимое файла не значимо, важен сам факт: Stop hook читает только наличие.
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
P="$(printf '%s' "$(cat)" | python3 -I -c '
import sys, json
try: print((json.load(sys.stdin).get("prompt") or "").strip())
except Exception: pass
' 2>/dev/null)"
case "$P" in
  # выход из режима — только отсюда: guard.sh не даёт снять замок из Bash
  /dev\ off|/dev\ off\ *) rm -f "$ROOT/.claude/dev-mode" "$ROOT/.claude/.stop-attempts" ;;
  /dev|/dev\ *) mkdir -p "$ROOT/.claude" && date +%s > "$ROOT/.claude/dev-mode" ;;
esac
exit 0
