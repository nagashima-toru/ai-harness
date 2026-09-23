#!/usr/bin/env python3
"""PreToolUse フック：サブエージェントごとに書き込み先を制限する。

- verifier : vault/verdicts/ 配下のみ
- planner  : vault/plans/ と vault/tasks/ 配下のみ
対象ツール : Write / Edit / MultiEdit / NotebookEdit（パス判定）、Bash（リダイレクトや破壊的コマンドの簡易判定）
メインエージェントや他のサブエージェントには何もしない。

改ざん防止：上記とは別に、agent_type を問わず（メインエージェント含む）vault/rules/ 配下への
書き込みを常に拒否する。タスクの状態（todo/doing/review）や承認済み計画の有無は問わない。
作成エージェントがタスク中にルールを書き換え、verifier の判定基準を自分で緩めるのを防ぐ。
ルール変更を成果物とするタスクは、実パスではなく vault/tasks/<計画ID>/<id>-proposal.md に
下書きし、verifier はそこを検証する。実体（vault/rules/ 配下）への反映は人が手作業で行う
（docs/vault-spec.md 第12節）。
"""
import json
import os
import re
import subprocess
import sys

GIT_COMMIT_PATTERN = r"\bgit\s+commit\b"

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
    return branch or None


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

    # main 直接コミット拒否：agent_type を問わず、現在のブランチが main の時は git commit を拒否する。
    # 非 git リポジトリ・ブランチ取得不能（detached HEAD 等）は fail-open（この判定は素通り）。
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if re.search(GIT_COMMIT_PATTERN, cmd) and current_branch(root) == "main":
            deny(
                f"[agent_write_guard] main への直接コミットはできません。"
                f"ブランチを切ってください（work/<計画IDの英小文字>）: {cmd[:120]}"
            )

    # 改ざん防止：agent_type を問わず、vault/rules/ への書き込みは常に拒否する
    # （タスクの状態や承認済み計画の有無を問わない。解除口は無い）
    if targets_vault_rules(tool, tool_input, root):
        deny(
            "[agent_write_guard] vault/rules/ へは書き込めません。"
            "ルール変更が成果物のタスクは vault/tasks/<計画ID>/<id>-proposal.md に下書きし、"
            "実体への反映は人が手作業で行います。"
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
