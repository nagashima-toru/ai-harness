#!/usr/bin/env python3
"""PostToolUse フック：自分のブランチの計画票（vault/plans/*.md のうち status: approved の1件）
のタスク表の整合性を検査する。

検出する壊れ方：
  (a) status が doing の行が2件以上
  (b) status が blocked なのに question 列が空
  (c) status が todo / doing / review / blocked / done 以外
  (d) 「## タスク表」に id の重複がある
  (e) 「## タスク表」のデータ行の列数が6でない

加えて、1ブランチ1計画の不変条件を検査する：
  (f) approved な計画票が2件以上ある

approved な計画票が0件、および表にデータ行が無い場合は何もせず許可する。
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


def plan_id_and_status(path):
    """計画票の frontmatter から (id, status) を返す。読めない・frontmatter が無ければ (None, None)。"""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None, None
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        return None, None
    front = m.group(1)
    id_m = re.search(r"^id:\s*(\S+)\s*$", front, re.MULTILINE)
    status_m = re.search(r"^status:\s*(\S+)\s*$", front, re.MULTILINE)
    plan_id = id_m.group(1) if id_m else os.path.basename(path)[: -len(".md")]
    status = status_m.group(1) if status_m else None
    return plan_id, status


def approved_plans(root):
    """vault/plans/*.md のうち status: approved のもの一覧を [(plan_id, path), ...] で返す。"""
    plans_dir = os.path.join(root, "vault", "plans")
    if not os.path.isdir(plans_dir):
        return []
    out = []
    for name in sorted(os.listdir(plans_dir)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(plans_dir, name)
        plan_id, status = plan_id_and_status(path)
        if status == "approved":
            out.append((plan_id, path))
    return out


def raw_rows(plan_text):
    """「## タスク表」（前方一致）以降のデータ行を生のセルのリストで返す（見出し行・区切り行は除く）。"""
    rows = []
    in_table = False
    for line in plan_text.splitlines():
        if line.startswith("## "):
            in_table = line.strip().startswith("## タスク表")
            continue
        stripped = line.strip()
        if not in_table or not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or cells[0] == "id" or re.fullmatch(r"-*", cells[0]):
            continue
        rows.append(cells)
    return rows


def parse_tasks(plan_text):
    """stop_gate.py と同じ規則で行を dict にする（6列に満たない分は空文字で埋める）。"""
    tasks = []
    for cells in raw_rows(plan_text):
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
    plans = approved_plans(root)

    if len(plans) == 0:
        sys.exit(0)

    if len(plans) >= 2:
        ids = ", ".join(pid for pid, _ in plans)
        block(
            f"[plan_guard] approved な計画票が{len(plans)}件あります（{ids}）。"
            f"1ブランチにつき approved は1件にしてください。"
        )

    plan_id, plan_path = plans[0]
    try:
        with open(plan_path, encoding="utf-8") as f:
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
                f"[plan_guard] {plan_id} の {label} の行の列数が{len(cells)}です。"
                f"id/status/attempt/after/title/question の6列にしてください。"
            )

    tasks = parse_tasks(text)

    for t in tasks:
        if t["status"] not in STATUSES:
            block(
                f"[plan_guard] {plan_id} の {t['id']} の status が '{t['status']}' です。"
                f"todo/doing/review/blocked/done のいずれかにしてください。"
            )

    doing = [t["id"] for t in tasks if t["status"] == "doing"]
    if len(doing) >= 2:
        block(
            f"[plan_guard] {plan_id} で doing の行が{len(doing)}件あります（{', '.join(doing)}）。"
            f"doing は常に1件です。1件だけ残し、他は todo か review に戻してください。"
        )

    for t in tasks:
        if t["status"] == "blocked" and not t["question"]:
            block(
                f"[plan_guard] {plan_id} の {t['id']} が blocked なのに question 列が空です。"
                f"question 列に人へ聞くことを書いてください。"
            )

    seen = set()
    for t in tasks:
        if t["id"] in seen:
            block(f"[plan_guard] {plan_id} で id {t['id']} が重複しています。id は一意にしてください。")
        seen.add(t["id"])

    sys.exit(0)


if __name__ == "__main__":
    main()
