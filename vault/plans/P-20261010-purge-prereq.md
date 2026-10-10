---
id: P-20261010-purge-prereq
status: approved
---
# ゴール
D-016 フェーズ2の一括削除（`bash scripts/purge_plan.sh --merged --apply`。`docs/runbook.md` 5節）を実行した後も `bash scripts/smoke.sh` が全部通るようにする。

計画時点で、一時 worktree で一括削除してから smoke を実行すると2件落ちる（pass=476 fail=2）：
1. `(ref-1) 主な文書のバッククォート内のパスがすべて存在する`：`vault/log/`（`.claude/ai-harness.md:23`・`.claude/agents/planner.md:33`・`docs/vault-spec.md:140`）と `vault/archive/`（`docs/vault-spec.md:26`・`docs/runbook.md:61`・`docs/runbook.md:85`）が削除後に存在しない。`vault/log/` は `.gitkeep` を足して残し、`vault/archive/` は文書側でバッククォートのパス参照にしない書き方に直す（`--apply` が vault/archive/ を消す説明は残す）
2. `(hooklib-rules) current_plan.sh: id・status が引用符付き → 引用符を外した計画 ID を出す`：`scripts/smoke.sh` が過去の計画のタスク票ディレクトリにあるフィクスチャ（`vault/tasks/P-20261004-hooklib-rules/fixtures-comment/`）を読んでいて、一括削除で消える。smoke が一時ディレクトリにフィクスチャを自分で作る形に直す

実際の一括削除はこの計画では行わない（マージ後に人の指示で行う）。

## 分割方針
- 1ファイル1タスクにする。同じファイルを2つのタスクで変えない
  - T-01：`docs/vault-spec.md` 26行目の `vault/archive/` をバッククォートのパス参照でない書き方にする
  - T-02：`docs/runbook.md` 61・85行目の `vault/archive/` を同じ書き方にする
  - T-03：`scripts/smoke.sh` のフィクスチャの依存を外し、一括削除した状態で smoke が全部通ることを確かめる（ゴール全体の確認。T-01・T-02 の後）
- T-01・T-02 は互いに依存しない（並行して取れる）。smoke.sh を変えるのは T-03 だけなので、smoke.sh を触るタスクは直列になる
- `vault/log/.gitkeep` は差分ゲート（`scripts/diff_gate.py` の `FORBIDDEN_PREFIXES`）が `vault/log/` 配下の変更を宣言があっても違反にするため、creator のタスクの成果物にできない。人が計画ブランチに足す前提にしている（「人への質問」の1）。`.claude/ai-harness.md`・`.claude/agents/planner.md`・`docs/vault-spec.md` 140行目の `vault/log/` の参照は、`.gitkeep` があれば一括削除後も実在するので文書は変えない
- smoke が `vault/` の計画の実ファイルに依存している箇所の洗い出し（計画時点）：`grep -nE 'ROOT/vault/(plans|tasks|verdicts|log|archive)' scripts/smoke.sh` の一致は1833行目（hooklib-rules の fixtures-comment）の1件だけ。そのほかの `vault/plans/P-*` などの出現は `$TMP` 配下に自分で作るフィクスチャで、一括削除の影響を受けない。実際に一時 worktree で一括削除して smoke を流した結果も、落ちたのは上の2件だけだった
- 一括削除した状態の確認は、作業ツリーを壊さないよう `git worktree add --detach` した一時 worktree（`/tmp/claude/<計画ID>-<タスクID>/wt`）で行い、`git worktree remove --force` で片づける。detached HEAD なので現在のブランチの計画の除外条件には当たらないが、この計画の計画票は approved（done でない）なので一括削除の対象にならない。`main` の版の計画票の status は共有の ref から読める

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | vault-spec.md の vault/archive/ をバッククォートのパス参照でない書き方にする | |
| T-02 | todo | 0 | - | runbook.md の vault/archive/ をバッククォートのパス参照でない書き方にする | |
| T-03 | todo | 0 | T-01,T-02 | smoke.sh の fixtures-comment の依存を外し、一括削除後も smoke が全部通ることを確かめる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問（回答済み）
1. `vault/log/.gitkeep` は、差分ゲート（`scripts/diff_gate.py`）が `vault/log/` 配下の変更を「宣言があっても違反」にするため、creator のタスクの成果物にできません（オーケストレーターも成果物は作りません）。次のどれにしますか。
   - (a) 承認の前に、人（または人の指示で `/plan` のセッション）が計画ブランチ `work/p-20261010-purge-prereq` に空の `vault/log/.gitkeep` を足してコミットする（計画の推奨。T-03 の受け入れ基準はこれを前提に `git ls-files vault/log/.gitkeep` を確かめる）
   - (b) この計画では足さず、PR のマージ前に人が足す（その場合 T-03 の「一括削除後の smoke が全部通る」は満たせないので、T-03 の基準を `vault/log/` の参照切れを除いた形に直す必要がある）
   - (c) 別の方法（文書の `vault/log/` をバッククォートの参照にしない等）。ゴールでは `.gitkeep` を足すと指定されているため、計画では採っていない
   - 回答：(a)。人の指示で /plan のセッションが計画ブランチに空の `vault/log/.gitkeep` を足してコミットした（48b14e9）
