---
id: P-20260926-hook-worktree-delegate-phase2
status: draft
---
# ゴール

フェーズ1で `.claude/hooks/agent_write_guard.py` に実装した worktree 委譲ロジック（`payload["cwd"]` の git toplevel が自リポジトリと異なれば、そのルート配下の同名スクリプトへ委譲し、失敗時はフェイルオープンでフォールバックする）と同じパターンを `.claude/hooks/plan_guard.py`・`.claude/hooks/stop_gate.py` それぞれに複製して実装する。既存の判定ロジック（タスク表整合性チェック・verdict 検証等）は変更しない。

背景：issue #56（`EnterWorktree` で分離実行された verifier/creator が `.claude/hooks/` 配下のスクリプト自体を成果物として検証する時、`PreToolUse`/`PostToolUse`/`Stop` の3フックが `${CLAUDE_PROJECT_DIR}` 固定パスでメインリポジトリ側の未修正コードを実行してしまう）への対応。設計文書 `vault/designs/D-008.md` のフェーズ2（フェーズ1は `P-20260926-write-guard-worktree-delegate` で実装済み・マージ済み）がこのゴールの元。

## 分割方針

対象は `plan_guard.py`（PostToolUse）・`stop_gate.py`（Stop）の2ファイルで、それぞれ独立した既存ロジック（タスク表整合性チェック／verdict 判定）を持つ別々のスクリプトのため、フェーズ1の1タスク（`agent_write_guard.py` 1本＋`scripts/smoke.sh`）と同等の規模の作業がファイル単位で2回分発生する。1タスクにまとめると受け入れ基準が7行を超えるため、ファイルごとに T-01（`plan_guard.py`）・T-02（`stop_gate.py`）へ分割する。

両タスクとも `scripts/smoke.sh` に新規テストケースを追記するが、挿入箇所は既存の `== stop_gate.py ==`（69〜124行目、ファイル先頭側）と `== plan_guard.py ==`（283行目以降）で離れており、論理的な依存関係は無い。ただし同一ファイルへの追記が2タスクで並行 doing になった場合の worktree 間マージ衝突リスクを避けるため、T-02 は T-01 に `after` で依存させ、逐次実行にする（`vault/rules/common/git.md` の「コンフリクトは自己判断で解決せず blocked にする」運用を踏まえた予防的な順序付け）。

新規テストケースのラベルは、フェーズ1で既に `scripts/smoke.sh` に存在する `(delegate)`（`agent_write_guard.py` 向け）と衝突しないよう、`(delegate plan_guard)`・`(delegate stop_gate)` という一意な文字列にする（`grep -c` によるケース数確認が、他ファイル向けラベルを誤って数えないようにするため）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | plan_guard.py に worktree 委譲ロジックを追加する | |
| T-02 | todo | 0 | T-01 | stop_gate.py に worktree 委譲ロジックを追加する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
（なし。`vault/designs/D-008.md` フェーズ2で決定済みの内容、および `P-20260926-write-guard-worktree-delegate`（フェーズ1）で人が既に判断した内容のみを対象にしている）
