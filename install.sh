#!/usr/bin/env bash
# Глобальная установка: скилл /dev и агенты в ~/.claude (один раз на компьютер).
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"
mkdir -p "$DEST/skills" "$DEST/agents"

backup() { [ -e "$1" ] && mv "$1" "$1.bak.$(date +%Y%m%d%H%M%S)" && echo "  бэкап: $1.bak.*"; return 0; }

backup "$DEST/skills/dev"
cp -R "$KIT/global/skills/dev" "$DEST/skills/dev"
echo "✓ скилл  → $DEST/skills/dev"

for f in "$KIT"/global/agents/*.md; do
  backup "$DEST/agents/$(basename "$f")"
  cp "$f" "$DEST/agents/"
  echo "✓ агент  → $DEST/agents/$(basename "$f")"
done
echo
echo "Готово. Дальше в каждом проекте: bash \"$KIT/init-project.sh\""
