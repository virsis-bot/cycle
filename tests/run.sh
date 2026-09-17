#!/usr/bin/env bash
# Автотесты кита. Запуск: bash tests/run.sh (из корня dev-kit).
# Раздел ОБХОДЫ воспроизводит атаки из ревью — они должны оставаться закрытыми.
KIT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s — %s\n' "$1" "$2"; }
want(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "ждали $2, получили $3"; }

newproj() {
  P="$TMP/p$RANDOM$RANDOM"; mkdir -p "$P/.claude/hooks"; cd "$P" || exit 1
  git init -q .; git config user.email t@t; git config user.name t
  cp "$KIT/project/.claude/hooks/"*.sh "$KIT/project/.claude/hooks/"*.py .claude/hooks/
  cp "$KIT/project/verify.sh" .
  chmod +x verify.sh .claude/hooks/*.sh
  mkdir -p src; echo "x=1" > src/app.py
  git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1
  export CLAUDE_PROJECT_DIR="$P"
}
setverify() { printf '#!/usr/bin/env bash\nFAIL=%s\n%s\nexit $FAIL\n' "$1" \
  'mkdir -p "$CLAUDE_PROJECT_DIR/.claude"; printf "{\"fingerprint\":\"%s\",\"exit\":%s,\"at\":%s}\n" "$(bash "$CLAUDE_PROJECT_DIR/.claude/hooks/fingerprint.sh")" "$FAIL" "$(date +%s)" > "$CLAUDE_PROJECT_DIR/.claude/verify.json"' > verify.sh; chmod +x verify.sh; }
lock()  { mkdir -p .claude; date +%s > .claude/dev-mode; }
stop()  { echo '{"stop_hook_active":false}' | bash .claude/hooks/verify-stop.sh >/dev/null 2>&1; echo $?; }
gd()    { printf '%s' "$1" | bash .claude/hooks/guard.sh >/dev/null 2>&1; c=$?; [ $c -eq 2 ] && echo BLOCK || echo allow; }
ups()   { printf '{"hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1" | bash .claude/hooks/dev-mode.sh >/dev/null 2>&1; }
B(){ want "$1" BLOCK "$(gd "$2")"; }
A(){ want "$1" allow "$(gd "$2")"; }

echo "── verify.sh и аттестация ──"
newproj; ./verify.sh >/dev/null 2>&1; want "V1 ненастроенный verify.sh падает" 1 "$?"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1
[ -f .claude/verify.json ] && ok "V2 verify.sh пишет аттестацию" || bad "V2 verify.sh пишет аттестацию" "нет файла"

echo "── Stop hook ──"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; want "S1 без замка не мешает" 0 "$(stop)"
newproj; setverify 0; lock; want "S2 проверка не запускалась → блок" 2 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock; want "S3 зелёная аттестация отпускает" 0 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock; stop >/dev/null
[ -f .claude/dev-mode ] && bad "S4 хук снимает замок" "остался" || ok "S4 хук снимает замок"
newproj; setverify 1; ./verify.sh >/dev/null 2>&1; lock; want "S5 красный verify → блок" 2 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock
echo "СЛОМАНО" >> src/app.py; want "S6 правка после проверки → блок" 2 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock
echo "СЛОМАНО" >> src/app.py; git add -A >/dev/null; git commit -qm x
want "S7 КОММИТ не отменяет проверку" 2 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock
printf '# PLAN\n- [x] T1\n- [ ] T2\n' > PLAN.md; want "S8 незакрытый - [ ] блокирует" 2 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock
printf '# PLAN\n* [ ] T2\n' > PLAN.md; want "S9 звёздочка тоже считается" 2 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock
printf '# PLAN\n- [ ] T2 BLOCKED: чужой API\n' > PLAN.md; want "S10 BLOCKED не мешает" 0 "$(stop)"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock
printf '# PLAN\n- [ ] T2\n' > PLAN.md
a=$(stop);b=$(stop);c=$(stop);d=$(stop);e=$(stop)
want "S11 лимит: 2,2,2,2(финал),0" "22220" "$a$b$c$d$e"
grep -q 'BLOCKED (hook)' PLAN.md && ok "S12 хук сам пишет BLOCKED" || bad "S12 хук сам пишет BLOCKED" "нет"
newproj; setverify 0; ./verify.sh >/dev/null 2>&1; lock
t0=$(python3 -c "import time;print(time.time())"); stop >/dev/null
t1=$(python3 -c "import time;print(time.time())")
python3 -c "
d=($t1-$t0)*1000
print('  ok   S13 Stop-хук быстрый (%.0f мс)'%d) if d<2000 else print('  FAIL S13 медленный: %.0f мс'%d)" | tee /dev/stderr | grep -q FAIL && FAIL=$((FAIL+1)) || PASS=$((PASS+1))

newproj; setverify 1; ./verify.sh >/dev/null 2>&1; lock
a=$(stop); b=$(stop)
echo "правка" >> src/app.py; ./verify.sh >/dev/null 2>&1
c=$(stop); d=$(stop); e=$(stop)
want "S14 правка кода сбрасывает счётчик" "22222" "$a$b$c$d$e"

echo "── UserPromptSubmit ──"
newproj; ups "/dev починить кнопку"
[ -f .claude/dev-mode ] && ok "U1 /dev ставит замок" || bad "U1 /dev ставит замок" "нет"
ups "/dev off"; [ -f .claude/dev-mode ] && bad "U2 /dev off снимает" "остался" || ok "U2 /dev off снимает"
newproj; ups "просто вопрос"
[ -f .claude/dev-mode ] && bad "U3 обычный промпт не ставит" "поставил" || ok "U3 обычный промпт не ставит"

echo "── ОБХОДЫ из ревью (должны быть закрыты) ──"
newproj; lock
B "X1 true; rm -rf /"            '{"tool_name":"Bash","tool_input":{"command":"true; rm -rf /"}}'
B "X2 cd /tmp && rm -rf ~"       '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && rm -rf ~"}}'
B "X3 true && git push --force"  '{"tool_name":"Bash","tool_input":{"command":"true && git push --force"}}'
B "X4 sh -c rm -rf /"            '{"tool_name":"Bash","tool_input":{"command":"sh -c \"rm -rf /\""}}'
B "X5 rm -r ~ без -f"            '{"tool_name":"Bash","tool_input":{"command":"rm -r ~"}}'
B "X6 rm -rf . (весь проект)"    '{"tool_name":"Bash","tool_input":{"command":"rm -rf ."}}'
B "X7 rm -rf\${IFS}/"            '{"tool_name":"Bash","tool_input":{"command":"rm -rf${IFS}/"}}'
B "X8 git push origin +main"     '{"tool_name":"Bash","tool_input":{"command":"git push origin +main"}}'
B "X9 echo >.env без пробела"    '{"tool_name":"Bash","tool_input":{"command":"echo K=1 >.env"}}'
B "X10 cp в .env"                '{"tool_name":"Bash","tool_input":{"command":"cp /tmp/leak .env"}}'
B "X11 tee .env"                 '{"tool_name":"Bash","tool_input":{"command":"echo K=1 | tee .env"}}'
B "X12 rm .claude/dev-mode"      '{"tool_name":"Bash","tool_input":{"command":"rm -f .claude/dev-mode"}}'
B "X13 подделка verify.json"     '{"tool_name":"Bash","tool_input":{"command":"echo {} > .claude/verify.json"}}'
B "X14 подмена verify.sh"        '{"tool_name":"Bash","tool_input":{"command":"printf \"exit 0\" > verify.sh"}}'
B "X15 Write в verify.sh"        "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PWD/verify.sh\"}}"
B "X16 chmod -x verify.sh"       '{"tool_name":"Bash","tool_input":{"command":"chmod -x verify.sh"}}'
B "X17 git reset --hard"         '{"tool_name":"Bash","tool_input":{"command":": ; git reset --hard"}}'
printf 'raise SystemExit(0)\n' > shlex.py
B "X18 подмена модуля shlex.py"  '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
rm -f shlex.py
newproj; lock; touch .claude/protect-tests; mkdir -p tests; echo t > tests/test_a.py
B "X19 sed -i по тесту"          '{"tool_name":"Bash","tool_input":{"command":"sed -i \"\" s/a/b/ tests/test_a.py"}}'
B "X20 rm теста"                 '{"tool_name":"Bash","tool_input":{"command":"rm tests/test_a.py"}}'
B "X21 cat > теста"              '{"tool_name":"Bash","tool_input":{"command":"cat /tmp/x > tests/test_a.py"}}'
B "X22 Tests/ с большой буквы"   "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PWD/Tests/FooTests.swift\"}}"
B "X23 NotebookEdit теста"       "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$PWD/tests/t.ipynb\"}}"
B "X24 rm .claude/protect-tests" '{"tool_name":"Bash","tool_input":{"command":"rm .claude/protect-tests"}}'

echo "── ложные срабатывания (должны проходить) ──"
newproj; lock
A "F1 обычный Edit"              "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PWD/src/app.py\"}}"
A "F2 ls"                        '{"tool_name":"Bash","tool_input":{"command":"ls -la src"}}'
A "F3 chmod +x verify.sh"        '{"tool_name":"Bash","tool_input":{"command":"chmod +x verify.sh"}}'
A "F4 rm .env.example"           '{"tool_name":"Bash","tool_input":{"command":"rm .env.example"}}'
A "F5 rm -rf build"              '{"tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
A "F6 rm -rf /tmp/mycache"       '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/mycache"}}'
A "F7 --force-with-lease"        '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}'
A "F8 запуск тестов"             '{"tool_name":"Bash","tool_input":{"command":"pytest -q tests/"}}'
A "F9 новый скилл в .claude"     "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PWD/.claude/skills/x/SKILL.md\"}}"
touch .claude/protect-tests
A "F10 чистка __pycache__"       '{"tool_name":"Bash","tool_input":{"command":"rm -rf tests/__pycache__"}}'

echo "── деградация ──"
newproj
out=$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | PATH=/nonexistent /bin/bash .claude/hooks/guard.sh 2>&1); c=$?
want "D1 нет python3 → блокирует (не fail-open)" 2 "$c"
A "D2 битый JSON пропускается"   'не json вовсе'

echo "── ОБХОДЫ из второго ревью ──"
newproj; lock
B "Y1 .Claude/ в другом регистре"  '{"tool_name":"Bash","tool_input":{"command":"printf x > .Claude/verify.json"}}'
B "Y2 rm .CLAUDE/dev-mode"         '{"tool_name":"Bash","tool_input":{"command":"rm .CLAUDE/dev-mode"}}'
B "Y3 mv уносит замок (источник)"  '{"tool_name":"Bash","tool_input":{"command":"mv .claude/dev-mode /tmp/x"}}'
B "Y4 mv уносит .env"              '{"tool_name":"Bash","tool_input":{"command":"mv .env /tmp/leak"}}'
B "Y5 mv уносит verify.sh"         '{"tool_name":"Bash","tool_input":{"command":"mv verify.sh /tmp/old"}}'
B "Y6 env rm -rf вне проекта"      '{"tool_name":"Bash","tool_input":{"command":"env rm -rf /Users/nobody/x"}}'
B "Y7 rm -Rf заглавная R"          '{"tool_name":"Bash","tool_input":{"command":"rm -Rf /Users/nobody/x"}}'
B "Y8 глубокая обёртка env x50"    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$(python3 -c 'print("env "*50+"rm -rf /Users/nobody/x")')\"}}"
B "Y9 git -C . push --force"       '{"tool_name":"Bash","tool_input":{"command":"git -C . push --force"}}'
B "Y10 git --no-pager reset --hard" '{"tool_name":"Bash","tool_input":{"command":"git --no-pager reset --hard"}}'

echo "── ложные срабатывания из второго ревью ──"
A "G1 коммит со словом force в тексте" '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs: warn about git push --force\""}}'
A "G2 grep по тексту про reset"    '{"tool_name":"Bash","tool_input":{"command":"grep -rn \"git reset --hard\" docs"}}'
A "G3 rm -rf с переменной внутри проекта" '{"tool_name":"Bash","tool_input":{"command":"rm -rf build/$VERSION"}}'
A "G4 перенос чужого verify.sh"    '{"tool_name":"Bash","tool_input":{"command":"mv tools/verify.sh scripts/verify.sh"}}'

echo "── fingerprint ──"
newproj
python3 -c "open('big.py','w').write('A'*300000)"
f1=$(bash .claude/hooks/fingerprint.sh)
python3 -c "open('big.py','w').write('B'*300000)"; touch -t 200001010000 big.py
f2=$(bash .claude/hooks/fingerprint.sh)
[ "$f1" != "$f2" ] && ok "P1 большой файл: подмена содержимого видна" || bad "P1 большой файл" "отпечаток не изменился"
mkdir -p dist; echo "код" > dist/mod.py; f3=$(bash .claude/hooks/fingerprint.sh)
[ "$f2" != "$f3" ] && ok "P2 код в dist/ входит в отпечаток" || bad "P2 код в dist/" "невидим"
mkdir -p src; f4=$(bash .claude/hooks/fingerprint.sh); echo "evil" > src/PLAN.md; f5=$(bash .claude/hooks/fingerprint.sh)
[ "$f4" != "$f5" ] && ok "P3 src/PLAN.md не игнорируется" || bad "P3 src/PLAN.md" "игнорируется"
printf '# PLAN\n- [ ] x\n' > PLAN.md; f6=$(bash .claude/hooks/fingerprint.sh)
[ "$f5" = "$f6" ] && ok "P4 корневой PLAN.md отпечаток не трогает" || bad "P4 корневой PLAN.md" "трогает"

echo "── pre-push ──"
newproj; lock
B "H1 git push --no-verify"        '{"tool_name":"Bash","tool_input":{"command":"git push --no-verify"}}'
B "H2 git -C . push --no-verify"   '{"tool_name":"Bash","tool_input":{"command":"git -C . push origin main --no-verify"}}'
B "H3 правка .git/hooks/pre-push"  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PWD/.git/hooks/pre-push\"}}"
B "H4 rm .git/hooks/pre-push"      '{"tool_name":"Bash","tool_input":{"command":"rm .git/hooks/pre-push"}}'
B "H5 echo > .git/config"          '{"tool_name":"Bash","tool_input":{"command":"echo x > .git/config"}}'
A "H6 обычный git push"            '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
A "H7 снятие застрявшего index.lock" '{"tool_name":"Bash","tool_input":{"command":"rm -f .git/index.lock"}}'
newproj; cp "$KIT/project/git-hooks/pre-push" .git/hooks/pre-push; chmod +x .git/hooks/pre-push
setverify 1
bash .git/hooks/pre-push </dev/null >/dev/null 2>&1; want "H8 pre-push режет красный verify" 1 "$?"
setverify 0
bash .git/hooks/pre-push </dev/null >/dev/null 2>&1; want "H9 pre-push пропускает зелёный" 0 "$?"
rm -f verify.sh
bash .git/hooks/pre-push </dev/null >/dev/null 2>&1; want "H10 нет verify.sh — не мешает push" 0 "$?"

echo "── stats.sh и docs ──"
newproj; cp "$KIT/project/stats.sh" .; chmod +x stats.sh
bash stats.sh >/dev/null 2>&1; want "M1 без LOG.md не падает" 0 "$?"
printf '# LOG\nT1 | ok | попытка 1\nT2 | fail | попытка 1\nT2 | ok | попытка 2\n' > LOG.md
printf '# PLAN\n- [x] T1\n- [ ] T3 BLOCKED: причина\n' > PLAN.md
out=$(bash stats.sh 2>&1); want "M2 отрабатывает на логе" 0 "$?"
echo "$out" | grep -q "шагов в логе:             2" && ok "M3 считает шаги" || bad "M3 считает шаги" "$(echo "$out"|head -1)"
echo "$out" | grep -q "T2" && ok "M4 находит проблемный шаг" || bad "M4 находит проблемный шаг" "нет T2"
echo "$out" | grep -q "BLOCKED в плане" && ok "M5 считает BLOCKED" || bad "M5 считает BLOCKED" "нет строки"
python3 -c "import xml.dom.minidom;xml.dom.minidom.parse('$KIT/docs/schema.svg')" 2>/dev/null \
  && ok "M6 docs/schema.svg — валидный XML" || bad "M6 docs/schema.svg" "не парсится"
grep -q 'prefers-color-scheme' "$KIT/docs/schema.svg" && ok "M7 схема работает в тёмной теме" || bad "M7 тёмная тема" "нет медиазапроса"

echo
echo "итог: ok=$PASS  fail=$FAIL"
[ "$FAIL" -eq 0 ]
