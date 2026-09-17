#!/usr/bin/env bash
# Stop hook. Работает меньше секунды: сам ничего не прогоняет, а СВЕРЯЕТ аттестацию,
# которую оставил ./verify.sh. Так сделано потому, что хук, превысивший таймаут,
# просто отменяется и турн закрывается — то есть долгая проверка внутри хука была бы
# дырой «сделай тесты медленнее лимита».
# Отпускает, когда: аттестация свежая (отпечаток исходников совпал), в ней exit=0,
# и в PLAN.md нет незакрытых пунктов.
INPUT="$(cat)"
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" || exit 0

MODE_FILE=".claude/dev-mode"
COUNTER=".claude/.stop-attempts"
ATT=".claude/verify.json"
MAX=3
[ -f "$MODE_FILE" ] || exit 0

FP="$(bash .claude/hooks/fingerprint.sh 2>/dev/null || echo ERR)"

read_att() {  # $1 = поле
  python3 -I -c '
import json,sys
try: print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception: pass
' "$ATT" "$1" 2>/dev/null
}

release() { rm -f "$COUNTER" "$MODE_FILE" ".claude/protect-tests"; exit 0; }

block() {  # $1 текст для Claude, $2 причина для PLAN.md
  # Счётчик сбрасывается, как только код изменился с прошлой блокировки: одно дело
  # долбиться в стену, другое — починить и попробовать снова. Без этого счётчик
  # утекал между задачами и следующая получала меньше попыток.
  PREV_N="$(sed -n 1p "$COUNTER" 2>/dev/null || echo 0)"
  PREV_FP="$(sed -n 2p "$COUNTER" 2>/dev/null || echo '')"
  if [ "$PREV_FP" = "$FP" ]; then N=$(( PREV_N + 1 )); else N=1; fi
  printf '%s\n%s\n' "$N" "$FP" > "$COUNTER" 2>/dev/null || true
  if [ "$N" -gt "$MAX" ]; then
    [ -f PLAN.md ] || printf '# PLAN\n' > PLAN.md
    grep -q '^BLOCKED (hook)' PLAN.md 2>/dev/null || { echo; echo "BLOCKED (hook): $2"; } >> PLAN.md
    if [ "$N" -eq $(( MAX + 1 )) ]; then
      { echo "Исчерпаны $MAX попытки. Причина: $2."
        echo "В PLAN.md проставлен BLOCKED. Скажи пользователю, что осталось незакрытым, и заканчивай."
      } >&2
      exit 2     # последнее слово отдаём через exit 2: stderr при exit 0 модель не видит
    fi
    release
  fi
  { echo "Не завершай работу (попытка $N из $MAX)."; echo "$1"; } >&2
  exit 2
}

[ "$FP" = "ERR" ] && block "Не удалось посчитать отпечаток исходников — проверь python3." "сбой fingerprint.sh"

if [ ! -f "$ATT" ]; then
  block "Проверка не запускалась. Выполни ./verify.sh и дождись зелёного." "./verify.sh не запускался"
fi
A_FP="$(read_att fingerprint)"; A_CODE="$(read_att exit)"
if [ "$A_FP" != "$FP" ]; then
  block "Код менялся после последней проверки. Выполни ./verify.sh заново." "аттестация устарела"
fi
if [ "$A_CODE" != "0" ]; then
  block "Последний ./verify.sh упал (exit $A_CODE). Почини и прогони заново." "./verify.sh красный"
fi

if [ -f PLAN.md ]; then
  OPEN="$(grep -nE '^[[:space:]]*[-*+][[:space:]]*\[[[:space:]]*\]' PLAN.md | grep -v BLOCKED || true)"
  [ -n "$OPEN" ] && block "$(printf 'Проверка зелёная, но в PLAN.md незакрыты пункты:\n%s' "$(printf '%s' "$OPEN" | head -n 10)")" \
    "остались незакрытые пункты плана"
fi
release
