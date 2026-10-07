#!/usr/bin/env python3
"""PostToolUse フック：自分のブランチの計画票（vault/plans/*.md のうち status: approved の1件）
のタスク表の整合性を検査する。

検出する壊れ方：
  (a) doing/review の行の `after` 列に、まだ done でない他の doing/review 行の id が含まれる
      （依存の無い集合＝着手可能集合に限り doing/review は複数件になりうるが、依存が残ったまま
      doing/review になっている行があってはならない）
  (b) status が blocked なのに question 列が空
  (c) status が todo / doing / review / blocked / done 以外
  (d) 「## タスク表」に id の重複がある
  (e) 「## タスク表」のデータ行の列数が6でない
  (g) status が done の行に、attempt が一致する正しい PASS の verdict が無い

加えて、1ブランチ1計画の不変条件を検査する：
  (f) approved な計画票が2件以上ある

approved な計画票が0件、および表にデータ行が無い場合は何もせず許可する。
出力：壊れていれば {"decision": "block", "reason": "..."}、正常なら何も出さず exit 0。

worktree 委譲：payload["cwd"] が自リポジトリと異なる git worktree を指す場合、そのルート配下の
同名スクリプト（.claude/hooks/plan_guard.py）へ判定を委譲する（issue #56 / D-008 フェーズ2）。
委譲の実装は共通モジュール `_hooklib.py` の `delegate_to_worktree` を使う。
タスク表の行の解釈（`parse_tasks`）と受け入れ基準の行数（`count_criteria`）も `_hooklib.py` のものを使う。
`_hooklib` を読み込めない時は、理由を標準エラーに出して終了コード2で終わる。
"""
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import _hooklib as H
except Exception as e:  # SyntaxError なども含めて捕まえる
    sys.stderr.write(f"[plan_guard] _hooklib の読み込みに失敗しました: {e}\n")
    sys.exit(2)

STATUSES = ("todo", "doing", "review", "blocked", "done")


def project_dir(payload):
    cand = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
    if cand:
        return cand
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def dependency_violations(tasks):
    """doing/review の行のうち、`after` が指す依存先がまだ done でないものを [(id, dep_id, dep_status), ...] で返す。

    `after` はカンマ区切りの id リスト（`-` は依存無し）。依存先の id がタスク表に無い場合は
    無視する（存在しない id を参照する不整合は別の検査の対象ではないため、ここではブロックしない）。
    """
    by_id = {t["id"]: t for t in tasks}
    violations = []
    for t in tasks:
        if t["status"] not in ("doing", "review"):
            continue
        for dep_id in (a.strip() for a in t["after"].split(",")):
            if not dep_id or dep_id == "-":
                continue
            dep = by_id.get(dep_id)
            if dep is not None and dep["status"] != "done":
                violations.append((t["id"], dep_id, dep["status"]))
    return violations


TASK_PATH_RE = re.compile(r"^vault/tasks/([^/]+)/(T-\d{2})\.md$")
CRITERIA_MIN, CRITERIA_MAX = 3, 7


def granularity_violation(payload, root):
    """draft 計画のタスク票への Write/Edit で受け入れ基準が3〜7行でなければ理由文を返す。対象外・問題なしは None。

    fail-open：計画票が無い・読めない・status が取れない・タスク票が読めない場合は None。
    """
    if payload.get("tool_name") not in ("Write", "Edit"):
        return None
    tool_input = payload.get("tool_input")
    file_path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if not isinstance(file_path, str) or not file_path:
        return None
    if os.path.isabs(file_path):
        rel = os.path.relpath(file_path, os.path.abspath(root))
    else:
        rel = os.path.normpath(file_path)
    m = TASK_PATH_RE.match(rel.replace(os.sep, "/"))
    if not m:
        return None
    plan_id, task_id = m.group(1), m.group(2)
    _, status = H.plan_id_and_status(os.path.join(root, "vault", "plans", plan_id + ".md"))
    if status != "draft":
        return None
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None
    n = H.count_criteria(text)
    if CRITERIA_MIN <= n <= CRITERIA_MAX:
        return None
    return (
        f"[plan_guard] {plan_id}/{task_id} の受け入れ基準が{n}行です。"
        f"{CRITERIA_MIN}〜{CRITERIA_MAX}行にしてください。"
    )


PLAN_PATH_RE = re.compile(r"^vault/plans/([^/]+)\.md$")
PLAN_ROWS_MAX = 7


def plan_size_violation(payload, root):
    """draft 計画票への Write/Edit でタスク表のデータ行が7行を超えれば理由文を返す。対象外・問題なしは None。

    fail-open：計画票が読めない・status が取れない場合は None。行数は raw_rows と同じ規則で数える。
    """
    if payload.get("tool_name") not in ("Write", "Edit"):
        return None
    tool_input = payload.get("tool_input")
    file_path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if not isinstance(file_path, str) or not file_path:
        return None
    if os.path.isabs(file_path):
        rel = os.path.relpath(file_path, os.path.abspath(root))
    else:
        rel = os.path.normpath(file_path)
    rel = rel.replace(os.sep, "/")
    m = PLAN_PATH_RE.match(rel)
    if not m:
        return None
    path = os.path.join(root, rel)
    _, status = H.plan_id_and_status(path)
    if status != "draft":
        return None
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None
    n = len(H.raw_rows(text))
    if n <= PLAN_ROWS_MAX:
        return None
    return (
        f"[plan_guard] {m.group(1)} のタスク表が{n}行です。1計画は{PLAN_ROWS_MAX}タスク以下にしてください。"
        f"超える分は次フェーズの候補として計画票の末尾に書くだけにしてください。"
    )


def newly_approved_plans(root):
    """作業ツリーで approved かつ HEAD では approved でない計画票を [(plan_id, file_name), ...] で返す。

    HEAD の取得失敗（HEAD 無し・未追跡）は「HEAD では approved でない」として扱う。
    非 git ディレクトリ・git が使えない場合は空リスト（何もしない）。
    """
    plans_dir = os.path.join(root, "vault", "plans")
    if not os.path.isdir(plans_dir):
        return []
    try:
        inside = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True, timeout=5, cwd=root,
        )
    except Exception:
        return []
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        return []
    out = []
    for name in sorted(os.listdir(plans_dir)):
        if not name.endswith(".md"):
            continue
        plan_id, status = H.plan_id_and_status(os.path.join(plans_dir, name))
        if status != "approved":
            continue
        head_status = None
        try:
            shown = subprocess.run(
                ["git", "show", f"HEAD:./vault/plans/{name}"],
                capture_output=True, text=True, timeout=5, cwd=root,
            )
            if shown.returncode == 0:
                head_status = H.frontmatter_status(shown.stdout)
        except Exception:
            pass
        if head_status != "approved":
            out.append((plan_id, name))
    return out


def approval_check(payload, root):
    """今回承認された計画票の裏付けを会話記録で検査する。(block 理由 or None, 警告 or None) を返す。"""
    warnings = []
    transcript_path = payload.get("transcript_path")
    humans = None
    for plan_id, _name in newly_approved_plans(root):
        if humans is None:
            humans = H.human_messages(transcript_path if isinstance(transcript_path, str) else None)
        if not humans:
            warnings.append(
                f"[plan_guard] {plan_id} が draft から approved に書き換えられていますが、"
                f"会話記録が読めないため承認の裏付けを検査できませんでした。"
                f"人が /plan approve {plan_id} で指示した時だけ承認できます。"
            )
            continue
        if not any(H.is_approve_command(t, plan_id) for t in humans):
            return (
                f"[plan_guard] {plan_id} が draft から approved に書き換えられていますが、"
                f"人の /plan approve {plan_id} の指示が会話記録にありません。"
                f"git restore vault/plans/{plan_id}.md で元に戻してください"
                f"（承認は人が /plan approve {plan_id} で指示した時だけ行えます）。"
            ), None
    return None, ("\n".join(warnings) if warnings else None)


def unblocked_rows(root):
    """作業ツリーで blocked でなく、HEAD では blocked だった行を [(plan_id, file_name, task_id), ...] で返す。

    対象は計画票すべて。HEAD の取得失敗（HEAD 無し・未追跡）は blocked の行が無い扱い。
    作業ツリーに同じ id の行が無ければ検査しない。非 git ディレクトリ・git が使えない場合は空リスト。
    """
    plans_dir = os.path.join(root, "vault", "plans")
    if not os.path.isdir(plans_dir):
        return []
    try:
        inside = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True, timeout=5, cwd=root,
        )
    except Exception:
        return []
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        return []
    out = []
    for name in sorted(os.listdir(plans_dir)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(plans_dir, name)
        try:
            shown = subprocess.run(
                ["git", "show", f"HEAD:./vault/plans/{name}"],
                capture_output=True, text=True, timeout=5, cwd=root,
            )
            if shown.returncode != 0:
                continue
            with open(path, encoding="utf-8") as f:
                current = f.read()
        except Exception:
            continue
        head_blocked = {c[0] for c in H.raw_rows(shown.stdout) if len(c) >= 2 and c[1] == "blocked"}
        if not head_blocked:
            continue
        plan_id, _ = H.plan_id_and_status(path)
        for cells in H.raw_rows(current):
            if len(cells) >= 2 and cells[0] in head_blocked and cells[1] != "blocked":
                out.append((plan_id, name, cells[0]))
    return out


def unblock_check(payload, root):
    """blocked の解除の裏付けを会話記録で検査する。(block 理由 or None, 警告 or None) を返す。"""
    warnings = []
    transcript_path = payload.get("transcript_path")
    humans = None
    for plan_id, _name, task_id in unblocked_rows(root):
        if humans is None:
            humans = H.human_messages(transcript_path if isinstance(transcript_path, str) else None)
        if not humans:
            warnings.append(
                f"[plan_guard] {plan_id}/{task_id} が blocked から書き換えられていますが、"
                f"会話記録が読めないため解除の裏付けを検査できませんでした。"
                f"人が /plan unblock {plan_id} {task_id} で指示した時だけ解除できます。"
            )
            continue
        if not any(H.is_unblock_command(t, plan_id, task_id) for t in humans):
            return (
                f"[plan_guard] {plan_id}/{task_id} が blocked から書き換えられていますが、"
                f"人の /plan unblock {plan_id} {task_id} の指示が会話記録にありません。"
                f"git restore vault/plans/{plan_id}.md で元に戻してください"
                f"（blocked の解除は人が /plan unblock {plan_id} {task_id} で指示した時だけ行えます）。"
            ), None
    return None, ("\n".join(warnings) if warnings else None)


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

    delegated_stdout = H.delegate_to_worktree(payload, "plan_guard.py")
    if delegated_stdout is not None:
        sys.stdout.write(delegated_stdout)
        sys.exit(0)

    root = project_dir(payload)

    violation = granularity_violation(payload, root)
    if violation:
        block(violation)

    violation = plan_size_violation(payload, root)
    if violation:
        block(violation)

    reason, warning = approval_check(payload, root)
    if reason:
        block(reason)
    reason2, warning2 = unblock_check(payload, root)
    if reason2:
        block(reason2)
    warning = "\n".join(w for w in (warning, warning2) if w) or None

    def finish():
        """終了経路。既存の検査がブロックしなかった時だけ、承認の裏付け警告を1回出して終わる。"""
        if warning:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PostToolUse", "additionalContext": warning}}, ensure_ascii=False))
        sys.exit(0)

    plans = H.approved_plans(root)

    if len(plans) == 0:
        finish()

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
        finish()

    rows = H.raw_rows(text)
    if not rows:
        finish()

    for cells in rows:
        if len(cells) != 6:
            label = cells[0] if cells else "(id 不明)"
            block(
                f"[plan_guard] {plan_id} の {label} の行の列数が{len(cells)}です。"
                f"id/status/attempt/after/title/question の6列にしてください。"
            )

    tasks = H.parse_tasks(text)

    for t in tasks:
        if t["status"] not in STATUSES:
            block(
                f"[plan_guard] {plan_id} の {t['id']} の status が '{t['status']}' です。"
                f"todo/doing/review/blocked/done のいずれかにしてください。"
            )

    violations = dependency_violations(tasks)
    if violations:
        detail = ", ".join(f"{tid}→{dep_id}({dep_status})" for tid, dep_id, dep_status in violations)
        block(
            f"[plan_guard] {plan_id} で doing/review の行に未完了の依存があります（{detail}）。"
            f"doing/review にできるのは after の依存が全て done な行（着手可能集合）だけです。"
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

    missing = H.done_rows_without_pass(root, plan_id, tasks)
    if missing:
        tid, why = missing[0]
        attempt = next((t["attempt"] for t in tasks if t["id"] == tid), "")
        block(
            f"[plan_guard] {plan_id}/{tid} は done ですが、attempt={attempt} の PASS の verdict がありません"
            f"（{why}）。計画票の {tid} の status を review に戻し、verifier を実行してください。"
        )

    finish()


if __name__ == "__main__":
    main()
