---
id: P-20261011-base-branch-env
status: approved
---
# ゴール
ハーネスが `main` を直書きしている箇所を、環境変数 `HARNESS_BASE_BRANCH`（前後の空白を除いて空なら `main`）の値に置き換える。対象は `scripts/vcs_finish.sh`（GitHub REST の `base`・ホスティング無しのマージ案内）、`.claude/skills/plan/SKILL.md` 手順A-2 と `.claude/skills/design/SKILL.md` 手順1 の開始条件、`.claude/hooks/agent_write_guard.py` (b) の直接コミット拒否（ベースブランチと `main` の両方を拒否）、`scripts/purge_plan.sh --merged` のマージ済み判定（`<ベース>:vault/plans/…`）、`.claude/skills/run/SKILL.md` 手順7 の MCP 代替時の base と、`docs/vault-spec.md`・`docs/runbook.md`・`docs/install.md` の説明。既定値のままなら今の動作を変えない。`scripts/smoke.sh` に既定（main）と別名ベース（develop）の両方のケースを足す。

（設計文書 `vault/designs/D-20261010-base-branch-config.md` のフェーズ1。設計文書の削除と `docs/decisions.md` への追記はフェーズ2で行うので、この計画には含めない）

## 分割方針
- 実装は変更するファイルごとに分ける：T-01 `scripts/vcs_finish.sh`、T-02 `.claude/hooks/agent_write_guard.py`、T-03 `scripts/purge_plan.sh`。互いに依存しないので並列に走れる
- 文言の変更は2つに分ける：T-04 スキル3本と `.claude/agents/creator.md`、T-05 docs 3本。どちらも決定済みの仕様を書くだけで実装に依存しないので、T-01〜T-03 と並列に走れる
- `scripts/smoke.sh` は T-06 だけが触る。別名ベース（develop）のケースは T-01〜T-03 の実装に依存し、ゴール全体で古い記述が残っていないことの確認は T-04・T-05 の結果も見るので、T-06 は全タスクの後に置く
- T-01〜T-03 の時点では、既定（main）で既存の smoke が通ること（今の動作を変えない）と、リポジトリ内で読み取りだけで確かめられる動作（none の案内・フックの関数・メインチェックアウトのブランチでの拒否）を基準にする。develop のケースの機能確認は T-06 の smoke で行う
- 並列に走るタスク同士で同じファイルを成果物にしない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | vcs_finish.sh の base とマージ案内を HARNESS_BASE_BRANCH にする | |
| T-02 | doing | 2 | - | agent_write_guard.py (b) でベースブランチと main の直接コミットを拒否する | |
| T-03 | doing | 1 | - | purge_plan.sh --merged のマージ済み判定をベースブランチの版で行う | |
| T-04 | todo | 0 | - | plan・design・run のスキルと creator.md の main をベースブランチにする | |
| T-05 | todo | 0 | - | vault-spec・runbook・install に HARNESS_BASE_BRANCH を書く | |
| T-06 | todo | 0 | T-01,T-02,T-03,T-04,T-05 | smoke.sh に既定 main と develop のケースを足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- 設計文書のフェーズ2（`HARNESS_PUSH_BRANCH` で push 先と PR/MR の head を上書きする。決定事項の `docs/decisions.md` への取り出しと設計文書の削除を含む）。この計画の完了後に、フェーズ2のゴール文を `/plan` に渡す
