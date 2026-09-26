#!/usr/bin/env python3
"""Stop フック：verdict を見て作業終了の可否を判定する。状態は書き換えない。

自分のブランチの計画票（vault/plans/*.md のうち status: approved の1件）のタスク表と
vault/verdicts/<計画ID>/<タスクID>.json を読んで判定する。

入力  : stdin に Claude Code の Stop フック JSON
出力  : ブロック時は stdout に {"decision": "block", "reason": "..."}、許可時は何も出さず exit 0
環境  : HARNESS_MAX_ATTEMPTS（既定 3）、HARNESS_STRICT_STOP=1 で stop_hook_active を無視

worktree 委譲：payload["cwd"] が自リポジトリと異なる git worktree を指す場合、そのルート配下の
同名スクリプト（.claude/hooks/stop_gate.py）へ判定を委譲する（issue #56 / D-008 フェーズ2）。
実装は agent_write_guard.py の delegate_to_worktree と同じパターンをそのまま複製したもの
（git_toplevel・existing_ancestor も同様にコピー。他ファイルへの import はしない）。
"""
import json
import os
import re
import subprocess
import sys

MAX_ATTEMPTS = int(os.environ.get("HARNESS_MAX_ATTEMPTS", "3"))
STRICT = os.environ.get("HARNESS_STRICT_STOP", "0") == "1"


def existing_ancestor(dir_path):
    """dir_path 自身、または存在する祖先ディレクトリまで `os.path.dirname()` で遡って返す。

    worktree 内でまだ作成されていないネストしたディレクトリ配下に書き込もうとした場合、
    `git -C <存在しないpath> rev-parse --show-toplevel` は exit 128 で失敗する（issue #24）。
    worktree のルート自体は常に存在するため、存在するディレクトリまで遡ってから
    `git -C` に渡せば正しく worktree のルートを解決できる。
    """
    if not dir_path:
        return None
    probe = dir_path
    while probe and not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            # ルートまで遡っても見つからない（ほぼ起こらない）場合は諦める
            return None
        probe = parent
    return probe or None


def git_toplevel(dir_path):
    """dir_path から `git rev-parse --show-toplevel` を試みる。

    worktree 内から呼ばれた場合はその worktree のルートを返す。非 git・取得失敗時は None
    （呼び出し側で既存のフォールバック順に進む＝fail-open）。
    """
    if not dir_path:
        return None
    dir_path = existing_ancestor(dir_path)
    if not dir_path:
        return None
    try:
        out = subprocess.run(
            ["git", "-C", dir_path, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    top = out.stdout.strip()
    return top or None


def delegate_to_worktree(payload):
    """payload["cwd"] が自リポジトリと異なる git worktree を指す場合、そのルート配下の
    `.claude/hooks/stop_gate.py` へ判定を委譲する（issue #56 / D-008 フェーズ2）。

    委譲に成功した場合は委譲先の stdout をそのまま文字列で返す（呼び出し側はそれをそのまま
    自分の stdout として出し exit 0 する）。委譲しない・できない場合は None を返し、
    呼び出し側は通常どおりメインリポジトリ側のローカル判定に進む（fail-open）。

    二重委譲防止：委譲先プロセスの環境変数に `_HOOK_DELEGATED=1` をセットして呼び出す。
    自分自身の環境で既に `_HOOK_DELEGATED` が設定されている場合は委譲せず、必ず
    ローカル判定にフォールバックする（委譲は1段まで）。
    """
    if os.environ.get("_HOOK_DELEGATED"):
        return None

    cwd = payload.get("cwd") or ""
    if not cwd:
        return None
    worktree_root = git_toplevel(cwd)
    if not worktree_root:
        return None

    self_root = os.environ.get("CLAUDE_PROJECT_DIR") or git_toplevel(os.path.dirname(os.path.abspath(__file__)))
    if not self_root:
        return None
    if os.path.abspath(worktree_root) == os.path.abspath(self_root):
        return None

    delegate_script = os.path.join(worktree_root, ".claude", "hooks", "stop_gate.py")
    if not os.path.isfile(delegate_script):
        return None

    env = os.environ.copy()
    env["_HOOK_DELEGATED"] = "1"
    try:
        result = subprocess.run(
            ["python3", delegate_script],
            input=json.dumps(payload),
            capture_output=True, text=True, timeout=20, env=env,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout


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


def has_uncommitted_changes(root):
    """作業ツリーに未コミットの変更があるか。非 git リポジトリ・取得不能なら False（fail-open）。"""
    if not os.path.isdir(os.path.join(root, ".git")):
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

    delegated_stdout = delegate_to_worktree(payload)
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
