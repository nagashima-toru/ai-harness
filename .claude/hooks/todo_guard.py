#!/usr/bin/env python3
"""PostToolUse フック：vault/todo.md の整合性を検査する。

検出する壊れ方：
  (a) status が doing の行が2件以上
  (b) status が blocked なのに question 列が空
  (c) status が todo / doing / review / blocked / done 以外
  (d) 「## タスク」表に id の重複がある
  (e) 「## タスク」表のデータ行の列数が6でない

vault/todo.md が無い場合、および表にデータ行が無い場合は何もせず許可する。
出力：壊れていれば {"decision": "block", "reason": "..."}、正常なら何も出さず exit 0。
"""
import json
import os
import re
import sys

STATUSES = ("todo", "doing", "review", "blocked", "done")
COLUMNS = ("id", "status", "attempt", "after", "title", "question")


def project_dir(payload):
    cand = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
    if cand:
        return cand
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def raw_rows(todo_text):
    """「## タスク」表のデータ行を生のセルのリストで返す（見出し行・区切り行は除く）。"""
    rows = []
    in_tasks = False
    for line in todo_text.splitlines():
        if line.startswith("## "):
            in_tasks = line.strip() == "## タスク"
            continue
        stripped = line.strip()
        if not in_tasks or not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or cells[0] == "id" or re.fullmatch(r"-*", cells[0]):
            continue
        rows.append(cells)
    return rows


def parse_tasks(todo_text):
    """stop_gate.py と同じ規則で行を dict にする（6列に満たない分は空文字で埋める）。"""
    tasks = []
    for cells in raw_rows(todo_text):
        if len(cells) < 5:
            continue
        cells = list(cells) + [""] * (6 - len(cells))
        tasks.append(dict(zip(COLUMNS, cells[:6])))
    return tasks


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    root = project_dir(payload)
    todo_path = os.path.join(root, "vault", "todo.md")
    if not os.path.isfile(todo_path):
        sys.exit(0)
    try:
        with open(todo_path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        sys.exit(0)

    rows = raw_rows(text)
    if not rows:
        sys.exit(0)

    for cells in rows:
        if len(cells) != 6:
            label = cells[0] if cells else "(id 不明)"
            block(
                f"[todo_guard] {label} の行の列数が{len(cells)}です。"
                f"id/status/attempt/after/title/question の6列にしてください。"
            )

    tasks = parse_tasks(text)

    for t in tasks:
        if t["status"] not in STATUSES:
            block(
                f"[todo_guard] {t['id']} の status が '{t['status']}' です。"
                f"todo/doing/review/blocked/done のいずれかにしてください。"
            )

    doing = [t["id"] for t in tasks if t["status"] == "doing"]
    if len(doing) >= 2:
        block(
            f"[todo_guard] doing の行が{len(doing)}件あります（{', '.join(doing)}）。"
            f"doing は常に1件です。1件だけ残し、他は todo か review に戻してください。"
        )

    for t in tasks:
        if t["status"] == "blocked" and not t["question"]:
            block(
                f"[todo_guard] {t['id']} が blocked なのに question 列が空です。"
                f"question 列に人へ聞くことを書いてください。"
            )

    seen = set()
    for t in tasks:
        if t["id"] in seen:
            block(f"[todo_guard] id {t['id']} が重複しています。id は一意にしてください。")
        seen.add(t["id"])

    sys.exit(0)


if __name__ == "__main__":
    main()
