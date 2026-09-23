---
id: P-20260924-rules-guard
status: approved
---
# ゴール
`vault/designs/D-002.md` フェーズ1。`.claude/hooks/agent_write_guard.py` から `HARNESS_ALLOW_RULES_WRITE`
による明示解除の仕組み（環境変数の読み取り・`rules_write_allowed`・`doing`/`review` の有無による条件
分岐）を削除し、`vault/rules/` への書き込みをタスクの状態や計画の有無に関わらず常にすべてのエージェ
ント（メインエージェント含む）に対して拒否するように変える。`docs/vault-spec.md` を新しい「提案ファ
イル方式」（ルール変更を成果物とするタスクは `vault/tasks/<計画ID>/<id>-proposal.md` に下書きし、
verifier がそこを検証し、実体への反映は人が手作業で行う）を正本として書き直す。`vault/rules/creator/`
と `vault/rules/planner/` に、ルール変更が成果物のタスクをこの方式で扱う旨の指示を追記する（この計画
自体が提案ファイル方式の最初の適用例になるため、追記そのものも直接編集ではなく提案ファイルとして下
書きする）。

## 分割方針
- T-01（フック本体）：`.claude/hooks/agent_write_guard.py` は `vault/rules/` 配下ではないため直接編
  集できる。常時拒否ロジックへの書き換えと、対応する `scripts/smoke.sh` のケース更新は密結合（ケー
  スを直さないとフックの正しさを検証できない）なので1タスクにまとめる（`vault/tasks/T-0048.md` の前
  例に倣う）。
- T-02（仕様書）：`docs/vault-spec.md` も `vault/rules/` の外なので直接編集できる。第11節の要約文と
  第12節の全面書き直しは同じファイル・同じ話題のため1タスクにまとめる。
- T-03・T-04（ルール指示の追記）：追記先の `vault/rules/creator/creator.md` と
  `vault/rules/planner/planner.md` はどちらも `vault/rules/` 配下。T-01 の完了前後を問わず、この計画
  のタスクが `doing`/`review` になれば（旧ロジックでも新ロジックでも）フックが書き込みを拒否するた
  め、直接編集はできない。この計画自体がゴールとする「提案ファイル方式」を先取りして適用し、成果物
  を実体パスではなく `vault/tasks/P-20260924-rules-guard/T-03-proposal.md` /
  `T-04-proposal.md` にする。実体への反映は人が手作業で行う（`vault/designs/D-002.md` の決定事項ど
  おり、反映の自動化はスコープ外）。
- 追記先ファイルが `creator/` と `planner/` で分かれるため、成果物を1つに保つ原則（`vault/templates/
  task.md`）に従い T-03・T-04 は別タスクにする。
- 4タスクとも成果物ファイルが独立しており、依存に循環はない。順序を強制する技術的な理由が無いため
  `after` はすべて `-` にした（人が並行させたい場合はそのまま進められる）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | agent_write_guard.py の常時拒否化と smoke.sh 更新 | |
| T-02 | todo | 0 | - | vault-spec.md を提案ファイル方式に書き直す | |
| T-03 | todo | 0 | - | creator ルールへの提案ファイル方式の指示を提案ファイルとして用意する | |
| T-04 | todo | 0 | - | planner ルールへの提案ファイル方式の指示を提案ファイルとして用意する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
なし（`vault/designs/D-002.md` の決定事項でこの計画に必要な判断は出尽くしている）
