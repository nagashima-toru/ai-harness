---
id: P-20261006-pr-task-history
status: approved
---
# ゴール
PR をスカッシュマージしてもタスクごとの履歴を PR 本文から辿れるようにする

PR をスカッシュマージすると main にタスクごとの履歴が残らない問題を解消する。`scripts/vcs_finish.sh` が作る PR 本文に、計画のタスクごとの一覧（タスク ID・title・コミット・verdict）を載せ、スカッシュマージ後も PR 本文から履歴を辿れるようにする。マージ方式はスカッシュを推奨し、運用を `docs/runbook.md` に明記する。

## 分割方針
- 本文の生成と PR 作成を分ける。T-01 で計画 ID を受けて本文（Markdown）を標準出力に出す `scripts/pr_body.py` を作り、T-02 で `scripts/vcs_finish.sh` がそれを呼ぶ。本文の生成は、リポジトリに既にある計画（`P-20261004-hooklib-rules` と、その計画ブランチに残っている `<計画ID>/<id>: done` コミット）を入力に、verifier が読み取りだけで確かめられる
- T-02 は `scripts/vcs_finish.sh` の変更と、それを確かめる `scripts/smoke.sh` の vcs_finish 節へのケース追加を1タスクにする。`gh`/`glab` をスタブにした smoke 以外に、PR 作成の経路を verifier が実際に動かして確かめる手段が無いため（変更と確認を別タスクにすると、T-02 の基準が grep だけになる）
- 引数を渡した時の素通し・計画が見つからないブランチ（`design/d-xxx` など）での `--fill`/`--fill --yes`・ホスティング無し（`none`）の案内は今のまま残す。D-013 で設計中の `HARNESS_PR_BODY_FILE` などの環境変数は、まだ無い前提で先取りしない
- 文書は1ファイル1タスクで、T-02 の挙動が決まった後に並行して直す。T-03 は運用（`docs/runbook.md`、スカッシュ推奨）、T-04 は run の手順（`.claude/skills/run/SKILL.md` 手順7。今の「引数なしは `--fill`」の記述が古くなる）、T-05 は仕様の正本（`docs/vault-spec.md` 1節の「証跡」の段落）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | 計画のタスク履歴表を PR 本文として出力する scripts/pr_body.py を作る | |
| T-02 | todo | 0 | T-01 | vcs_finish.sh が引数なしの時に計画のタスク履歴を PR/MR 本文に載せる（smoke.sh にケース追加） | |
| T-03 | todo | 0 | T-02 | docs/runbook.md に PR のマージ方式とタスク履歴の辿り方を書く | |
| T-04 | todo | 0 | T-02 | run/SKILL.md 手順7の vcs_finish.sh 引数なしの説明を新しい挙動に合わせる | |
| T-05 | todo | 0 | T-02 | docs/vault-spec.md 1節の証跡の段落に PR 本文のタスク履歴を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わる

## 人の回答（決定済み）
1. マージ方式の推奨：スカッシュマージを推奨する。GitHub の squash の既定コミットメッセージを `Pull request title and description` にして、タスク履歴表を main のコミットメッセージにも残す設定を勧める（設定は人が行う）。通常のマージも可
2. PR タイトル：`<計画ID>: <ゴールの1行目>`。ゴールの1行目は計画票の `# ゴール` 直後の最初の空でない行（この計画では「PR をスカッシュマージしてもタスクごとの履歴を PR 本文から辿れるようにする」）
3. コミット列：`<計画ID>/<id>: done` コミットの短縮ハッシュ（planner の前提のまま。回答なし）
