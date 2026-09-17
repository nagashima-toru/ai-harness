#!/usr/bin/env python3
"""Stop フック：verdict を見て作業終了の可否を判定する。状態は書き換えない。

入力  : stdin に Claude Code の Stop フック JSON
出力  : ブロック時は stdout に {"decision": "block", "reason": "..."}、許可時は何も出さず exit 0
環境  : HARNESS_MAX_ATTEMPTS（既定 3）、HARNESS_STRICT_STOP=1 で stop_hook_active を無視
"""
import json
import os
import re
import sys

MAX_ATTEMPTS = int(os.environ.get("HARNESS_MAX_ATTEMPTS", "3"))
STRICT = os.environ.get("HARNESS_STRICT_STOP", "0") == "1"


def project_dir(payload):
    for cand in (os.environ.get("CLAUDE_PROJECT_DIR"), payload.get("cwd")):
        if cand and os.path.isfile(os.path.join(cand, "vault", "todo.md")):
            return cand
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def parse_tasks(todo_text):
    """todo.md の「## タスク」表を読み、行を dict のリストで返す。"""
    rows = []
    in_tasks = False
    for line in todo_text.splitlines():
        if line.startswith("## "):
            in_tasks = line.strip() == "## タスク"
            continue
        if not in_tasks or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 5 or cells[0] == "id" or re.fullmatch(r"-*", cells[0]):
            continue
        cells += [""] * (6 - len(cells))
        rows.append({
            "id": cells[0], "status": cells[1], "attempt": cells[2],
            "after": cells[3], "title": cells[4], "question": cells[5],
        })
    return rows


def count_acceptance_criteria(task_path):
    """タスク票の「## 受け入れ基準」節にある行頭 `- ` の行数を返す（ネストは数えない）。"""
    with open(task_path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    in_section = False
    count = 0
    for line in lines:
        if line.startswith("## "):
            in_section = line.strip() == "## 受け入れ基準"
            continue
        if in_section and line.startswith("- "):
            count += 1
    return count


def validate_verdict(verdict, tid, root):
    """verdict の形式を検査し、不正な点の説明リストを返す（空なら正常）。"""
    problems = []
    result = verdict.get("result")
    if str(result).upper() not in ("PASS", "FAIL"):
        problems.append(f"result が PASS/FAIL 以外です（{result!r}）")
    criteria = verdict.get("criteria")
    if not isinstance(criteria, list):
        problems.append("criteria が配列ではありません")
    else:
        for i, c in enumerate(criteria):
            if not isinstance(c, dict):
                problems.append(f"criteria[{i}] が辞書ではありません")
                continue
            if not all(k in c for k in ("text", "ok", "note")):
                problems.append(f"criteria[{i}] に text/ok/note のいずれかがありません")
                continue
            note = c.get("note")
            if not isinstance(note, str) or not note.strip():
                problems.append(f"criteria[{i}].note が空です")
        task_path = os.path.join(root, "vault", "tasks", tid + ".md")
        if os.path.isfile(task_path):
            expected = count_acceptance_criteria(task_path)
            if len(criteria) != expected:
                problems.append(
                    f"criteria の行数（{len(criteria)}）がタスク票の受け入れ基準の行数（{expected}）と一致しません"
                )
    if not isinstance(verdict.get("reasons"), list):
        problems.append("reasons が配列ではありません")
    return problems


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
    sys.exit(0)


def allow():
    sys.exit(0)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    if payload.get("stop_hook_active") and not STRICT:
        allow()

    root = project_dir(payload)
    todo_path = os.path.join(root, "vault", "todo.md")
    if not os.path.isfile(todo_path):
        allow()

    with open(todo_path, encoding="utf-8") as f:
        tasks = parse_tasks(f.read())

    active = next((t for t in tasks if t["status"] in ("doing", "review")), None)
    if active is None:
        allow()

    tid = active["id"]
    status = active["status"]
    try:
        attempt = int(active["attempt"])
    except ValueError:
        attempt = 0

    verdict_path = os.path.join(root, "vault", "verdicts", tid + ".json")
    verdict = None
    if os.path.isfile(verdict_path):
        try:
            with open(verdict_path, encoding="utf-8") as f:
                verdict = json.load(f)
        except Exception:
            verdict = None

    stale = verdict is not None and (
        verdict.get("task") != tid or str(verdict.get("attempt")) != str(attempt)
    )
    if verdict is None or stale:
        why = "verdict が古い（task/attempt が todo.md と不一致）" if stale else "verdict が無い"
        block(
            f"[stop_gate] {tid} は {status} ですが {why}。"
            f"verifier サブエージェントを実行して vault/verdicts/{tid}.json を書くこと"
            f"（attempt={attempt}）。"
        )

    problems = validate_verdict(verdict, tid, root)
    if problems:
        block(
            f"[stop_gate] {tid} の verdict の形式が不正です: {'; '.join(problems)}。"
            f"verifier サブエージェントを再実行して vault/verdicts/{tid}.json を書き直すこと（attempt={attempt}）。"
        )

    result = str(verdict.get("result", "")).upper()
    reasons = verdict.get("reasons") or []
    reasons_text = " / ".join(str(r) for r in reasons) if reasons else "（理由なし）"

    if result == "PASS":
        if status == "done":
            allow()
        block(
            f"[stop_gate] {tid} の verdict は PASS ですが status が {status} です。"
            f"vault/todo.md の status を done にし、vault/log/queue.md に1行追記すること。"
        )

    # FAIL（または不明な result は FAIL 扱い）
    if attempt < MAX_ATTEMPTS:
        block(
            f"[stop_gate] {tid} の verdict は FAIL（attempt={attempt}/{MAX_ATTEMPTS}）。理由: {reasons_text}。"
            f"vault/todo.md の status を doing に戻し attempt を {attempt + 1} にして修正し、"
            f"タスク票の「進捗」に追記してから、再度 review にして verifier を実行すること。"
        )
    block(
        f"[stop_gate] {tid} の verdict は FAIL で試行上限（{MAX_ATTEMPTS}）に達しました。理由: {reasons_text}。"
        f"vault/todo.md の status を blocked にし、question 列に人へ聞くこと（理由の要約）を書き、"
        f"vault/log/queue.md に1行追記すること。"
    )


if __name__ == "__main__":
    main()
