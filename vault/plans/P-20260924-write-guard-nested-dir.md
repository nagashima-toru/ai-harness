---
id: P-20260924-write-guard-nested-dir
status: approved
---
# ゴール

`.claude/hooks/agent_write_guard.py` の `resolve_root()` は、worktree 内で書き込み先の親ディレクトリ（`probe_dir`）がまだファイルシステム上に存在しない場合、`git -C <存在しないパス> rev-parse --show-toplevel` が exit code 128 で失敗し `git_toplevel()` が `None` を返すため、`CLAUDE_PROJECT_DIR`（メインチェックアウト）に誤ってフォールバックする。この結果、worktree 側の絶対パスをメインチェックアウトからの相対パスに変換しようとして `../../` を含む無関係な相対パスになり、`vault/verdicts/` 等への正当な書き込みが誤って拒否される（GitHub Issue #24）。

`git_toplevel()` の探索対象を、`probe_dir` の直近の**存在する祖先ディレクトリ**まで遡ってから実行するように修正し、この誤検知を無くす。

## 分割方針
バグ修正1本（`.claude/hooks/agent_write_guard.py` の関数修正 + 回帰確認の smoke ケース追加）で完結するスコープであり、成果物も同一ファイル1つに閉じるため、契約タスクと実装タスクに分ける必要が無い。1タスク（T-01）のみで構成する。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | agent_write_guard: 未作成の祖先ディレクトリでも worktree root を解決する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
（なし）
