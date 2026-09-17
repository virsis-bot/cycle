#!/usr/bin/env bash
# Зеркало по LOG.md: где цикл буксует. Только читает, ничего не меняет.
# Строка лога: <шаг> | ok|fail | попытка N
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" || exit 1
[ -f LOG.md ] || { echo "LOG.md нет — считать не из чего"; exit 0; }

awk -F'|' '
  {
    gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2)
    if (NF < 2 || $1 == "" || $1 ~ /^#/) next
    step = $1
    if (!(step in seen)) { seen[step] = 1; order[++n] = step }
    total[step]++
    if ($2 ~ /ok/)   { ok[step]++;   if (total[step] == 1) first++ }
    if ($2 ~ /fail/) { fail[step]++; anyfail++ }
  }
  END {
    if (n == 0) { print "  в LOG.md нет разобранных строк"; exit }
    printf "  шагов в логе:             %d\n", n
    printf "  закрыто с первой попытки: %d из %d (%d%%)\n", first, n, first * 100 / n
    printf "  всего неудачных попыток:  %d\n", anyfail + 0
    worst = ""; wc = 0
    for (i = 1; i <= n; i++) { s = order[i]; if (fail[s] > wc) { wc = fail[s]; worst = s } }
    if (wc > 0) printf "  больше всего возвратов:   %s (%d)\n", worst, wc
  }
' LOG.md

if [ -f PLAN.md ]; then
  B=$(grep -c 'BLOCKED' PLAN.md 2>/dev/null || echo 0)
  T=$(grep -cE '^[[:space:]]*[-*+][[:space:]]*\[' PLAN.md 2>/dev/null || echo 0)
  [ "$T" -gt 0 ] && printf '  BLOCKED в плане:          %d из %d пунктов\n' "$B" "$T"
fi
echo
echo "  Много неудач на первой попытке — шаги слишком крупные."
echo "  Растёт BLOCKED — дыра в verify.sh или в дроблении плана."
