#!/usr/bin/env python3
"""PreToolUse フック：書き込みの3つの判定と、worktree への委譲（D-015 フェーズ3）。

判定は次の3つだけ。どれにも当たらなければ何も出力せず終了コード0で終わる。
- (b) main 上の git commit の拒否：Bash のコマンドを &&・||・;・|・改行（引用符の外）で区切った各部分の
  先頭が git commit（git のオプションを挟む形も）で、現在のブランチが main の時。引用符の中は見ない。
  agent_type は問わない。ブランチが取れない時（非 git・detached HEAD）は素通り。
- (a) done のタスク票・verdict への書き込みの拒否：Write / Edit / MultiEdit / NotebookEdit の対象が
  vault/tasks/<計画ID>/<id>.md または vault/verdicts/<計画ID>/<id>.json で、計画票（vault/plans/<計画ID>.md）の
  タスク表でその id の status が done の時。agent_type は問わない。計画票・行が無い時は許可（fail-open）。
  タスク表の解析は _hooklib.py の parse_tasks を使う。Bash による書き換えは見ない。
- (c) verifier の書き込み先を vault/verdicts/ に限る：agent_type が verifier の Write 系ツールだけを見る。
  verifier の Bash と、planner・creator の書き込み先は制限しない。

worktree への委譲：payload の cwd が別の git worktree を指す時は、その worktree の同じフックに判定を任せる。
Write 系は対象パスが worktree の中の時だけ、Bash とそれ以外のツールは常に委譲する。
共通関数は .claude/hooks/_hooklib.py にあり、読み込めない時は終了コード2で終わる（D-011）。
"""
import json
import os
import re
import shlex
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import _hooklib as H
except Exception as e:  # SyntaxError なども含めて捕まえる
    sys.stderr.write(f"[agent_write_guard] _hooklib の読み込みに失敗しました: {e}\n")
    sys.exit(2)

WRITE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")
TASK_FILE_RE = re.compile(r"^vault/tasks/([^/]+)/([^/]+)\.md$")
VERDICT_FILE_RE = re.compile(r"^vault/verdicts/([^/]+)/([^/]+)\.json$")


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))
    sys.exit(0)


def normalize(path, root):
    if not path:
        return ""
    ap = os.path.abspath(os.path.join(root, path)) if not os.path.isabs(path) else os.path.abspath(path)
    ap = os.path.realpath(ap)
    root = os.path.realpath(root)
    rel = os.path.relpath(ap, root)
    return rel.replace(os.sep, "/")


def tool_path(tool_input):
    return tool_input.get("file_path") or tool_input.get("notebook_path") or ""


def resolve_root(tool, tool_input, payload):
    """書き込み先パスの正規化に使う root を求める。

    Write 系では対象パスの親ディレクトリを起点に、Bash では payload.cwd を起点に、
    それぞれ `git rev-parse --show-toplevel` で worktree のルートを優先的に求める。
    取得できない場合のみ CLAUDE_PROJECT_DIR → payload.cwd → os.getcwd() の優先順にフォールバックする。
    """
    fallback = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    probe_dir = None
    if tool in WRITE_TOOLS:
        path = tool_path(tool_input)
        if path:
            abs_path = path if os.path.isabs(path) else os.path.abspath(os.path.join(fallback, path))
            probe_dir = os.path.dirname(abs_path)
    elif tool == "Bash":
        cwd = payload.get("cwd") or ""
        if cwd:
            probe_dir = cwd
    if probe_dir:
        top = H.git_toplevel(probe_dir)
        if top:
            return top
    return fallback


def current_branch(root):
    """現在のブランチ名を返す。非 git リポジトリ・エラー・detached HEAD 等は None（fail-open）。"""
    try:
        out = subprocess.run(
            ["git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    branch = out.stdout.strip()
    if branch == "HEAD":
        return None
    return branch or None


def writes_inside_worktree(tool, tool_input, payload):
    """worktree への委譲の可否。Write 系は対象パスが worktree のルートの中の時だけ True、
    Bash とそれ以外のツールは常に True。worktree のルートが求まらない時は True（委譲側が None を返す）。
    """
    if tool not in WRITE_TOOLS:
        return True
    cwd = payload.get("cwd") or ""
    wt_root = H.git_toplevel(cwd) if cwd else None
    if not wt_root:
        return True
    p = os.path.expanduser(tool_path(tool_input))
    if not p:
        return False
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    real_root = os.path.realpath(wt_root)
    rp = os.path.realpath(p)
    return rp == real_root or rp.startswith(real_root + "/")


def _split_command(cmd):
    """引用符の外にある &&・||・;・|・改行でコマンドを部分に分ける（引用符の中は区切らない）。"""
    parts = []
    buf = []
    quote = None
    i = 0
    n = len(cmd)
    while i < n:
        c = cmd[i]
        if quote:
            buf.append(c)
            if quote == '"' and c == "\\" and i + 1 < n:
                buf.append(cmd[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in ("'", '"'):
            quote = c
            buf.append(c)
        elif c in (";", "\n", "|", "&"):
            if c in ("|", "&") and i + 1 < n and cmd[i + 1] == c:
                i += 1  # && と ||
            elif c == "&":
                buf.append(c)  # 単独の & は区切らない
                i += 1
                continue
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(c)
        i += 1
    parts.append("".join(buf))
    return parts


def is_git_commit_command(cmd):
    """区切った各部分の先頭が git commit（git -C . commit のようなオプション付きも）か。
    引用符の中の文字列は見ない。env・VAR=値の前置き、bash -c の中、サブシェルは見ない。
    """
    for part in _split_command(cmd):
        try:
            words = shlex.split(part)
        except ValueError:
            words = part.split()
        if not words or os.path.basename(words[0]) != "git":
            continue
        i = 1
        while i < len(words) and words[i].startswith("-"):
            if words[i] in ("-C", "-c", "--git-dir", "--work-tree", "--namespace"):
                i += 1
            i += 1
        if i < len(words) and words[i] == "commit":
            return True
    return False


def plan_task_status(root, plan_id, task_id):
    """vault/plans/<plan_id>.md のタスク表から task_id の status を返す。

    計画票が無い・読めない・該当行が無い場合は None（fail-open。呼び出し側で許可に倒す）。
    """
    path = os.path.join(root, "vault", "plans", f"{plan_id}.md")
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None
    for t in H.parse_tasks(text):
        if t["id"] == task_id:
            return t["status"]
    return None


def match_task_or_verdict_path(rel):
    """rel（normalize() 済みのパス）が vault/tasks/<計画ID>/<id>.md または
    vault/verdicts/<計画ID>/<id>.json にマッチしたら (plan_id, id) を返す。マッチしなければ None。
    """
    m = TASK_FILE_RE.match(rel)
    if m:
        return m.group(1), m.group(2)
    m = VERDICT_FILE_RE.match(rel)
    if m:
        return m.group(1), m.group(2)
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if not isinstance(payload, dict):
        sys.exit(0)

    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}

    if writes_inside_worktree(tool, tool_input, payload):
        delegated_stdout = H.delegate_to_worktree(payload, "agent_write_guard.py")
        if delegated_stdout is not None:
            sys.stdout.write(delegated_stdout)
            sys.exit(0)

    root = resolve_root(tool, tool_input, payload)

    # (b) main 直接コミットの拒否
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if is_git_commit_command(cmd) and current_branch(root) == "main":
            deny(
                f"[agent_write_guard] main への直接コミットはできません。"
                f"ブランチを切ってください（work/<計画IDの英小文字>）: {cmd[:120]}"
            )

    if tool in WRITE_TOOLS:
        path = tool_path(tool_input)
        rel = normalize(path, root)

        # (a) done のタスク票・verdict への書き込みの拒否
        matched = match_task_or_verdict_path(rel)
        if matched and plan_task_status(root, matched[0], matched[1]) == "done":
            deny(
                f"[agent_write_guard] {matched[0]}/{matched[1]} は status が done のため、"
                f"{rel} へは書き込めません。"
            )

        # (c) verifier の書き込み先を vault/verdicts/ に限る
        if payload.get("agent_type") == "verifier" and not rel.startswith("vault/verdicts/"):
            deny(f"[agent_write_guard] verifier は vault/verdicts/ 以外に書き込めません: {path}")

    sys.exit(0)


if __name__ == "__main__":
    main()
