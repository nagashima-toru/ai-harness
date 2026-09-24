---
id: P-20260924-vcs-finish
status: approved
---
# ゴール
`run` スキルの最終手順（全タスク `done` 後の PR 作成）と `design` スキルの最終手順（設計文書提示後の
PR 作成案内）が直接呼んでいる `gh pr create` を、新しい共有スクリプト `scripts/vcs_finish.sh` の呼び
出しに置き換える。このスクリプトは、環境変数 `HARNESS_VCS_HOST`（`github`/`gitlab`/`none`。未設定ま
たは `auto` なら自動判定）に従って動作を分岐する：`github` なら `gh pr create "$@"` を、`gitlab` なら
`glab mr create "$@"` を実行してその終了コードをそのまま返す。自動判定は `git remote get-url origin`
の値に `github.com` を含めば `github`、`gitlab` を含めば `gitlab`、リモートが無い・どちらにも一致し
なければ `none` とする。`none` の場合は `gh`/`glab` を一切呼ばず、現在のブランチ名と、main への取り
込みに使う `git merge --no-ff <branch>` コマンドを標準出力に案内として書き、終了コード0で終わる（エ
ージェントはこのメッセージをそのまま人に伝える。自分でマージは実行しない）。`docs/vault-spec.md`
（計画票 `status: done` の定義、設計文書のブランチと PR の節）と `docs/runbook.md` の該当箇所も、
`gh pr create` 前提の記述からこのスクリプト経由の記述に更新する（GitHub issue #19、設計文書
`vault/designs/D-005.md` フェーズ1）。

## 分割方針
`vault/designs/D-005.md` フェーズ1は単一フェーズ・単一ゴールだが、成果物は独立した5ファイルにまた
がる（新規スクリプト1・スキル手順2・仕様書2）ため、ファイル単位で5タスクに割る。

- T-01（`scripts/vcs_finish.sh` 新規作成）：他タスクが参照する呼び出し方（環境変数名・分岐・出力形
  式）を確定する「契約」タスク。最初に着手する
- T-02（`.claude/skills/run/SKILL.md`）・T-03（`.claude/skills/design/SKILL.md`）・T-04
  （`docs/vault-spec.md`）・T-05（`docs/runbook.md`）：いずれも T-01 で確定した呼び出し方を前提に、
  各ファイル内の `gh pr create` 前提の記述を書き換えるだけの独立作業。成果物ファイルが互いに重ならず、
  4タスク間に依存関係は無いため、T-01 完了後は並行して着手できる
- 5タスクとも `vault/designs/D-005.md` の「決定済み」に answer が揃っているため、着手前に人へ追加で
  聞くことは無い
- 次フェーズの候補は無い（`D-005` は単一フェーズで完結する）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | scripts/vcs_finish.sh を新規作成しホスティング判定とPR/MR作成を実装する | |
| T-02 | done | 1 | T-01 | run スキルの最終手順を vcs_finish.sh 呼び出しに置き換える | |
| T-03 | done | 1 | T-01 | design スキルの最終手順を vcs_finish.sh 呼び出しに置き換える | |
| T-04 | done | 1 | T-01 | vault-spec.md の done 定義と設計文書のブランチ・PR 節を vcs_finish.sh 経由の記述に更新する | |
| T-05 | review | 1 | T-01 | runbook.md の PR 作成手順を vcs_finish.sh 経由の記述に更新する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
