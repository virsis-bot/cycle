"""Логика PreToolUse-хука. Запускается как python3 -I guard.py, читает JSON со stdin.
Печатает причину блокировки или ничего. Любой сбой разбора = блокировка (fail-closed)."""
import os, sys, json, shlex, re, posixpath

ROOT = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or ".")
CDIR = os.path.join(ROOT, ".claude")
DEV  = os.path.exists(os.path.join(CDIR, "dev-mode"))
PROT = os.path.exists(os.path.join(CDIR, "protect-tests"))
I = re.I

ENV_RE  = re.compile(r"(^|/)\.env(\.[^/]*)?$", I)
ENV_OK  = re.compile(r"\.env\.(example|sample|template|dist)$", I)
TEST_RE = re.compile(r"(^|/)(tests?|__tests__|specs?)/|(_test|_spec|\.test|\.spec|Tests?)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$", I)
TEST_OK = re.compile(r"(__pycache__|\.pyc$|\.pytest_cache|node_modules|\.snap$)", I)
CLAUDE_OK = re.compile(r"^\.claude/(commands|agents|skills|memory)/", I)
CLAUDE_RE = re.compile(r"^\.claude(/|$)", I)
GIT_RE    = re.compile(r"^\.git(/|$)", I)
# опции git до подкоманды: git -C . push, git --no-pager reset, git -c k=v push
GITOPT = r"(?:-{1,2}[A-Za-z-]+(?:=\S+)?\s+|-[cC]\s+\S+\s+)*"
BACKSTOP = [
 (re.compile(r"\brm\s+(?:-\S+\s+)*-\S*[rR]\S*\s+(?:/|~|\$\{?HOME\}?|\*)(?=\s|$|;|&|\||\"|\x27)"),
  "rm -rf по корню, домашней папке или *"),
 (re.compile(r"\bgit\s+" + GITOPT + r"push\b[^;&|]*(?:--force(?!-with-lease|-if-includes)|\s-f(?=\s|$)|\s\+\S)", I),
  "форс-пуш (включая refspec +branch). Используй --force-with-lease или вручную"),
 (re.compile(r"\bgit\s+" + GITOPT + r"reset\b[^;&|]*--hard", I),
  "git reset --hard — спроси пользователя"),
 # стирают незакоммиченную работу молча; git clean -X/-x заодно сносит замок
 # .claude/dev-mode, потому что он в .gitignore — обычная уборка снимала бы защиту
 (re.compile(r"\bgit\s+" + GITOPT + r"clean\b(?![^;&|]*\s-(?:-dry-run|[A-Za-z]*n))[^;&|]*\s(?:--force|-[A-Za-z]*f)", I),
  "git clean -f удаляет неотслеживаемые файлы, а с -X/-x — и замок кита. Сначала git clean -n, остальное — пользователь"),
 (re.compile(r"\bgit\s+" + GITOPT + r"checkout\b[^;&|]*(?:\s--(?=\s|$)|\s\.(?=\s|$)|\s(?:-f|--force)(?=\s|$))", I),
  "git checkout -- / . / -f стирает незакоммиченные правки. Закоммить или спроси пользователя"),
 (re.compile(r"\bgit\s+" + GITOPT + r"restore\b(?![^;&|]*\s(?:--staged|-S)(?=\s|$)(?![^;&|]*\s(?:--worktree|-W)(?=\s|$)))", I),
  "git restore стирает незакоммиченные правки. Закоммить или спроси пользователя"),
 (re.compile(r"\bgit\s+" + GITOPT + r"stash\b[^;&|]*\s(?:-a|--all)(?=\s|$)", I),
  "git stash --all уносит и игнорируемые файлы, включая замок кита"),
 (re.compile(r"\bgit\s+" + GITOPT + r"push\b[^;&|]*--no-verify", I),
  "git push --no-verify отключает проверку перед отправкой. Почини тесты, а не обходи хук"),
]
# команды, внутри которых текст — это данные, а не вызов
QUOTING = {"echo", "printf", "grep", "rg", "cat", "ack", "comm", "diff"}
UNWRAP  = {"env", "sudo", "nohup", "time", "xargs", "command", "exec", "doas", "stdbuf"}
COPYLIKE = {"cp", "mv", "ln", "install", "dd", "rsync"}


def split_segments(cmd):
    segs, buf, q, i = [], [], None, 0
    while i < len(cmd):
        c = cmd[i]
        if q:
            buf.append(c)
            if c == q:
                q = None
            elif c == "\\" and q == chr(34) and i + 1 < len(cmd):
                i += 1
                buf.append(cmd[i])
        elif c in (chr(39), chr(34)):
            q = c
            buf.append(c)
        elif c in ";\n":
            segs.append("".join(buf)); buf = []
        elif c in "&|":
            segs.append("".join(buf)); buf = []
            if i + 1 < len(cmd) and cmd[i + 1] == c:
                i += 1
        else:
            buf.append(c)
        i += 1
    segs.append("".join(buf))
    return [s.strip() for s in segs if s.strip()]


def head_of(seg):
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        toks = seg.split()
    d = 0
    while toks and d < 8:
        h = posixpath.basename(toks[0])
        if h == "git" and len(toks) > 1:
            return "git " + next((t for t in toks[1:] if not t.startswith("-")), "")
        if h in UNWRAP:
            toks = toks[1:]; d += 1; continue
        return h
    return toks[0] if toks else ""


def rel(p):
    p = p.strip().strip(chr(39) + chr(34))
    ap = p if posixpath.isabs(p) else posixpath.join(ROOT, p)
    try:
        real = os.path.realpath(ap)
    except Exception:
        real = ap
    # realpath уводит с симлинка; для .claude/dev-mode это важно, поэтому берём оба
    for cand in (real, posixpath.normpath(ap)):
        if cand.startswith(ROOT + "/"):
            return cand[len(ROOT) + 1:]
    return p


def inside(tok):
    t = tok.strip().strip(chr(39) + chr(34))
    if not t or t.startswith("~") or t.startswith("$"):
        return False
    if "$" in t:
        # подстановка внутри относительного пути без .. за пределы проекта не выводит
        return not posixpath.isabs(t) and ".." not in t.split("/")
    base = ROOT if not posixpath.isabs(t) else "/"
    full = posixpath.normpath(posixpath.join(base, t))
    try:
        full = os.path.realpath(full)
    except Exception:
        pass
    if full == ROOT:
        return False                      # rm -rf . сносит весь проект
    if any(full.startswith(x) for x in ("/tmp/", "/var/folders/", "/private/tmp/", "/private/var/folders/")):
        return True
    return full.startswith(ROOT + "/")


def path_verdict(p, writing):
    if not writing or not p:
        return None
    r = rel(p)
    low = r.replace(os.sep, "/")
    if GIT_RE.match(low) and low.lower() != ".git/index.lock":
        return "запись в .git/ (%s) — служебный каталог git, туда пишет только git" % r
    if CLAUDE_RE.match(low) and not CLAUDE_OK.match(low) and DEV:
        return "запись в .claude/ (%s) — служебное состояние кита ведут хуки" % r
    if low.lower() == "verify.sh" and DEV:
        return "правка verify.sh при включённом режиме — проверку не переписывают под себя"
    if ENV_RE.search(low) and not ENV_OK.search(low):
        return "запись в %s — секреты меняет только пользователь" % r
    if PROT and TEST_RE.search(low) and not TEST_OK.search(low):
        return "тесты заблокированы (.claude/protect-tests): %s. Спроси пользователя" % r
    return None


def check_segment(seg, depth=0):
    if depth > 6:
        return "команда слишком глубоко завёрнута, разобрать не удалось"
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        toks = seg.split()
    if not toks:
        return None
    head = posixpath.basename(toks[0])
    if head in UNWRAP:
        rest = [t for t in toks[1:] if "=" not in t.split("/")[0] or t.startswith("-")]
        return check_segment(" ".join(shlex.quote(t) for t in rest), depth + 1) if rest else None
    flags = [t for t in toks[1:] if t.startswith("-")]
    args  = [t for t in toks[1:] if not t.startswith("-")]
    redir = []
    for i, t in enumerate(toks):
        if t in (">", ">>") and i + 1 < len(toks):
            redir.append(toks[i + 1])
        elif re.match(r"^>{1,2}\S", t):
            redir.append(t.lstrip(">"))
    if head == "rm" and any(("r" in f.lower() or f == "--recursive") for f in flags):
        if any("$" in f for f in flags):
            return "rm с подстановкой внутри ключей — цель не разобрать"
        for a in args:
            if not inside(a):
                return "rm -rf по цели вне проекта (%s). Это делает пользователь" % a
    if head == "chmod":
        mode = flags[0] if flags else (args[0] if args else "")
        octal = re.fullmatch(r"[0-7]{3,4}", mode)
        drops = ("-" in mode and "x" in mode) or (octal and int(mode[-3]) % 2 == 0)
        for a in (args if flags else args[1:]):
            if rel(a).lower() == "verify.sh" and drops:
                return "chmod снимает исполняемый бит с verify.sh — так проверка отключается"
        return None
    mutate = head in ("rm", "truncate", "shred", "tee") or head in COPYLIKE
    inplace = head in ("sed", "perl", "ruby") and any(re.match(r"^-\S*i", f) for f in flags)
    # у cp/mv/ln проверяем И источник, и приёмник: mv уносит файл так же, как правка
    for t in args + redir:
        v = path_verdict(t, mutate or inplace or t in redir)
        if v:
            return v
    return None


def main():
    d = json.load(sys.stdin)
    tool = d.get("tool_name", "") or ""
    ti = d.get("tool_input") or {}
    if tool == "Bash":
        cmd = ti.get("command", "") or ""
        segs = split_segments(cmd)
        for rx, why in BACKSTOP:
            m = rx.search(cmd)
            if m:
                owner = next((s for s in segs if m.group(0)[:20] in s), "")
                if head_of(owner) in QUOTING or head_of(owner) == "git commit":
                    continue
                return why
        for seg in segs:
            v = check_segment(seg)
            if v:
                return v
        return None
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return path_verdict(ti.get("file_path") or ti.get("notebook_path") or "", True)
    return None


try:
    r = main()
except json.JSONDecodeError:
    r = None                       # не наш вход — пропускаем
except RecursionError:
    r = "команду не удалось разобрать (слишком глубокая вложенность)"
except Exception as e:
    r = "сбой разбора команды в guard.py: %s" % type(e).__name__
if r:
    print(r)
