#!/usr/bin/env bash
# Единая проверка проекта. Код выхода 0 = всё хорошо.
# Выводит только ошибки — это экономит токены.
# РАСКОММЕНТИРУЙ/ПОПРАВЬ строки под свой стек. Пока не раскомментировано —
# скрипт падает намеренно: пустая проверка опаснее отсутствующей.

FAIL=0
CHECKS=0
run() {
  local name="$1"; shift
  local out
  CHECKS=$((CHECKS + 1))
  if ! out="$("$@" 2>&1)"; then
    echo "✗ $name"
    echo "$out" | tail -n 25
    FAIL=1
  fi
}

# --- JavaScript / TypeScript ---
# run "types"  npx tsc --noEmit
# run "lint"   npx eslint . --quiet
# run "tests"  npm test --silent

# --- Python ---
# run "lint"   ruff check .
# run "types"  mypy .
# run "tests"  pytest -q -x

# --- Astro / сайт ---
# run "build"  npm run build --silent

if [ "$CHECKS" -eq 0 ]; then
  echo "✗ verify.sh не настроен: раскомментируй проверки под свой стек в verify.sh"
  echo "  иначе Stop hook будет пропускать любой результат как зелёный"
  exit 1
fi
if [ "$FAIL" -eq 0 ]; then echo "✓ verify ok"; fi

# Аттестация для Stop-хука: отпечаток исходников + код выхода.
if [ -x "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/fingerprint.sh" ]; then
  mkdir -p "${CLAUDE_PROJECT_DIR:-.}/.claude"
  printf '{"fingerprint":"%s","exit":%s,"at":%s}\n' \
    "$(bash "${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/fingerprint.sh")" "$FAIL" "$(date +%s)" \
    > "${CLAUDE_PROJECT_DIR:-.}/.claude/verify.json"
fi
exit $FAIL
