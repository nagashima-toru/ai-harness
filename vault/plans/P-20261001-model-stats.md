---
id: P-20261001-model-stats
status: approved
---
# ゴール

D-010 フェーズ8：`.claude/skills/run/SKILL.md` を改訂し、オーケストレーターが log の遷移行に使ったモデルを記録するようにする。`doing→review`・`doing→blocked` の行の補足には `creator=<モデル>`、`review→done`・`review→doing`・`review→blocked` の行の補足には `verifier=<モデル>` を付ける。モデルの値は `.claude/agents/<name>.md` の frontmatter の `model` とする。`scripts/model_stats.py` を新規作成し、引数に渡した log ファイル群（既定は `vault/log/*.md`）から、creator のモデル別に、対象タスク数・1回目 PASS 率・平均 attempt・blocked 率を表形式で標準出力に出す。`docs/vault-spec.md` 7節に補足の書式を追記し、`scripts/smoke.sh` にテストを足す。

PR 本文用：`Closes #74`

## 分割方針
- 書式の正本（`docs/vault-spec.md` 7節）を T-01 で先に確定し、`.claude/skills/run/SKILL.md`（T-03）と `scripts/model_stats.py`（T-02）がそれを参照する。T-02 と T-03 は触るファイルが別なので互いに依存させない
- `scripts/smoke.sh` に触るのは T-04 だけ。T-02・T-03 の後に直列で行い、model_stats.py のフィクスチャ検査、SKILL.md の記述検査、log を読むフック（stop_gate.py・agent_write_guard.py・plan_guard.py）が新しい補足で壊れないことの検査（smoke 全体の `fail=0`）をまとめる
- 実際の log 行の補足は `creator=<モデル>` / `verifier=<モデル>`。verdict.json の形式と stop_gate.py は変えない

### 決定済み（設計文書から引き継ぎ。各タスク票にも写す）
- 記録先は log（verdict ではない）
- 集計の定義：対象タスクは `計画ID/id`（計画 ID は log のファイル名から取る）の最後の遷移行が `→done` または `→blocked` のもの。集計キーは最後の `doing→review` 行の `creator=`（無ければ `unknown`）。1回目 PASS 率は `review→done attempt=1` で終わった件数 ÷ 対象タスク数。平均 attempt は最後の遷移行の `attempt=` の平均。blocked 率は `→blocked` で終わった件数 ÷ 対象タスク数
- 遷移行（`<状態>→<状態>` を含む行）以外は無視する（`worktree path=...` やハングの補足行を含む）
- 出力はタブ区切り、1行目は見出し `model	tasks	first_pass_rate	avg_attempt	blocked_rate`、率は小数2桁
- `vault/archive/` 配下の log は引数で明示すれば集計できるが、既定の対象には含めない
- verifier のモデル別の集計は出さない（記録だけする）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | vault-spec 7節に creator=/verifier= の補足の書式を追記する | |
| T-02 | todo | 0 | T-01 | scripts/model_stats.py を新規作成する | |
| T-03 | todo | 0 | T-01 | run SKILL.md の手順4・6に creator=/verifier= の記録を足す | |
| T-04 | todo | 0 | T-02,T-03 | smoke.sh に model_stats と補足付き log のテストを足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
