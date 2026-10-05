"""P-20261005-bash-write-unify の確認用フィクスチャ（planner が作成。編集しない）。

agent_write_guard.py の BASH_WRITE_PATTERNS・OTHER_WRITE_PATTERNS（正規表現の文字列のリスト）と
DESTRUCTIVE_BASH_PATTERN（正規表現の文字列）が、一本化する前（main = 854cc4e）の定義と同じ文字列に
一致するかを、下の SAMPLES で1件ずつ比べる。違ったものを `<名前>: <サンプル>` で1行ずつ出し、最後に
`pattern_mismatch=<件数>` と `samples=<サンプル数>` を出す。

使い方（リポジトリのルートで）：python3 -B vault/tasks/P-20261005-bash-write-unify/fixtures/patterns_check.py
"""
import os
import re
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, ".claude", "hooks"))

import agent_write_guard as G  # noqa: E402

# 一本化する前の定義（854cc4e の agent_write_guard.py から写したもの）
OLD_BASH_WRITE_PATTERNS = [
    r"(^|[^<>])>{1,2}\s*(?!&)\S",
    r"\btee\b",
    r"\b(rm|mv|cp|touch|mkdir|chmod|chown)\b",
    r"\bgit\s+(add|commit|push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)\b",
    r"\bsed\s+-i\b",
]
OLD_OTHER_WRITE_PATTERNS = [
    r"\btee\b",
    r"\b(rm|mv|cp|touch|mkdir|chmod|chown)\b",
    r"\bgit\s+(push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)\b",
    r"\bsed\s+-i\b",
]
OLD_DESTRUCTIVE_BASH_PATTERN = (
    r"\b(rm|mv|cp|git\s+(add|commit|push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)"
    r"|sed\s+-i|tee)\b"
)

R = chr(62)
VERBS = ["rm", "mv", "cp", "touch", "mkdir", "chmod", "chown", "tee", "ln", "dd", "rsync", "cat", "grep"]
GIT_SUBS = ["add", "commit", "push", "checkout", "switch", "reset", "restore", "clean", "stash", "merge",
            "rebase", "rm", "mv", "status", "log", "diff", "show", "fetch", "addx", "commits"]
SAMPLES = []
for v in VERBS:
    SAMPLES += [v + " a b", "x; " + v + " -f a", "my" + v + " a", v + "x a", "/bin/" + v + " a", "echo " + v]
for s in GIT_SUBS:
    SAMPLES += ["git " + s + " a", "git  " + s, "git\t" + s + " -x", "git -C . " + s, "xgit " + s]
SAMPLES += [
    "sed -i s/a/b/ f", "sed -i.bak s/a/b/ f", "sed -n p f", "sed  -i f", "sed -ie x f",
    "echo x " + R + " f", "echo x " + R + R + " f", "echo x" + R + "f", "cmd 2" + R + "&1", "cmd " + R + "&2",
    "cmd " + R + " &2", "a <" + R + " b", "a " + R + R + R + " b", R + " f", "echo x " + R,
    "cat <<EOF", "grep -c x README.md", "ls -la", "", "tee", "teeth", "git", "rmdir a",
]

mismatch = 0
for name, old, new in [
    ("BASH_WRITE_PATTERNS", OLD_BASH_WRITE_PATTERNS, G.BASH_WRITE_PATTERNS),
    ("OTHER_WRITE_PATTERNS", OLD_OTHER_WRITE_PATTERNS, G.OTHER_WRITE_PATTERNS),
    ("DESTRUCTIVE_BASH_PATTERN", [OLD_DESTRUCTIVE_BASH_PATTERN], [G.DESTRUCTIVE_BASH_PATTERN]),
]:
    for s in SAMPLES:
        a = any(re.search(p, s) for p in old)
        b = any(re.search(p, s) for p in new)
        if a != b:
            mismatch += 1
            print(f"{name}: {s!r}")
print(f"pattern_mismatch={mismatch}")
print(f"samples={len(SAMPLES)}")
