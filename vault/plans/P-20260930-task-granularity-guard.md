---
id: P-20260930-task-granularity-guard
status: approved
---
# ゴール
`.claude/hooks/plan_guard.py` に粒度の検査を追加する。Write/Edit の対象が `vault/tasks/<計画ID>/T-xx.md` で、対応する計画票の frontmatter の status が `draft` の時は、「## 受け入れ基準」節の箇条書きが3〜7行でなければブロックする。対象が `vault/plans/<計画ID>.md` で、status が `draft` の時は、タスク表のデータ行が7行を超えればブロックする。`docs/vault-spec.md` の8節と10節に、機械で検査される旨を追記する。`scripts/smoke.sh` にテストを足す（issue #77、`vault/designs/D-010.md` フェーズ3）。

PR 本文では `Closes #77` を使う（D-010 決定事項：1 issue = 1 フェーズ。設計文書自体の PR だけが `Relates to #N`）。

## 分割方針
- T-01：`plan_guard.py` に「Write/Edit の `file_path` から対象を特定し draft 計画だけ検査する」枠組みと、タスク票の受け入れ基準3〜7行の検査を入れる。既存の approved 計画の検査は「approved が0件なら即終了」で始まるため、粒度検査はその前に置く必要があり、この枠組みを先に作る。実装とその回帰テスト（`smoke.sh`）は関連する2ファイルの1PR分として1タスクにまとめる（`P-20260927-done-write-guard`/T-01 と同じ扱い）
- T-02：同じ枠組みに、draft 計画票のタスク表7行以下の検査を足す。T-01 と同じファイルを編集するので `after` で T-01 に依存させる
- T-03：`docs/vault-spec.md` 8節・10節への追記。T-01・T-02 の挙動を正確に書く必要があるため両方に依存させる
- 3タスクとも成果物が特定でき、1計画7タスク以内に収まる。次フェーズの候補は無い

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | plan_guard.py に draft 計画のタスク票の受け入れ基準3〜7行の検査を追加し smoke.sh にテストを足す | |
| T-02 | review | 1 | T-01 | plan_guard.py に draft 計画票のタスク表7行以下の検査を追加し smoke.sh にテストを足す | |
| T-03 | todo | 0 | T-01,T-02 | vault-spec.md の8節・10節に粒度が機械で検査される旨を追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
