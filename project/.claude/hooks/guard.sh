#!/usr/bin/env bash
# PreToolUse hook. Вся логика в guard.py рядом. Exit 2 = вызов отменён.
# Это защита от случайностей и коротких путей, НЕ граница безопасности —
# см. раздел «Чего кит НЕ гарантирует» в README.
D="$(cd "$(dirname "$0")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "ЗАБЛОКИРОВАНО: нет python3, guard.sh не может проверить вызов." >&2
  exit 2
fi
REASON="$(CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}" python3 -I "$D/guard.py" 2>/dev/null)"
if [ -n "$REASON" ]; then
  echo "ЗАБЛОКИРОВАНО хуком guard.sh: $REASON" >&2
  exit 2
fi
exit 0
