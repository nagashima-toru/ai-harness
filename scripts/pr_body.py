#!/usr/bin/env python3
"""計画のタスク履歴表を PR/MR 本文用の Markdown として標準出力に出す。

使い方: python3 scripts/pr_body.py <計画ID> [<rev>]
<rev> は done コミットを探す起点（省略時は HEAD）。ファイルには書き込まない。
done コミットの件名は `<計画ID>/<id>: done`（従来）と transition.py の
`<計画ID>/<id>: review→done`（複数 id は `<計画ID>/T-01,T-02: review→done`）の両方を探す。
"""
import json
import os
import re
import subprocess
import sys


def repo_root():
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    except OSError:
        return os.getcwd()
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    return os.getcwd()


def split_row(line):
    cells = re.split(r"(?<!\\)\|", line.strip())
    if cells and cells[0] == "":
        cells = cells[1:]
    if cells and cells[-1] == "":
        cells = cells[:-1]
    return [c.strip() for c in cells]


def parse_tasks(text):
    """タスク表の (id, title) を表の順に返す。"""
    tasks = []
    in_table = False
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            if in_table:
                break
            continue
        cells = split_row(s)
        if not in_table:
            if cells[:4] == ["id", "status", "attempt", "after"]:
                in_table = True
            continue
        if cells and set("".join(cells)) <= set("-: "):
            continue
        if len(cells) >= 5 and cells[0].startswith("T-"):
            tasks.append((cells[0], cells[4].replace("\\|", "|")))
    return tasks


def ere_escape(s):
    """ERE の特殊文字の前にバックスラッシュを付ける（re.escape は使わない）。"""
    return re.sub(r"([.\[\]()*+?{}|^$\\])", r"\\\1", s)


def commit_of(plan_id, task_id, rev):
    pattern = "^%s/([^:]*,)?%s(,[^:]*)?: (review→)?done$" % (
        ere_escape(plan_id), ere_escape(task_id))
    try:
        r = subprocess.run(
            ["git", "log", "--format=%h", "-n", "1", "--extended-regexp",
             "--grep=" + pattern, rev],
            capture_output=True, text=True)
    except OSError:
        return "-"
    out = r.stdout.strip()
    if r.returncode != 0 or not out:
        return "-"
    return out.splitlines()[0]


def verdict_of(root, plan_id, task_id):
    path = os.path.join(root, "vault", "verdicts", plan_id, task_id + ".json")
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        result, attempt = d["result"], d["attempt"]
    except (OSError, ValueError, KeyError, TypeError):
        return "-"
    return "%s (attempt=%s)" % (result, attempt)


def main(argv):
    if len(argv) not in (2, 3):
        sys.stderr.write("使い方: python3 scripts/pr_body.py <計画ID> [<rev>]\n")
        return 2
    plan_id = argv[1]
    rev = argv[2] if len(argv) == 3 else "HEAD"
    root = repo_root()
    plan_rel = "vault/plans/%s.md" % plan_id
    try:
        with open(os.path.join(root, plan_rel), encoding="utf-8") as f:
            text = f.read()
    except OSError:
        sys.stderr.write("pr_body.py: 計画票がありません: %s\n" % plan_rel)
        return 1

    lines = [
        "## タスク履歴",
        "",
        "計画: `%s`（計画票 `%s`、ログ `vault/log/%s.md`）" % (plan_id, plan_rel, plan_id),
        "",
        "| id | title | commit | verdict |",
        "|---|---|---|---|",
    ]
    for tid, title in parse_tasks(text):
        lines.append("| %s | %s | %s | %s |" % (
            tid, title.replace("|", "\\|"),
            commit_of(plan_id, tid, rev), verdict_of(root, plan_id, tid)))
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
