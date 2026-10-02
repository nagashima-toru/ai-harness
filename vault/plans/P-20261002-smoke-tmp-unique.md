---
id: P-20261002-smoke-tmp-unique
status: approved
---
# ゴール
GitHub Issue **#95**（P1 bug）「smoke.sh が /tmp の固定パスを使うため、並行 creator/verifier で偽の fail が出る」を解決する。
`scripts/smoke.sh` に残る `/tmp/P-...` の固定パスを、実行ごとに一意なパス（`$TMP` 配下）へ置き換え、`bash scripts/smoke.sh` を同時に複数走らせても fail が出ないようにする。テスト件数・各テストの判定は変えない。

## 分割方針
**現状（計画時点に planner が確認）**
- 逐次実行：`smoke: pass=435 fail=0`（Issue 記載時は 358 件だったが、その後テストが増えた）
- 3並列で同時実行：`smoke: pass=417 fail=18` / `pass=419 fail=16` / `pass=418 fail=17`。NG は `(approve-post)`・`(unblock-post)` に集中しており、固定パスの git フィクスチャ（`AP_REPO`・`UP_REPO`）と会話記録ファイル（`AP_TRANSCRIPT`・`UB_TRANSCRIPT`）を取り合っている
- 冒頭の `TMP="$(mktemp -d)"` と `trap 'rm -rf "$TMP"' EXIT`（11〜12行目）、その他の `mktemp -d` 利用は問題ない
- 固定パスが実体として作られる・読まれる箇所は10行：`TG_HOME`（471）・`AP_TRANSCRIPT`（545）・存在しない会話記録パス（592・805・883）・`UB_TRANSCRIPT`（610）・`AP_REPO`（757）・`UP_REPO`（833）・`RU_PID`/`RU_ERR`（1354〜1355）。`grep -nE '(=|")/tmp/P-' scripts/smoke.sh` でちょうどこの10行が出る
- 対象外：`run_guard`・`bp`・`bpc`・`expect_tg` などに渡す JSON / コマンド文字列内の `/tmp/x`・`/tmp/a`・`/tmp/P-20261002-write-guard-false-positive-note.md` 等（ガードに文字列として渡すだけで実ファイルを作らない）、model_stats のログ本文の `path=/tmp/wt-T-01`（1381、ログの文字列）

**方式**
- 固定パスをすべて `$TMP` 配下の実行ごとに一意なパスに置き換える。後始末は既存の EXIT trap（`rm -rf "$TMP"`）に寄せ、新たな `rm -rf` は書かない
- 修正は `scripts/smoke.sh` 1ファイルで閉じるため、1タスクにする
- Issue の提案2つ目（run スキルに smoke.sh を逐次呼ぶ旨の注記）は、根本修正で不要になるので入れない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | smoke.sh の /tmp 固定パスを $TMP 配下の一意なパスに置き換える | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
