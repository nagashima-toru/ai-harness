#!/usr/bin/env python3
"""PreToolUse フック：サブエージェントごとに書き込み先を制限する。

- verifier : vault/verdicts/ 配下のみ
- planner  : vault/plans/ と vault/tasks/ 配下のみ
対象ツール : Write / Edit / MultiEdit / NotebookEdit（パス判定）、Bash（リダイレクトや破壊的コマンドの簡易判定）
メインエージェントや他のサブエージェントには何もしない。

改ざん防止：上記とは別に、vault/todo.md に doing/review 中のタスクが1件でもあれば、
agent_type を問わず（メインエージェント含む）vault/rules/ 配下への書き込みを拒否する。
作成エージェントがタスク中にルールを書き換え、verifier の判定基準を自分で緩めるのを防ぐ。
解除は環境変数 HARNESS_ALLOW_RULES_WRITE=<doing/review のタスク ID> を人が起動時に
与えた時だけ効く。フックは Claude Code プロセスの環境を継承するため、作成エージェントが
Bash 内で export しても届かない（実質的に人しか解除できない）。
"""
import json
import os
import re
import sys

ALLOWED = {
    "verifier": ["vault/verdicts/"],
    "planner": ["vault/plans/", "vault/tasks/"],
}
BASH_WRITE_PATTERNS = [
    r"(^|[^<>])>{1,2}\s*\S",          # リダイレクト（<> や >& を含む単純な誤検知は許容）
    r"\btee\b",
    r"\b(rm|mv|cp|touch|mkdir|chmod|chown)\b",
    r"\bgit\s+(add|commit|push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)\b",
    r"\bsed\s+-i\b",
]


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
    rel = os.path.relpath(ap, root)
    return rel.replace(os.sep, "/")


def active_doing_review_task_ids(root):
    """vault/todo.md の「## タスク」表から status が doing/review の id を返す（無ければ空リスト）。
    .claude/hooks/todo_guard.py の raw_rows と同じ規則の簡易版をこのファイル内に持つ（import はしない）。"""
    todo_path = os.path.join(root, "vault", "todo.md")
    if not os.path.isfile(todo_path):
        return []
    try:
        with open(todo_path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return []
    ids = []
    in_tasks = False
    for line in text.splitlines():
        if line.startswith("## "):
            in_tasks = line.strip() == "## タスク"
            continue
        stripped = line.strip()
        if not in_tasks or not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or cells[0] == "id" or re.fullmatch(r"-*", cells[0]):
            continue
        if len(cells) >= 2 and cells[1] in ("doing", "review"):
            ids.append(cells[0])
    return ids


def rules_write_allowed(active_ids):
    """環境変数 HARNESS_ALLOW_RULES_WRITE による明示解除の判定。

    値は解除を許すタスク ID の列（カンマまたは空白区切り）。doing/review の ID が
    すべて含まれる時だけ True。未設定・空・不一致、および `1` / `true` のような
    ID でない値では解除しない（必ず ID を書かせる）。
    フックは Claude Code プロセスの環境を継承するため、作成エージェントが Bash 内で
    export しても届かない。実質的に人だけが起動時に解除できる。
    """
    raw = os.environ.get("HARNESS_ALLOW_RULES_WRITE", "")
    allowed = {v for v in re.split(r"[,\s]+", raw) if v}
    if not allowed:
        return False
    return all(tid in allowed for tid in active_ids)


def targets_vault_rules(tool, tool_input, root):
    """この呼び出しが vault/rules/ 配下への書き込みを試みているか判定する。"""
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        return normalize(path, root).startswith("vault/rules/")
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if not any(re.search(p, cmd) for p in BASH_WRITE_PATTERNS):
            return False
        redirect_targets = re.findall(r">{1,2}\s*([^\s;&|]+)", cmd)
        path_like = re.findall(r"[^\s'\"]*vault/rules/[^\s'\"]*", cmd)
        candidates = redirect_targets + path_like
        return any(normalize(t, root).startswith("vault/rules/") for t in candidates)
    return False


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}

    # 改ざん防止：agent_type を問わず、doing/review 中は vault/rules/ への書き込みを拒否する
    # （HARNESS_ALLOW_RULES_WRITE に doing/review の ID が指定されている時だけ解除する）
    active_ids = active_doing_review_task_ids(root)
    if active_ids and targets_vault_rules(tool, tool_input, root) and not rules_write_allowed(active_ids):
        deny(
            f"[agent_write_guard] doing/review 中は vault/rules/ を編集できません（対象タスク: {', '.join(active_ids)}）。"
            f"ルール自体を変更するタスクなら、人が HARNESS_ALLOW_RULES_WRITE={','.join(active_ids)} を付けて起動すること。"
        )

    agent = payload.get("agent_type") or ""
    if agent not in ALLOWED:
        sys.exit(0)

    allowed = ALLOWED[agent]
    allowed_text = " / ".join(allowed)

    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        rel = normalize(path, root)
        if not any(rel.startswith(a) for a in allowed):
            deny(f"[agent_write_guard] {agent} は {allowed_text} 以外に書き込めません: {path}")
        sys.exit(0)

    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if any(re.search(p, cmd) for p in BASH_WRITE_PATTERNS):
            # 許可ディレクトリだけを対象にしたリダイレクトは通す
            targets = re.findall(r">{1,2}\s*([^\s;&|]+)", cmd)
            if targets and all(normalize(t, root).startswith(tuple(allowed)) for t in targets) \
                    and not re.search(r"\b(rm|mv|cp|git\s+(add|commit|push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)|sed\s+-i|tee)\b", cmd):
                sys.exit(0)
            deny(f"[agent_write_guard] {agent} の Bash では書き込み・破壊的操作を行えません（{allowed_text} へのリダイレクトのみ可）: {cmd[:120]}")
    sys.exit(0)


if __name__ == "__main__":
    main()
