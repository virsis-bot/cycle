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
# выход из режима — только отсюда: guard.sh не даёт снять замок из Bash.
# Строго «/dev», пробелы, «off» в любом регистре и ничего больше: иначе
# «/dev off by one in parser» — обычная задача — молча снимала бы сторожа.
# Снимает и protect-tests: вне режима блокировка тестов только мешает.
if [[ "$P" =~ ^/dev[[:space:]]+[oO][fF][fF]$ ]]; then
  rm -f "$ROOT/.claude/dev-mode" "$ROOT/.claude/.stop-attempts" "$ROOT/.claude/protect-tests"
elif [ "$P" = "/dev" ] || [[ "$P" == "/dev"[[:space:]]* ]]; then
  mkdir -p "$ROOT/.claude" && date +%s > "$ROOT/.claude/dev-mode"
fi
exit 0
