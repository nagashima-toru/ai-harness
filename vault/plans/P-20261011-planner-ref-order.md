---
id: P-20261011-planner-ref-order
status: approved
---
# ゴール
planner が、後続タスクで作るファイルのパスを先行タスクの成果物（smoke の `(ref-1)` が検査する文書）に書かせる計画を作らないようにする（GitHub Issue #172）。

背景：P-20261011-user-guide-entry の T-01 で `.claude/agents/planner.md` に、まだ存在しない `docs/guide.md`（後続の T-02 で作るファイル）をバッククォートで書かせたため、smoke の `(ref-1)` が NG になり、`fail=0` の基準と同時に満たせなかった（受け入れ基準どうしの矛盾）。

## 分割方針
- 変える文書が2つ（planner の定義と `/plan` スキル）なので、文書ごとに1タスクにする。不必要に細かく割らない
- T-01：`.claude/agents/planner.md` の「やらないこと」節に規則を、「書き終えた後の確認」節に確認項目を足す。付随して、このリポジトリの planner 経緯集 `vault/rules/planner/ai-harness-lessons.md` に経緯を1項目足す（経緯集は「やらないこと」の各項目の経緯を並べる決まりのため）
- T-02：`.claude/skills/plan/SKILL.md` の手順A-5（粒度の確認）に、この点の確認を足す
- 2タスクは別ファイルを変え、どちらも新しいファイルを作らないので依存は無い（`after` は `-`）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | planner.md に新規ファイルへの参照順の規則と確認項目を足す | |
| T-02 | done | 1 | - | /plan の粒度の確認に新規ファイルへの参照順の確認を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 2タスクの完了後、`bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わる
