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


TASK_PATH_RE = re.compile(r"^vault/tasks/([^/]+)/(T-\d{2})\.md$")
CRITERIA_MIN, CRITERIA_MAX = 3, 7


def count_criteria(text):
    """「## 受け入れ基準」の次の行から次の `## ` 見出し（または EOF）までの、行頭が `- ` か `数字. ` の行数。"""
    count = 0
    in_section = False
    for line in text.splitlines():
        if line.startswith("## "):
            in_section = line.strip() == "## 受け入れ基準"
            continue
        if in_section and re.match(r"^(- |\d+\. )", line):
            count += 1
    return count


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
    _, status = plan_id_and_status(os.path.join(root, "vault", "plans", plan_id + ".md"))
    if status != "draft":
        return None
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None
    n = count_criteria(text)
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
    _, status = plan_id_and_status(path)
    if status != "draft":
        return None
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None
    n = len(raw_rows(text))
    if n <= PLAN_ROWS_MAX:
        return None
    return (
        f"[plan_guard] {m.group(1)} のタスク表が{n}行です。1計画は{PLAN_ROWS_MAX}タスク以下にしてください。"
        f"超える分は次フェーズの候補として計画票の末尾に書くだけにしてください。"
    )


def frontmatter_status(text):
    """先頭の `---` から次の `---` までの frontmatter の `status:` の値を返す。無ければ None。本文は見ない。

    agent_write_guard.py の同名関数のコピー（フック間で import しない方針）。
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r"^status:\s*(\S*)", line)
        if m:
            return m.group(1).strip("\"'")
    return None


def human_messages(transcript_path):
    """会話記録（JSONL）から人の発言（type=user・content が文字列・isMeta が真でない行）を返す。

    読めない（パスが無い・ファイルが無い・どの行も JSON でない）場合も空リストを返す。
    agent_write_guard.py の同名関数のコピー。
    """
    if not transcript_path:
        return []
    try:
        with open(os.path.expanduser(transcript_path), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except Exception:
        return []
    out = []
    for line in lines:
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict) or obj.get("type") != "user" or obj.get("isMeta"):
            continue
        msg = obj.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        if isinstance(content, str):
            out.append(content)
    return out


def is_approve_command(text, plan_id):
    """人の発言が `/plan approve <plan_id>`（スラッシュコマンド形式または文形式）か判定する。"""
    if "<command-name>/plan</command-name>" in text:
        for args in re.findall(r"<command-args>(.*?)</command-args>", text, re.S):
            if args.strip() == f"approve {plan_id}":
                return True
    m = re.match(r"^/plan\s+approve\s+(\S+)", text.lstrip())
    return bool(m) and m.group(1) == plan_id


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
        plan_id, status = plan_id_and_status(os.path.join(plans_dir, name))
        if status != "approved":
            continue
        head_status = None
        try:
            shown = subprocess.run(
                ["git", "show", f"HEAD:./vault/plans/{name}"],
                capture_output=True, text=True, timeout=5, cwd=root,
            )
            if shown.returncode == 0:
                head_status = frontmatter_status(shown.stdout)
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
            humans = human_messages(transcript_path if isinstance(transcript_path, str) else None)
        if not humans:
            warnings.append(
                f"[plan_guard] {plan_id} が draft から approved に書き換えられていますが、"
                f"会話記録が読めないため承認の裏付けを検査できませんでした。"
                f"人が /plan approve {plan_id} で指示した時だけ承認できます。"
            )
            continue
        if not any(is_approve_command(t, plan_id) for t in humans):
            return (
                f"[plan_guard] {plan_id} が draft から approved に書き換えられていますが、"
                f"人の /plan approve {plan_id} の指示が会話記録にありません。"
                f"git restore vault/plans/{plan_id}.md で元に戻してください"
                f"（承認は人が /plan approve {plan_id} で指示した時だけ行えます）。"
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

    delegated_stdout = delegate_to_worktree(payload)
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

    def finish():
        """終了経路。既存の検査がブロックしなかった時だけ、承認の裏付け警告を1回出して終わる。"""
        if warning:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PostToolUse", "additionalContext": warning}}, ensure_ascii=False))
        sys.exit(0)

    plans = approved_plans(root)

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

    rows = raw_rows(text)
    if not rows:
        finish()

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

    finish()


if __name__ == "__main__":
    main()
