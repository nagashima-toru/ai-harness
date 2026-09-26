---
id: P-20260926-write-guard-worktree-delegate
status: done
---
# ゴール

`.claude/hooks/agent_write_guard.py` に、PreToolUse 呼び出しの `payload["cwd"]` が git worktree を指している場合はそのルート配下の `.claude/hooks/agent_write_guard.py` へ委譲する（委譲先の stdout をそのまま自分の stdout として出し `exit 0` する）ロジックを追加する。委譲先が存在しない・委譲の実行自体が失敗/タイムアウトした場合は、フェイルオープンで既存のローカル判定（メインリポジトリ側のコード）にフォールバックする。委譲は1段までとし、二重委譲を環境変数で防止する。既存の判定ロジック（`vault/rules/` 改ざん防止・`main` 直接コミット拒否・verifier/planner/creator の書き込み先制限等）は変更しない。

背景：issue #56（`EnterWorktree` で分離実行された verifier が `.claude/hooks/agent_write_guard.py` のバグ修正を検証しようとしても、PreToolUse フックは `${CLAUDE_PROJECT_DIR}` 固定パスでメインリポジトリ側の未修正コードを実行してしまうため、worktree内の修正が反映されない）への対応。`vault/designs/D-008.md` のフェーズ1（既に `main` にマージ済み）がこのゴールの元。

## 分割方針

`vault/designs/D-008.md` フェーズ1の受け入れ基準の候補（5行）がそのまま3〜7行の粒度基準に収まり、変更対象ファイルも `.claude/hooks/agent_write_guard.py`（実装本体）＋回帰・新規テストケースの追加先 `scripts/smoke.sh` の2ファイルに閉じる、既存タスク `P-20260924-worktree-isolation-guard/T-01`（同じ2ファイルを1タスクで実装＋テスト追加した先例）と同等の規模のため、分割せず単一タスク T-01 とする。

D-008 のフェーズ2（`plan_guard.py`・`stop_gate.py` への同パターン展開）は、このフェーズ1がマージされてから、その時点の実装パターンを見て別計画として起票する（次フェーズ候補、票は起こさない）。

## タスク表（状態の正本）

| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | agent_write_guard.py に worktree 委譲ロジックを追加する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補（票は起こさない）
- D-008 フェーズ2：`plan_guard.py`・`stop_gate.py` に同じ委譲パターンを複製する（T-01 のマージ後に着手）

## 人への質問
（なし。`vault/designs/D-008.md` フェーズ1で決定済みの内容のみを対象にしている）
