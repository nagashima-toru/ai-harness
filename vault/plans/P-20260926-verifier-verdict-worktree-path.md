---
id: P-20260926-verifier-verdict-worktree-path
status: approved
---
# ゴール

verifier が `EnterWorktree` で対象 worktree に入った状態のまま `vault/verdicts/<計画ID>/<id>.json` を相対パスで書くと、working directory が worktree のままなのでメインリポジトリ側ではなく worktree 側に書き込まれてしまう（issue #61）。run スキルの手順6はメインリポジトリ側にファイルが存在する前提で読むため、気づかなければ verdict が「無い」ものとして扱われ続け、Stop フックにブロックされたり verifier の再実行を無駄に繰り返したりする。

`.claude/agents/verifier.md`・`vault/rules/verifier/verifier.md` に「worktree に入っていても書き込み先は必ずメインリポジトリ側のパスにする（`ExitWorktree` してから書く、または絶対パスで書く）」ことを明記し（予防）、`.claude/skills/run/SKILL.md` の verdict 読み取り手順に worktree 側へのフォールバック確認と復旧手順を追記する（検知・復旧）。

## 分割方針

該当箇所は独立した3ファイルで、それぞれ書き込み制限が異なる。
- `.claude/agents/verifier.md` は `vault/rules/` 配下ではないため、通常の成果物として直接編集できる（T-01）
- `vault/rules/verifier/verifier.md` は `vault/rules/` 配下で `agent_write_guard.py` が改ざん防止のため常に書き込みを拒否するため、`docs/vault-spec.md` 12節の提案ファイル方式に従い `vault/tasks/<計画ID>/T-02-proposal.md` への下書きを成果物にする（T-02）。実体への反映は人が行う
- `.claude/skills/run/SKILL.md` も `vault/rules/` 配下ではないため直接編集できる（T-03）。T-01・T-02（書き込み側の予防）とは独立した検知・復旧側の変更であり、ファイルも異なるため `after` 依存は付けない

3タスクとも対象ファイルが異なり、互いの内容を前提にしないため並行実行できる。`agent_write_guard.py` 自体（worktree 内外を区別する判定の追加）は今回のスコープに含めない。予防（T-01・T-02）と検知・復旧（T-03）の2段構えで対応する方が、フックのパス判定ロジックを変更するより副作用が少ないと判断した（フック変更は今回見送るだけで、再発した場合の次フェーズ候補として残す）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | verifier エージェント定義に worktree からメインリポジトリへの書き込み先明記を追加する | |
| T-02 | done | 1 | - | verifier ルール文書への同趣旨の追記を提案ファイルとして下書きする | |
| T-03 | review | 1 | - | run スキルの verdict 読み取り手順に worktree 側フォールバックを追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補（票は起こさない）
- `.claude/hooks/agent_write_guard.py` の `resolve_root()` が Write/Edit の相対パスを実際の書き込み先ではなく `CLAUDE_PROJECT_DIR`（環境変数）基準で解決している疑いがあり、worktree 内から相対パスで書く挙動そのものを恒久的に防げていない可能性がある。T-01〜T-03（instructions 側の対策）で issue #61 の再発が防げない場合、フック側でも worktree 内かどうかを検知して警告・拒否する仕組みを追加検討する

## 人への質問
（なし）
