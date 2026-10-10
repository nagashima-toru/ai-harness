---
id: P-20261010-async-agent-wait
status: approved
---
# ゴール
D-20261010-async-agent-wait フェーズ1（最終フェーズ）：run・plan の Agent 呼び出し（creator・planner・verifier）が `run_in_background: false` を指定してもバックグラウンドで起動して即座に戻る場合の扱いを決める。`.claude/skills/run/SKILL.md` の手順3・手順5・「ハング時の復旧」と `.claude/skills/plan/SKILL.md` の手順4に、起動通知が返った時はターンを終えて完了通知を待ち、通知が来るまで後続の手順に進まないことと、出力ファイル（transcript）の最終更新から10分進まなければハングとみなして既存の復旧手順で扱うことを書く。`.claude/hooks/stop_gate.py` は判定を変えず、記録行の無い doing でブロックする時のメッセージを「creator の完了通知を待っているなら、そのままターンを終えて待つ」旨に変え、`docs/vault-spec.md` 9節の表と `scripts/smoke.sh` をそれに合わせる。最後に、決定事項のうち docs に無いものを `docs/decisions.md` に追記し、設計文書 `vault/designs/D-20261010-async-agent-wait.md` を削除する。

## 分割方針
- 成果物のファイルごとに分ける。T-01（stop_gate.py と、その動作を確かめる smoke.sh のケース）を先に置き、9節の表（T-02）は T-01 が決めた実際の文面に合わせるため T-01 の後にする
- T-03（run の SKILL.md）・T-04（plan の SKILL.md）は文書だけで互いに独立なので、T-01 と並行に着手できる
- T-05（docs/decisions.md への追記と設計文書の削除）は、設計文書を読む T-01〜T-04 すべての後に置く（設計文書の決定済みどおり、削除は creator の成果物として行う）
- 7節（log の書式）は変えない。バックグラウンドの呼び出しのハングも既存の `--note`（`creator呼び出しハングにより再試行`・`creator呼び出しハング`・`verifier呼び出しハング`）で記録するため（T-03 の決定済み）
- PR 本文で Issue に触れる時は `Closes`・`Fixes` を使わず、`Relates to #147`・`Relates to #157` の非クローズキーワードにする（run の手順7で PR を作るオーケストレーター向けの注意。#157 は後半が別の計画に残るため）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | stop_gate.py の記録行の無い doing のブロック理由に完了通知待ちの案内を足し smoke で確かめる | |
| T-02 | review | 1 | T-01 | vault-spec.md 9節の表に記録行の無い doing の時のメッセージの違いを書く | |
| T-03 | done | 1 | - | run の SKILL.md に起動通知が返った時の待ち方と10分のハング基準を書く | |
| T-04 | done | 1 | - | plan の SKILL.md の手順4に planner の起動通知が返った時の待ち方を書く | |
| T-05 | todo | 0 | T-01,T-02,T-03,T-04 | 決定事項を docs/decisions.md に追記し設計文書を削除する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
