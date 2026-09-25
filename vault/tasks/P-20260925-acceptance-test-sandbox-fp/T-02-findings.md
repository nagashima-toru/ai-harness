# T-02 findings: grep 誤検知（issue #42 時の事象）の原因切り分け

## 受け入れ基準1の実行結果

実行したコマンド（タスク票の受け入れ基準1と同一）：

```
echo '{"tool_name":"Bash","tool_input":{"command":"grep -c \"git diff main\" /tmp/dummy.md"},"agent_type":"creator","cwd":"'$(pwd)'"}' | python3 .claude/hooks/agent_write_guard.py
```

このコマンド自体は、後述のとおり worktree 隔離のためのサンドボックス（コマンド安全性チェック）に
一度拒否されたため、まず JSON ペイロードをファイル（`/tmp/t02-payload.json`）に書き出し、
`python3 .claude/hooks/agent_write_guard.py < /tmp/t02-payload.json` の形で `agent_write_guard.py`
単体を実行した。

- 出力：空
- 終了コード：`0`

→ `agent_write_guard.py` は `grep -c "git diff main" ...` というコマンド文字列を deny しない（planner
  の事前確認と一致）。

## 実際に creator の Bash ツールで再現を試みた結果

1回目：受け入れ基準1のコマンドをそのまま（`echo '...' | python3 .claude/hooks/agent_write_guard.py`
の1行、`$(pwd)` コマンド置換込み）Bash ツールで実行 → **拒否された**。ただし出力は
`agent_write_guard.py` が返す deny の JSON ではなく、次のテキストだった（Bash ツール自体からのエラー）。

```
This agent is isolated in the worktree /Users/nagashimat/IdeaProjects/ai-harness/.claude/worktrees/agent-a53adb0b6f03c5f30,
but this command names git in a form too complex to verify that it stays inside the worktree.
Refusing to run it — a worktree-isolated agent's git operations must target its own worktree.
Split it into plain, separate commands and run them from
/Users/nagashimat/IdeaProjects/ai-harness/.claude/worktrees/agent-a53adb0b6f03c5f30.
```

2回目：`$(pwd)` コマンド置換を外し、cwd を直接リテラル文字列で埋め込んだ同種の1行（`echo '...(JSON,
"git diff main" という文字列を含む)...' | python3 .claude/hooks/agent_write_guard.py`）を実行 →
再び**拒否された**。文言はわずかに異なるが同じ趣旨。

```
This agent is isolated in the worktree /Users/nagashimat/IdeaProjects/ai-harness/.claude/worktrees/agent-a53adb0b6f03c5f30,
but this command feeds python text naming git in a plain command, which cannot be shown to stay
inside the worktree. Refusing to run it — a worktree-isolated agent's git operations must target
its own worktree. Run the plain command from
/Users/nagashimat/IdeaProjects/ai-harness/.claude/worktrees/agent-a53adb0b6f03c5f30.
```

3回目：`grep -c "git diff main" <一時ファイル>` を単独の素朴な1コマンドとして実行
（`echo "sample text" > /tmp/t02-dummy.md && grep -c "git diff main" /tmp/t02-dummy.md`、および
`grep -c "git diff main" vault/tasks/P-20260925-acceptance-test-sandbox-fp/T-02.md`）→ **拒否されず**、
通常どおり実行できた（出力 `0` および `4`、grep の終了コードもそれぞれ正常）。

## 結論

原因は `agent_write_guard.py`（PreToolUse フック）**ではない（no）**。

根拠：
- `agent_write_guard.py` を単体で模擬実行すると、当該コマンド文字列を deny しない（受け入れ基準1の
  実行結果、出力空・終了コード0）。`BASH_WRITE_PATTERNS` にも `targets_vault_rules` /
  `targets_creator_denied_paths` にも `grep` を書き込み系コマンドとして扱う判定は無く、コードを読んでも
  マッチしない。
- 一方で、`echo '<git という語を含むJSON文字列>' | python3 ...` のように、"git" という語を含むテキストを
  別プロセスへパイプする1行コマンドを Bash ツールで実行すると、`agent_write_guard.py` の deny JSON とは
  文面も構造も異なる別のメッセージ（"isolated in the worktree" / "git operations must target its own
  worktree"）で拒否された。この文言は本リポジトリの `.claude/hooks/` 配下のどのフックにも見当たらず、
  Claude Code のツール実行時のサンドボックス（worktree 隔離のための git コマンド安全性チェック）が
  発しているものと判断する。
- 実際に `grep -c "git diff main" <ファイル>` を単独の素朴な1コマンドとして実行した場合は拒否されなかった
  （3回目）。つまり今回の環境では、grep コマンド単体・素朴な形では再現しなかった。拒否が起きたのは、
  "git" という語を含む文字列を `echo | python3` のようにパイプ／複数コマンドに組み合わせた、より複雑な
  1行コマンドを実行しようとした場合だった。

以上より、issue #42 で観測された誤検知は `agent_write_guard.py` の判定ロジックの問題ではなく、
Claude Code 側のツール実行時サンドボックス（worktree 隔離のための git 関連コマンド検出）が、
コマンド文字列中に "git" という語（grep のパターン文字列の中身であっても）が含まれ、かつコマンドの
構造が複雑（パイプ・コマンド置換等）な場合に誤って git 操作とみなして拒否する、プラットフォーム側の
経路に起因する可能性が高い。`.claude/` 側のフックやルールで直接修正できる箇所ではない。

## 次の一手（未決定）

以下は対応候補の列挙であり、優先順位は付けていない。このタスクでは決定・実装を行わない。

- 人に今回の再現条件（"git" を含む文字列を `echo | python3` 等でパイプする複雑な1行コマンド）を伝え、
  Claude Code 側の挙動として意図されたものか、報告すべき不具合かを判断してもらう
- planner 側の指針として、確認コマンドに "git" を含む文字列（grep パターン等）を使う場合は、複雑な
  パイプ／コマンド置換を避け、事前にファイルへ書き出してから素朴な1コマンドで実行する形を推奨する
  （別タスクとして起票する）
- タスク票の受け入れ基準に併記する確認コマンドの作法（複雑な1行にせず、素朴な形に分解する）について、
  `vault/rules/` 側にガイドを追加することを検討する（実施は別タスクで、`vault/rules/` への直接変更は
  このタスクの範囲外）
- 同種の誤検知が他のコマンド（"git" 以外にサンドボックスが特別扱いする語がある場合）でも起きうるか、
  人が Claude Code のドキュメント／サポートに確認する
