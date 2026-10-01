#!/usr/bin/env python3
"""log から creator のモデル別に集計してタブ区切りで標準出力に出す。

使い方:
  python3 scripts/model_stats.py [log ファイル ...]
  引数が無ければ vault/log/*.md（vault/archive/ 配下は含めない）を対象にする。

定義は docs/vault-spec.md 7節を参照。
"""
import glob
import os
import re
import sys

LINE_RE = re.compile(
    r"^- \d{4}-\d{2}-\d{2} \d{2}:\d{2} (\S+) (\w+)→(\w+)(?:\s+(.*))?$"
)
ATTEMPT_RE = re.compile(r"(?:^|\s)attempt=(\d+)")
CREATOR_RE = re.compile(r"(?:^|\s)creator=(\S+)")
HEADER = "model\ttasks\tfirst_pass_rate\tavg_attempt\tblocked_rate"


def default_logs():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return sorted(glob.glob(os.path.join(root, "vault", "log", "*.md")))


def collect(paths):
    """{計画ID/id: {"last": (from, to, attempt), "creator": str|None}} を返す。"""
    tasks = {}
    for path in paths:
        plan = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as f:
            for raw in f:
                m = LINE_RE.match(raw.rstrip("\n"))
                if not m:
                    continue
                tid, src, dst, rest = m.group(1), m.group(2), m.group(3), m.group(4) or ""
                if tid == "-":
                    continue
                am = ATTEMPT_RE.search(rest)
                attempt = int(am.group(1)) if am else None
                t = tasks.setdefault(f"{plan}/{tid}", {"last": None, "creator": None})
                t["last"] = (src, dst, attempt)
                if src == "doing" and dst == "review":
                    cm = CREATOR_RE.search(rest)
                    t["creator"] = cm.group(1) if cm else None
    return tasks


def main(argv):
    paths = argv[1:] if len(argv) > 1 else default_logs()
    tasks = collect(paths)
    groups = {}
    for t in tasks.values():
        src, dst, attempt = t["last"]
        if dst not in ("done", "blocked"):
            continue
        g = groups.setdefault(
            t["creator"] or "unknown",
            {"n": 0, "first": 0, "attempts": [], "blocked": 0},
        )
        g["n"] += 1
        if dst == "done" and src == "review" and attempt == 1:
            g["first"] += 1
        if dst == "blocked":
            g["blocked"] += 1
        g["attempts"].append(attempt if attempt is not None else 1)
    print(HEADER)
    for model in sorted(groups):
        g = groups[model]
        n = g["n"]
        print(
            "\t".join(
                [
                    model,
                    str(n),
                    f"{g['first'] / n:.2f}",
                    f"{sum(g['attempts']) / n:.2f}",
                    f"{g['blocked'] / n:.2f}",
                ]
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
