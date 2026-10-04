"""P-20261005-bash-write-unify の確認用フィクスチャ（planner が作成。編集しない）。

agent_write_guard.py の `bash_write_targets(cmd, root)` の戻り値 `(parsed, writes)` を、下の CASES と比べる。
各ケースについて `<label> parsed=<bool> type=<writes の型名> kinds=<verb の集合> targets=<target の集合>` を出し、
期待と違えば行末に ` NG` を付ける。最後に `targets_mismatch=<違ったラベルのカンマ区切り。無ければ none>` を出す。
kinds・targets は集合（重複と順序は問わない）で比べる。

使い方（リポジトリのルートで）：python3 -B vault/tasks/P-20261005-bash-write-unify/fixtures/targets_check.py
"""
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, ".claude", "hooks"))
os.environ["_HOOK_DELEGATED"] = "1"

import agent_write_guard as G  # noqa: E402

R = chr(62)
P = "legacy-path"
RD = "legacy-redirect"
W = "legacy-write"
U = "legacy-unknown"
# (label, command, parsed, kinds, targets)
CASES = [
    ("parsed-redirect", "echo x " + R + " vault/rules/a.md", True, {"redirect"}, {"vault/rules/a.md"}),
    ("parsed-readonly", "ls -la", True, set(), set()),
    ("legacy-no-write", "python3 -c 'print(1)'", False, set(), set()),
    ("legacy-no-write-with-path", "bash -c 'cat x' ~/.claude/projects/y", False, set(), set()),
    ("legacy-redirect", "python3 -c 'print(1)' " + R + " vault/log/a.md", False, {P, RD, W}, {"vault/log/a.md"}),
    ("legacy-path-and-outside", "python3 -c \"open('vault/tasks/P/T-02.md')\" " + R + " /tmp/x.txt", False,
     {P, RD, W}, {"/tmp/x.txt", "vault/tasks/P/T-02.md"}),
    ("legacy-strip", "bash -c \"rm vault/plans/a.md)\"", False, {P, W}, {"vault/plans/a.md"}),
    ("legacy-transcript", "bash -c \"cp a ~/.claude/projects/x/s.jsonl\"", False, {P, W},
     {"~/.claude/projects/x/s.jsonl"}),
    ("legacy-verdict-paren", "bash -c \"tee vault/verdicts/P/T-01.json)x\"", False, {P},
     {"vault/verdicts/P/T-01.json)x", "vault/verdicts/P/T-01.json"}),
    ("legacy-no-candidate", "bash -c \"git push\"", False, {U}, {""}),
]

if not hasattr(G, "bash_write_targets"):
    print("bash_write_targets がありません")
    print("targets_mismatch=all")
    sys.exit(0)

mismatch = []
for label, cmd, e_parsed, e_kinds, e_targets in CASES:
    parsed, writes = G.bash_write_targets(cmd, HERE)
    kinds = {v for v, _ in writes}
    targets = {t for _, t in writes}
    ok = (parsed is e_parsed and type(writes) is tuple and kinds == e_kinds and targets == e_targets)
    print(f"{label} parsed={parsed} type={type(writes).__name__} kinds={sorted(kinds)} targets={sorted(targets)}"
          + ("" if ok else " NG"))
    if not ok:
        mismatch.append(label)
print("targets_mismatch=" + (",".join(mismatch) if mismatch else "none"))
