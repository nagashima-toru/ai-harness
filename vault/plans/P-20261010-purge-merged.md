---
id: P-20261010-purge-merged
status: approved
---
# ゴール
D-016 フェーズ2（`vault/designs/D-016.md` の「フェーズ2」の受け入れ基準の候補・決定済みを前提にする。フェーズ1（#146）はマージ済み）：`scripts/purge_plan.sh` に、`main` にマージ済みの計画一式と `vault/archive/` をまとめて削除する `--merged` モード（`--list`・`--report`・`--apply`）を足し、`scripts/archive_plans.sh` を廃止する。`--report` は削除の前に人が Issue 化すべき情報（`→blocked` の遷移があったタスクとその補足、verdict の `reasons`）を一覧で出す。`docs/runbook.md` 5節を「一括削除の手順」に書き換え、`docs/vault-spec.md`・`scripts/install.sh`・`scripts/uninstall.sh`・smoke（と、同じ記述を持つ `README.md`・`docs/install.md`）から archive の記述を除く。実際の削除はこの計画のマージ後に人が runbook の手順で行う（この計画では既存の計画一式や `vault/archive/` を実際に消さない）。

## 分割方針
- スクリプト側は `scripts/smoke.sh` を触るタスクを T-01 → T-02 → T-03 の直列にする（smoke の同時編集の衝突を避ける）。T-01 で `--merged` を足し、T-02 で `archive_plans.sh` と smoke の archive_plans 節を消し、T-03 で install.sh・uninstall.sh から archive を除く
- 文書側は、`--merged` の挙動が決まった T-01 の後に runbook（T-04）と vault-spec（T-05）を並行で直す。smoke は触らない
- 最後の T-06 で README・docs/install.md・docs/decisions.md を直し、ゴールの範囲（docs・.claude・scripts・README.md）に archive_plans や archive の古い記述が残っていないことをまとめて確かめる
- D-016 の候補「最後の遷移が `→blocked` のタスク」は、対象（全行 done の計画）では最後の遷移が必ず `→done` になり一致しないため、「log に `→blocked` の遷移行があったタスクとその補足（質問）」と読み替えた（T-01 の決定済み）
- 計画 ID の形式に合わない旧形式の計画（`vault/plans/P-019.md`〜`P-021.md`、`vault/tasks/T-00xx.md`）は、D-016 の条件1により `--merged` の対象外のまま残る。この計画では扱わず、runbook に「対象外で、必要なら人が `git rm` する」とだけ書く（T-04）
- T-07 は人の指示で後から足した。T-04 が runbook 5節に存在しないパスをバッククォートで書き、smoke の (ref-1) が落ちて T-02 が blocked になったため。T-02 の after に T-07 を足した

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | purge_plan.sh に --merged（--list・--report・--apply）を足し smoke で確かめる | |
| T-02 | done | 1 | T-01,T-07 | archive_plans.sh と smoke の archive_plans 節を消す | |
| T-03 | done | 1 | T-02 | install.sh・uninstall.sh から vault/archive を除く | |
| T-04 | done | 1 | T-01 | runbook 5節を一括削除の手順に書き換える | |
| T-05 | done | 1 | T-01 | vault-spec から archive の記述を除き --merged を書く | |
| T-06 | review | 1 | T-02,T-03,T-04,T-05 | README・install.md・decisions.md を直し archive の残りを確かめる | |
| T-07 | done | 1 | - | runbook 5節の存在しないパスの参照を直す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- D-016 フェーズ3（設計文書の ID 形式の変更と、既存の設計文書の削除）。この計画のマージ後、人が runbook 5節の一括削除を行ってから `/plan` に渡す
- 旧形式の計画（`vault/plans/P-019.md`〜`P-021.md`、`vault/tasks/T-0036.md`〜`T-0051.md` など、計画 ID の形式に合わないもの）の扱い。`--merged` の対象外なので、消すなら人が手で `git rm` するか、別のゴールとして扱う
