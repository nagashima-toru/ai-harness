---
id: P-20261012-planner-lessons-subprocess
status: done
---
# ゴール
GitHub Issue #195 を解決する。経緯集 `vault/rules/planner/ai-harness-lessons.md` の「## ルール」節に、`.claude/agents/planner.md` の「## やらないこと」に #196 で追加済みの「確認コマンドを、`python3 -c` の中から subprocess で git などの外部コマンドを呼ぶ形にしない」教訓に対応する項目（太字の教訓の一言＋「- 経緯：」行）を1つ足す。

対象外：`.claude/agents/planner.md` 自体（教訓は追加済み）、経緯集の「## 目的」「## 確認方法」。

## 分割方針
成果物は経緯集1ファイルへの1項目の追記だけなので、1タスクにする。経緯集は `vault/rules/` 配下で smoke の `(ref-1)` の対象外（`(ref-3)` で除外を確かめている）のため、`(ref-1)` の基準は置かない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | 経緯集に python3 -c 内の subprocess の教訓と経緯を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
