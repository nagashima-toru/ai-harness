---
id: P-20261021-planner-forbidden-words
status: done
---
# ゴール
GitHub Issue #224 に対応し、`.claude/agents/planner.md` に「禁止操作が含まれないことを調べる基準では、禁止操作の語（`git push`・`gh pr merge` など）を確認コマンドの文字列に直接書かない。語を分けて連結するか、検査する語をリポジトリ内のファイルから読む形にする」という指針を足す。「## やらないこと」に1項目、「## 書き終えた後の確認」に同じ指針を確かめる1項目を足す。

## 分割方針
- 成果物は `.claude/agents/planner.md` の1ファイルで、1コンテキストで終わるため1タスクにする。
- `docs/decisions.md` には足さない。同種の既存の指針（Issue #187 の `python3 -c` 内の subprocess、Issue #211 の grep パターンの `#`）が `docs/decisions.md` に書かれていないことを確かめたため（`grep -n '187' docs/decisions.md`・`grep -n '211' docs/decisions.md` がどちらも0件）。
- 経緯集 `vault/rules/planner/ai-harness-lessons.md` への追記は依頼の範囲（planner.md が中心、decisions.md は条件付き）に無いため、このタスクでは行わない。
- 状態遷移・フック・`.claude/settings.json`・スクリプトは変えない。
- 計画単位のレビュータスクは足さない。T-01 の成果物は `.claude/agents/planner.md`（拡張子 `.md`）だけで、コードを変更するタスクが0件のため。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | planner.md に確認コマンドの文字列へ禁止操作の語を直接書かない指針を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
