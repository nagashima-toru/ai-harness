---
id: P-20261010-plan-purge-on-finish
status: done
---
# ゴール
D-016 フェーズ1（`vault/designs/D-016.md` の「フェーズ1」の受け入れ基準の候補・決定済みを前提にする）：run の完了手順（`.claude/skills/run/SKILL.md` の手順7）で、PR を作る直前に、計画の記録を PR 本文に写し、残すべき情報を docs への追記か Issue 化で取り出し、`scripts/purge_plan.sh` で計画一式4種（`vault/plans/<計画ID>.md`・`vault/tasks/<計画ID>/`・`vault/verdicts/<計画ID>/`・`vault/log/<計画ID>.md`）を `git rm` してコミットするようにする。計画の記録は新しいスクリプト `scripts/plan_record.py` が出す。仕様（`docs/vault-spec.md`）・`docs/runbook.md`・`.claude/ai-harness.md`・smoke を合わせて直す。

## 分割方針
- 成果物ごとに1タスク。スクリプトはスクリプト本体と smoke のケースを同じタスクに入れる
  - T-01：`scripts/purge_plan.sh`（除去のスクリプト）と smoke のケース `(pp-1)`〜`(pp-8)`
  - T-02：`scripts/plan_record.py`（計画の記録の出力）と smoke のケース `(prec-1)`〜`(prec-6)`
  - T-03：`.claude/skills/run/SKILL.md` の手順7（と「注意」の例外の記述）と、手順7の順序を確かめる smoke のケース `(run-skill-4)`・`(run-skill-5)`
  - T-04：`docs/vault-spec.md`（1節・2節・4節・7節）・`docs/runbook.md`（3節）・`.claude/ai-harness.md`（役割）を T-01〜T-03 の後の実際の状態に揃え、古い記述がリポジトリに残っていないことを確かめる
- T-01〜T-03 はどれも `scripts/smoke.sh` を変えるので、`after` で T-01→T-02→T-03 と直列にする（並べるとマージ時に smoke.sh が衝突しうる）
- T-03・T-04 で文書に `scripts/purge_plan.sh`・`scripts/plan_record.py` を書くと、smoke の `(ref-1)`（主な文書のバッククォート内のパスの存在）と「新規インストール先で参照される scripts がすべて揃っている」が、スクリプトの存在を求める。そのためスクリプトのタスク（T-01・T-02）を先にする。T-04 は手順7の実際の記述を写すので T-03 の後
- `README.md` は範囲から外す（ゴールに挙がっておらず、図と scripts の一覧は要約で、今回の変更と食い違う記述が無い）。`docs/runbook.md` 5節（archive）・`scripts/archive_plans.sh`・`vault/archive/` はフェーズ2で廃止・書き換えるので触らない
- 確認の範囲から外すもの：`docs/decisions.md`（判断の記録で過去の行を書き換えない）、`vault/plans/`・`vault/tasks/`・`vault/log/`・`vault/verdicts/`・`vault/archive/`・`vault/designs/`（履歴と状態）
- この計画自身の一式は、run が T-03 で更新された手順7に従って除去すればよい。残った場合はフェーズ2の一括削除で消える（D-016 の決定済み）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | scripts/purge_plan.sh を作り smoke にケースを足す | |
| T-02 | done | 1 | T-01 | scripts/plan_record.py を作り smoke にケースを足す | |
| T-03 | done | 1 | T-02 | run スキル手順7に計画の記録・取り出し・計画一式の除去を入れ smoke にケースを足す | |
| T-04 | done | 1 | T-03 | vault-spec・runbook・ai-harness.md を計画一式の除去に揃え、古い記述が残っていないことを確かめる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補（票は起こさない）
- D-016 フェーズ2：`scripts/purge_plan.sh` に `--merged`（`--list`・`--report`・`--apply`）を足し、`scripts/archive_plans.sh` を廃止する。`docs/runbook.md` 5節を一括削除の手順に書き換える
- D-016 フェーズ3：設計文書の ID を `D-<YYYYMMDD>-<スラッグ>` にし、既存の設計文書を削除する
