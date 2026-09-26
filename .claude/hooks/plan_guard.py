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

加えて、1ブランチ1計画の不変条件を検査する：
  (f) approved な計画票が2件以上ある

approved な計画票が0件、および表にデータ行が無い場合は何もせず許可する。
出力：壊れていれば {"decision": "block", "reason": "..."}、正常なら何も出さず exit 0。

worktree 委譲：payload["cwd"] が自リポジトリと異なる git worktree を指す場合、そのルート配下の
同名スクリプト（.claude/hooks/plan_guard.py）へ判定を委譲する（issue #56 / D-008 フェーズ2）。
実装は agent_write_guard.py の delegate_to_worktree と同じパターンをそのまま複製したもの
（git_toplevel・existing_ancestor も同様にコピー。他ファイルへの import はしない）。
"""
import json
import os
import re
import subprocess
import sys

STATUSES = ("todo", "doing", "review", "blocked", "done")
COLUMNS = ("id", "status", "attempt", "after", "title", "question")


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
    `.claude/hooks/plan_guard.py` へ判定を委譲する（issue #56 / D-008 フェーズ2）。

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

    delegate_script = os.path.join(worktree_root, ".claude", "hooks", "plan_guard.py")
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

    delegated_stdout = delegate_to_worktree(payload)
    if delegated_stdout is not None:
        sys.stdout.write(delegated_stdout)
        sys.exit(0)

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

    sys.exit(0)


if __name__ == "__main__":
    main()
