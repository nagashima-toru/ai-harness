---
id: P-20261001-planner-opus
status: approved
---
# ゴール

D-010 フェーズ9：`.claude/agents/planner.md` の frontmatter の `model` を `opus` にする。`creator.md`・`verifier.md` は `sonnet` のまま据え置く。`.claude/skills/design/SKILL.md` と `.claude/skills/plan/SKILL.md` の本文、および `docs/runbook.md` に、`/design`・`/plan` は強いモデル（opus）のセッションで実行する旨を書く。`docs/decisions.md` に、2026-09-17 の「verifier / planner の model は sonnet」を今回の割当（planner=opus、verifier=sonnet、creator=sonnet 据え置き。creator は `scripts/model_stats.py` の結果を見て見直す）で置き換える旨の新しい行を追加する。

PR 本文用：`Closes #73`

## 分割方針
- 書き換えるファイルがすべて別なので、decisions.md（T-01）・design SKILL.md（T-02）・plan SKILL.md（T-03）・runbook.md（T-04）は互いに依存させず並行可能にする
- `agents/planner.md` の model 変更と `bash scripts/smoke.sh` の `fail=0` の確認は T-05 に切り出し、T-01〜T-04 の後に単独で動かす（smoke.sh が /tmp の固定パスを使うため、並行実行で偽の fail が出るのを避ける）。T-01〜T-04 の受け入れ基準に smoke は含めない

### 決定済み（設計文書 D-010 から引き継ぎ。各タスク票にも写す）
- モデル名は alias（`opus`・`sonnet`）で書く。バージョン付きの ID は書かない
- `docs/decisions.md` の 2026-09-17 の行は書き換えない（判断の記録として残す）。新しい日付の行を追加し、置き換える旨を書く
- スキルの frontmatter でのモデル指定はしない。本文の注意書きと runbook での運用とする
- creator のモデルは変えない。haiku 等への切り替えは、`model_stats.py` で十分な件数が集まってから、別の計画で行う
- verifier は「実行側」として扱う（人の回答）。`sonnet` のまま

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | decisions.md に planner=opus への置き換え行を追加する | |
| T-02 | done | 1 | - | design SKILL.md に opus セッションで実行する旨を書く | |
| T-03 | review | 1 | - | plan SKILL.md に opus セッションで実行する旨を書く | |
| T-04 | todo | 0 | - | runbook.md に /design・/plan を opus で実行する旨を書く | |
| T-05 | todo | 0 | T-01,T-02,T-03,T-04 | planner.md の model を opus にし smoke を通す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
