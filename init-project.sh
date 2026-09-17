#!/usr/bin/env bash
# Подключение проекта: запускать ИЗ КОРНЯ проекта.
# Твои файлы не затираются: изменённое уходит в *.bak.<дата>.
# Повторный запуск = обновление кита.
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
P="$(pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"
echo "Проект: $P"

same() { [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; }

copy_if_absent() {  # CLAUDE.md, verify.sh — их пишет пользователь, не трогаем
  if [ -e "$P/$1" ]; then echo "  пропуск (уже есть): $1"
  else mkdir -p "$(dirname "$P/$1")"; cp "$KIT/project/$1" "$P/$1"; echo "✓ $1"; fi
}

install_hook() {  # хуки обновляем, но изменённые сначала в бэкап
  local rel="$1"
  local src="$KIT/project/$rel"
  local dst="$P/$rel"
  if same "$src" "$dst"; then echo "  без изменений: $rel"; return 0; fi
  if [ -e "$dst" ]; then mv "$dst" "$dst.bak.$STAMP"; echo "  бэкап: $rel.bak.$STAMP"; fi
  cp "$src" "$dst"; chmod +x "$dst"; echo "✓ $rel"
}

copy_if_absent CLAUDE.md
copy_if_absent verify.sh
copy_if_absent stats.sh
chmod +x "$P/verify.sh" "$P/stats.sh" 2>/dev/null || true
mkdir -p "$P/.claude/hooks"
for h in verify-stop.sh guard.sh dev-mode.sh fingerprint.sh guard.py fingerprint.py; do
  install_hook ".claude/hooks/$h"
done

# pre-push: проверка перед отправкой в remote. Локальный файл, в репозиторий не едет.
if [ -d "$P/.git" ]; then
  if same "$KIT/project/git-hooks/pre-push" "$P/.git/hooks/pre-push"; then
    echo "  без изменений: .git/hooks/pre-push"
  else
    mkdir -p "$P/.git/hooks"
    [ -e "$P/.git/hooks/pre-push" ] && { mv "$P/.git/hooks/pre-push" "$P/.git/hooks/pre-push.bak.$STAMP"; echo "  бэкап: .git/hooks/pre-push.bak.$STAMP"; }
    cp "$KIT/project/git-hooks/pre-push" "$P/.git/hooks/pre-push"
    chmod +x "$P/.git/hooks/pre-push"; echo "✓ .git/hooks/pre-push"
  fi
fi

# Слить хуки в .claude/settings.json: свои записи заменяем, чужие не трогаем
[ -f "$P/.claude/settings.json" ] && cp "$P/.claude/settings.json" "$P/.claude/settings.json.bak.$STAMP" || true
python3 - "$P/.claude/settings.json" "$KIT/project/.claude/settings.dev-kit.json" <<'PY'
import json, os, sys, tempfile
dst, src = sys.argv[1], sys.argv[2]
cur = json.load(open(dst)) if os.path.exists(dst) else {}
add = json.load(open(src))
hooks = cur.setdefault("hooks", {})
MINE = ("verify-stop.sh", "guard.sh", "dev-mode.sh")
mine = lambda g: any(".claude/hooks/" in (h.get("command") or "")
                     and any(m in h["command"] for m in MINE)
                     for h in g.get("hooks", []))
for event, groups in add["hooks"].items():
    lst = [g for g in hooks.get(event, []) if not mine(g)]
    lst.extend(groups)
    hooks[event] = lst
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dst) or ".")
with os.fdopen(fd, "w") as f:
    json.dump(cur, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, dst)
print("✓ .claude/settings.json (хуки Stop + PreToolUse)")
PY

# Служебные файлы — в .gitignore
touch "$P/.gitignore"
for line in ".claude/dev-mode" ".claude/.stop-attempts" ".claude/protect-tests" \
            ".claude/verify.json" ".claude/settings.local.json"; do
  grep -qxF "$line" "$P/.gitignore" || echo "$line" >> "$P/.gitignore"
done
echo "✓ .gitignore"

[ -d "$P/.git" ] || echo "! Нет git. Советую: git init && git add -A && git commit -m init"
echo
echo "Осталось: 1) заполнить CLAUDE.md  2) раскомментировать команды в verify.sh"
echo "Проверка: ./verify.sh   Запуск: claude → /dev <задача>"
