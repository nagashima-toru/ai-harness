---
id: P-20260925-run-commit-before-worktree
status: approved
---
# ゴール

`.claude/skills/run/SKILL.md` に、計画票（`vault/plans/<計画ID>.md`）・ログ（`vault/log/<計画ID>.md`）を Edit/Bash で更新した後、次に creator/verifier のサブエージェントを呼ぶ（特に `isolation: "worktree"` で新しい worktree を作る、または既存 worktree に `EnterWorktree` で入る）前に、その更新を必ずコミットする旨を明記する（GitHub Issue #50）。

`isolation: "worktree"` を使う Agent 呼び出しは、その時点の計画ブランチの**コミット済み** HEAD から分岐する。オーケストレーターの working directory 上の未コミット変更は新しい worktree に反映されない。実際に `P-20260925-sandbox-hang-timeout` の T-01 attempt=2→3 遷移で、計画票・ログを更新したがコミットせずに `discard_worktree.sh` で worktree を作り直し creator を再呼び出しした結果、新しい worktree が古い（attempt=2 の）計画票内容から分岐し、verifier がその古い attempt 値を verdict に書いて `docs/vault-spec.md` の「attempt が計画票のタスク表の値と一致しない verdict は無いものとして扱う」チェックに引っかかる事故が起きた。

対応方針：`.claude/skills/run/SKILL.md` 内の以下3箇所に、直前の一括反映（計画票・ログの書き込み）をコミットしてから次の呼び出しに進む旨を追記する。既存の「一括反映する」という指示の直後に一連の流れとして書き足す形にし、新しい手順番号は切らない。
1. 手順2「取り出す」の末尾（doing への一括反映・ログ追記の直後、手順3で creator の worktree を作る前）
2. 手順4「review にする」の末尾（review への一括反映・ログ追記の直後、手順5で verifier を呼ぶ前。verifier は既存 worktree に `EnterWorktree` で入るため同様の問題が起きる）
3. 手順6.3.2（FAIL 再試行時、`discard_worktree.sh` で worktree を破棄して手順3から creator を呼び直すパターン）の該当箇所（直前の状態変更＝doing・attempt+1・ログ追記がコミット済みであることを確認してから worktree を作り直す、という順序を明示する）

対象外（このタスクではやらない）：
- `discard_worktree.sh` 等スクリプトの実装変更
- creator・verifier 側のルール（`vault/rules/creator/`・`vault/rules/verifier/`）の変更
- `docs/vault-spec.md` の変更
- 手順6.2（PASS 時の worktree 側の未コミット差分回収）の変更（`P-20260925-run-merge-uncommitted`、issue #32 で既に対応済みの別範囲）

## 分割方針
`.claude/skills/run/SKILL.md` 1ファイルの3箇所への指針追記という一体の修正であり、`P-20260925-run-merge-uncommitted`（同一ファイル・同種の運用バグ修正を1タスクで完結させた前例）に倣い、1タスク（T-01）のみで構成する。受け入れ基準は5行に収まる見込みのため分割の必要は無い。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | runスキル: worktree生成前に計画票・ログのコミットを明記 | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
</content>
