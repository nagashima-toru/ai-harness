---
id: P-20261011-smoke-worktree-remove-quiet
status: done
---
# ゴール
GitHub Issue #181（smoke.sh の `git worktree remove -q` が古い git（2.43）で失敗し、エラーが出力に混ざる）に対応する。`scripts/smoke.sh` の `git worktree remove` から `-q` をすべて外し、リダイレクトが無い `(stop_gate worktree)` 後の1箇所に `>/dev/null 2>&1` を足して他と揃える。

## 分割方針
- 変えるファイルは `scripts/smoke.sh` の1つだけで、変更は機械的な置換（`-q` 削除10箇所とリダイレクト追加1箇所）なので1タスクにする。
- `scripts/` と `.claude/` のほかの場所に `git worktree remove -q` は無い（計画時に `grep -rn 'worktree remove' scripts .claude` で確認済み。`scripts/discard_worktree.sh` と smoke.sh の911・928行目は既に `-q` 無し）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | smoke.sh の git worktree remove から -q を外しリダイレクトを揃える | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
