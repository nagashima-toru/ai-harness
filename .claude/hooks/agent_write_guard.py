#!/usr/bin/env python3
"""PreToolUse フック：サブエージェントごとに書き込み先を制限する。

- verifier : vault/verdicts/ 配下のみ
- planner  : vault/plans/ と vault/tasks/ 配下のみ
対象ツール : Write / Edit / MultiEdit / NotebookEdit（パス判定）、Bash（リダイレクトや破壊的コマンドの簡易判定）
メインエージェントや他のサブエージェントには何もしない。
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


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    agent = payload.get("agent_type") or ""
    if agent not in ALLOWED:
        sys.exit(0)

    root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
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
