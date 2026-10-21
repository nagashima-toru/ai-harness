---
id: P-20261021-parallel-done-recheck
status: approved
---
# ゴール
GitHub Issue #212「通常の並行実行で、先に done になった同じ組の他タスクの変更を含まない状態で、リポジトリ全体を見る基準を判定する」を解決する。同じ PLAN_HEAD から分岐して並行に作ったタスクのうち、先に別のタスクが done になって計画ブランチにマージされた時、後のタスクを計画ブランチの最新を含む worktree で再検証してから done にする。状態遷移（5つ）は増やさない。

## 分割方針
- 案A（done の時点で計画ブランチが進んでいたら再検証）を採り、案B（planner が after を付けて並行にしない）は採らない。根拠：
  - 案Bは「リポジトリ全体を見る基準か」を planner が判断する運用で、plan_guard などで機械的に確かめられない（docs/vision.md 原則2「規律はプロンプトに頼らず仕組みで強制する」）。安いモデルでも安定させたい目的に対し、見落とした時に誤 PASS／誤 FAIL が残る。また smoke の `(ref-1)`・`fail=0` のように多くのタスクが持つ基準まで並行をやめることになり、並行実行の意味が薄れる
  - 案Aは transition.py の done が機械的に判定・強制できる。費用は、同じ組で2件目以降に PASS したタスクの verifier の呼び出しが1回ずつ増えるだけ（run の手順6は逐次なので、再検証の間に他のマージは入らず、1タスクにつき最大1回。1組で最大 HARNESS_MAX_PARALLEL−1 回）
  - 状態遷移への影響：再検証の間も status は review のままにし、log には既存の `--keep-attempt` と同じ形の `review→review` の行を書く。5状態・遷移表の7つは増やさない。新しいのは transition.py の終了コード6だけ
  - 古い判定で done にできないよう、取り込みの時に transition.py が verdict を消す（仕組みで強制）
- 判定：計画ブランチは transition.py の状態のコミット（非マージ）で毎回進むので、HEAD と plan_head の比較では常に真になる。他タスクの変更は done の `--no-ff` マージでだけ入るので、`git rev-list --count --merges --first-parent <plan-head>..HEAD` が1以上の時だけ再検証に回す
- タスク：T-01 で transition.py と smoke のテスト、T-02 で docs/vault-spec.md（と docs/decisions.md）、T-03 で run/SKILL.md。T-02・T-03 は文書だけで T-01 の成果物を確認コマンドに使わないので並行にする（挙動は各票の「決定済み」に書く）。T-01 がコードを変えるので、最後に計画単位のレビュータスク T-04 を置く
- 次フェーズの候補：なし

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | transition.py の done が、同じ組の他タスクのマージ後は計画ブランチを worktree に取り込み終了コード6で再検証に回す | |
| T-02 | doing | 1 | - | docs/vault-spec.md と docs/decisions.md に done の再検証（終了コード6）を書く | |
| T-03 | doing | 1 | - | run/SKILL.md に done の終了コード6で verifier を呼び直す手順を書く | |
| T-04 | todo | 0 | T-01,T-02,T-03 | 計画の差分が `/code-review` を通過する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
