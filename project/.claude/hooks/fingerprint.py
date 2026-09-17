"""Отпечаток исходников. Без git — поэтому git stash и .gitignore на него не влияют.
Хешируется СОДЕРЖИМОЕ каждого файла (без порога по размеру: порог позволял подменить
большой файл, сохранив размер и mtime). Включает хуки и verify.sh — подмена проверки
меняет отпечаток."""
import os, sys, hashlib

ROOT = os.path.realpath(sys.argv[1] if len(sys.argv) > 1 else ".")
# пропускаем только то, что не может содержать написанный руками код
SKIP = {".git", "node_modules", "__pycache__", ".venv", "venv", ".tox",
        ".pytest_cache", ".mypy_cache", ".ruff_cache", ".gradle", ".claude"}
# файлы процесса, а не кода: только в корне
STATE = {"PLAN.md", "NOTES.md", "LOG.md", "HANDOFF.md", "SPEC.md", ".DS_Store"}
BIG = 262144
h = hashlib.sha256()


def add(path, rel):
    try:
        st = os.stat(path)
    except OSError:
        return
    h.update(rel.encode("utf-8", "replace")); h.update(b"\0")
    h.update(str(st.st_size).encode()); h.update(b"\0")
    if st.st_size <= BIG:
        try:
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
        except OSError:
            h.update(str(st.st_mtime_ns).encode())
    else:
        # крупные файлы не читаем целиком: st_ctime_ns обновляется при любой записи
        # и, в отличие от mtime, не выставляется утилитой touch
        h.update(("%d:%d:%d" % (st.st_mtime_ns, st.st_ctime_ns, st.st_ino)).encode())
    h.update(b"\0")


for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
    for fn in sorted(filenames):
        p = os.path.join(dirpath, fn)
        r = os.path.relpath(p, ROOT)
        if r in STATE:            # только корневые, не любой src/PLAN.md
            continue
        add(p, r)
hooks = os.path.join(ROOT, ".claude", "hooks")
if os.path.isdir(hooks):
    for fn in sorted(os.listdir(hooks)):
        add(os.path.join(hooks, fn), os.path.join(".claude/hooks", fn))
print(h.hexdigest())
