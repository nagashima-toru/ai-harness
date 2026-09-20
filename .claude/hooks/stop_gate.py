#!/usr/bin/env python3
"""Stop フック：verdict を見て作業終了の可否を判定する。状態は書き換えない。

自分のブランチの計画票（vault/plans/*.md のうち status: approved の1件）のタスク表と
vault/verdicts/<計画ID>/<タスクID>.json を読んで判定する。

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
        if cand and os.path.isdir(os.path.join(cand, "vault", "plans")):
            return cand
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def plan_id_and_status(path):
    """計画票の frontmatter から (id, status) を返す。読めない・frontmatter が無ければ (None, None)。
    plan_guard.py と同じ規則をこのファイル内にコピーして使う（import はしない）。"""
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


def parse_tasks(plan_text):
    """計画票の「## タスク表」（前方一致）以降の行を dict のリストで返す。"""
    rows = []
    in_table = False
    for line in plan_text.splitlines():
        if line.startswith("## "):
            in_table = line.strip().startswith("## タスク表")
            continue
        if not in_table or not line.startswith("|"):
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


def validate_verdict(verdict, expected_task, task_path):
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
    plans = approved_plans(root)

    if len(plans) == 0:
        allow()

    if len(plans) >= 2:
        ids = ", ".join(pid for pid, _ in plans)
        block(
            f"[stop_gate] approved な計画票が{len(plans)}件あります（{ids}）。"
            f"1つだけ approved にしてください。"
        )

    plan_id, plan_path = plans[0]
    with open(plan_path, encoding="utf-8") as f:
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

    task_key = f"{plan_id}/{tid}"
    task_path = os.path.join(root, "vault", "tasks", plan_id, tid + ".md")
    verdict_path = os.path.join(root, "vault", "verdicts", plan_id, tid + ".json")
    verdict = None
    if os.path.isfile(verdict_path):
        try:
            with open(verdict_path, encoding="utf-8") as f:
                verdict = json.load(f)
        except Exception:
            verdict = None

    stale = verdict is not None and (
        verdict.get("task") != task_key or str(verdict.get("attempt")) != str(attempt)
    )
    if verdict is None or stale:
        why = "verdict が古い（task/attempt が計画票のタスク表と不一致）" if stale else "verdict が無い"
        block(
            f"[stop_gate] {task_key} は {status} ですが {why}。"
            f"verifier サブエージェントを実行して vault/verdicts/{task_key}.json を書くこと"
            f"（attempt={attempt}）。"
        )

    problems = validate_verdict(verdict, task_key, task_path)
    if problems:
        block(
            f"[stop_gate] {task_key} の verdict の形式が不正です: {'; '.join(problems)}。"
            f"verifier サブエージェントを再実行して vault/verdicts/{task_key}.json を書き直すこと（attempt={attempt}）。"
        )

    result = str(verdict.get("result", "")).upper()
    reasons = verdict.get("reasons") or []
    reasons_text = " / ".join(str(r) for r in reasons) if reasons else "（理由なし）"

    if result == "PASS":
        if status == "done":
            allow()
        block(
            f"[stop_gate] {task_key} の verdict は PASS ですが status が {status} です。"
            f"計画票（vault/plans/{plan_id}.md）のタスク表の status を done にし、vault/log/{plan_id}.md に1行追記すること。"
        )

    # FAIL（または不明な result は FAIL 扱い）
    if attempt < MAX_ATTEMPTS:
        block(
            f"[stop_gate] {task_key} の verdict は FAIL（attempt={attempt}/{MAX_ATTEMPTS}）。理由: {reasons_text}。"
            f"計画票（vault/plans/{plan_id}.md）のタスク表の status を doing に戻し attempt を {attempt + 1} にして修正し、"
            f"タスク票の「進捗」に追記してから、再度 review にして verifier を実行すること。"
        )
    block(
        f"[stop_gate] {task_key} の verdict は FAIL で試行上限（{MAX_ATTEMPTS}）に達しました。理由: {reasons_text}。"
        f"計画票（vault/plans/{plan_id}.md）のタスク表の status を blocked にし、question 列に人へ聞くこと（理由の要約）を書き、"
        f"vault/log/{plan_id}.md に1行追記すること。"
    )


if __name__ == "__main__":
    main()
