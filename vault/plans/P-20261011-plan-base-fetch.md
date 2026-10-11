---
id: P-20261011-plan-base-fetch
status: approved
---
# ゴール
GitHub Issue #175（/plan・/design: クラウドセッションでローカルの main が古く開始条件で止まる）に対応する。`/plan` 手順A-2 と `/design` 手順1 の開始条件の確認の前に、`git fetch origin <ベースブランチ>:<ベースブランチ>` を best-effort で1回行う手順を入れ、同じ開始条件を説明する文書の記述をそろえる。

## 分割方針
- T-01：手順の正本である `.claude/skills/plan/SKILL.md`（手順A-2）と `.claude/skills/design/SKILL.md`（手順1）に、同じ文言で fetch 手順を入れ、「`origin/<ベース>` との比較や fetch はしない」を書き換える。2ファイルは同じ段落の同じ変更なので1タスクにまとめる（主な成果物は plan の SKILL.md）
- T-02：開始条件を説明している `docs/vault-spec.md`（`HARNESS_PUSH_BRANCH` の段落）の「`origin/<ベース>` の fetch はしない」を同じ趣旨に直し、`docs/decisions.md` に判断の変更を1行追記する。リポジトリ全体に古い記述が残っていないことの確認は T-01 の後でないと通らないので `after` を T-01 にする
- 確認したこと（計画時点）：`.claude/settings.json` の許可リストの `Bash(git *)` で `git fetch` は通り、deny（`git push --force` 系）には当たらない。`.claude/hooks/` と `scripts/smoke.sh`・`tests/` に fetch や該当文言を検査するものは無い。`docs/guide.md`・`docs/runbook.md`・`docs/install.md` の開始条件の記述は fetch に触れておらず、矛盾しないので対象にしない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | /plan 手順A-2・/design 手順1 の開始条件の前に best-effort の git fetch を入れる | |
| T-02 | todo | 0 | T-01 | vault-spec の開始条件の記述を fetch 手順に合わせ、decisions に判断の変更を記録する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
