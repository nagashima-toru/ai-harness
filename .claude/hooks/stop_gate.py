#!/usr/bin/env python3
"""Stop フック：verdict を見て作業終了の可否を判定する。状態は書き換えない。

自分のブランチの計画票（vault/plans/*.md のうち status: approved の1件）のタスク表と
vault/verdicts/<計画ID>/<タスクID>.json を読んで判定する。

入力  : stdin に Claude Code の Stop フック JSON
出力  : ブロック時は stdout に {"decision": "block", "reason": "..."}、許可時は何も出さず exit 0
環境  : HARNESS_MAX_ATTEMPTS（既定 3）、HARNESS_STRICT_STOP=1 で stop_hook_active を無視

worktree 委譲：payload["cwd"] が自リポジトリと異なる git worktree を指す場合、そのルート配下の
同名スクリプト（.claude/hooks/stop_gate.py）へ判定を委譲する（issue #56 / D-008 フェーズ2）。
タスク表と受け入れ基準の読み方は `_hooklib.py` の `parse_tasks`・`count_criteria` を使う。
委譲の実装は共通モジュール `_hooklib.py` の `delegate_to_worktree` を使う。
`_hooklib` が読み込めない時は、標準エラーに理由を出して終了コード2で終わる
（`stop_hook_active` が真で `HARNESS_STRICT_STOP` が `1` でなければ0）。
"""
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import _hooklib as H
except Exception as e:  # SyntaxError なども含めて捕まえる
    sys.stderr.write(f"[stop_gate] _hooklib の読み込みに失敗しました: {e}\n")
    try:
        _payload = json.load(sys.stdin)
    except Exception:
        _payload = {}
    if isinstance(_payload, dict) and _payload.get("stop_hook_active") and os.environ.get("HARNESS_STRICT_STOP", "0") != "1":
        sys.exit(0)
    sys.exit(2)

MAX_ATTEMPTS = int(os.environ.get("HARNESS_MAX_ATTEMPTS", "3"))
STRICT = os.environ.get("HARNESS_STRICT_STOP", "0") == "1"


def project_dir(payload):
    for cand in (os.environ.get("CLAUDE_PROJECT_DIR"), payload.get("cwd")):
        if cand and os.path.isdir(os.path.join(cand, "vault", "plans")):
            return cand
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def has_uncommitted_changes(root):
    """作業ツリーに未コミットの変更があるか。非 git リポジトリ・取得不能なら False（fail-open）。
    worktree（`.git` がファイル）でも判定する。"""
    try:
        inside = subprocess.run(
            ["git", "-C", root, "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return False
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        return False
    try:
        out = subprocess.run(
            ["git", "-C", root, "status", "--porcelain"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return False
    if out.returncode != 0:
        return False
    return bool(out.stdout.strip())


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
            with open(task_path, encoding="utf-8") as f:
                expected = H.count_criteria(f.read())
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

    delegated_stdout = H.delegate_to_worktree(payload, "stop_gate.py")
    if delegated_stdout is not None:
        sys.stdout.write(delegated_stdout)
        sys.exit(0)

    if payload.get("stop_hook_active") and not STRICT:
        allow()

    root = project_dir(payload)

    if has_uncommitted_changes(root):
        block(
            "[stop_gate] 未コミットの変更があります。"
            "作業ステップごとにコミットしてから終了してください（git status --porcelain の出力を確認）。"
        )

    plans = H.approved_plans(root)

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
        tasks = H.parse_tasks(f.read())

    active_tasks = [t for t in tasks if t["status"] in ("doing", "review")]
    if not active_tasks:
        allow()

    # doing/review は着手可能集合に限り複数件になりうる（2節）。タスク表の出現順（上から）に
    # 1件ずつ検査し、最初に許可できないと判定した行が見つかった時点でその行の理由を block() で
    # 返して以降の行は検査しない。全行が問題無ければループを最後まで回して allow() する。
    for active in active_tasks:
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
                continue
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

    allow()


if __name__ == "__main__":
    main()
