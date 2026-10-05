"""P-20261005-bash-write-unify の確認用フィクスチャ（planner が作成。編集しない）。

agent_write_guard.py を import し、analyze_bash_writes を呼び出し回数を数える関数で包んでから、
Bash の payload を1件ずつ main() に渡す。各ケースについて
`<label> <allow|deny> calls=<analyze_bash_writes の呼び出し回数>` を1行ずつ出し、最後に
`mismatch=<一本化後の期待と判定が違ったラベルのカンマ区切り。無ければ none>` と
`max_calls=<呼び出し回数の最大値>` を出す。

使い方（リポジトリのルートで）：python3 -B vault/tasks/P-20261005-bash-write-unify/fixtures/bash_writes_check.py
CLAUDE_PROJECT_DIR はこのファイルのあるディレクトリ（fixtures/）に向ける。fixtures/vault/plans/P-FX.md の
T-01 が done、T-02 が doing。コマンドは実行しない（文字列として判定に渡すだけ）。
"""
import contextlib
import io
import json
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, ".claude", "hooks"))
os.environ["CLAUDE_PROJECT_DIR"] = HERE
os.environ["_HOOK_DELEGATED"] = "1"  # worktree への委譲をさせない

import agent_write_guard as G  # noqa: E402

PY = "python3 -c 'print(1)'"
R = chr(62)  # リダイレクト記号
# (label, agent_type, command, 一本化後に期待する判定)
CASES = [
    ("rules-parsed", "", "echo x " + R + " vault/rules/a.md", "deny"),
    ("rules-legacy", "", PY + " " + R + " vault/rules/a.md", "deny"),
    ("transcript-legacy", "", PY + " " + R + " ~/.claude/projects/x.jsonl", "deny"),
    ("creator-parsed", "creator", "echo x " + R + R + " vault/plans/P-FX.md", "deny"),
    ("creator-legacy", "creator", PY + " " + R + " vault/log/P-FX.md", "deny"),
    ("done-legacy", "", PY + " " + R + " vault/tasks/P-FX/T-01.md", "deny"),
    ("done-gitadd", "", "git add vault/tasks/P-FX/T-01.md", "allow"),
    ("verifier-readonly", "verifier", "grep -c x README.md", "allow"),
    ("verifier-parsed-allowed", "verifier", "echo x " + R + " vault/verdicts/P-FX/T-02.json", "allow"),
    ("verifier-legacy-outside", "verifier", PY + " " + R + " /tmp/x.txt", "allow"),
    ("verifier-legacy-inside", "verifier", PY + " " + R + " README.md", "deny"),
    ("planner-legacy-allowed", "planner", PY + " " + R + " vault/tasks/P-FX/T-02.md", "allow"),
    # 一本化で変わる例：従来は許可（extract_bash_write_targets の対象が /tmp だけ）。
    # 一本化後は保護対象パスを含む path-like トークン（vault/tasks/P-FX/T-02.md）も候補に入り、
    # 「全候補が root の外」を満たさないので拒否になる
    ("change-example", "verifier",
     "python3 -c \"open('vault/tasks/P-FX/T-02.md')\" " + R + " /tmp/x.txt", "deny"),
]

calls = [0]
_orig = G.analyze_bash_writes


def counting(*args, **kwargs):
    calls[0] += 1
    return _orig(*args, **kwargs)


G.analyze_bash_writes = counting

mismatch = []
max_calls = 0
for label, agent, cmd, expected in CASES:
    payload = {"tool_name": "Bash", "tool_input": {"command": cmd}}
    if agent:
        payload["agent_type"] = agent
    calls[0] = 0
    out = io.StringIO()
    sys.stdin = io.StringIO(json.dumps(payload))
    with contextlib.redirect_stdout(out):
        try:
            G.main()
        except SystemExit:
            pass
    decision = "deny" if '"deny"' in out.getvalue() else "allow"
    print(f"{label} {decision} calls={calls[0]}")
    max_calls = max(max_calls, calls[0])
    if decision != expected:
        mismatch.append(label)
print("mismatch=" + (",".join(mismatch) if mismatch else "none"))
print(f"max_calls={max_calls}")
