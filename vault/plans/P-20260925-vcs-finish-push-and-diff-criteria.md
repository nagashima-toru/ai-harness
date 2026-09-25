---
id: P-20260925-vcs-finish-push-and-diff-criteria
status: done
---
# ゴール
GitHub issue #44 と issue #42 に対応する。2つは触るファイルが重ならず依存も無いため、1計画にまとめて2タスクとして並行に完了できるようにする。

- issue #44：`scripts/vcs_finish.sh` が `gh pr create`/`glab mr create` を呼ぶ前に、現在のブランチが `origin` に push 済みか（upstream の有無）を確認し、無ければ `git push -u origin <現在のブランチ>` を実行してから本来のコマンドを呼ぶようにする（人が決定済みの方針 (a)）。push 自体の失敗はそのまま伝播させてよい。
- issue #42：`vault/rules/planner/planner.md` に、「他タスクの成果物ファイルを変更していないこと」を確認する受け入れ基準の確認コマンドは `git diff main -- <path>` ではなく `git status --porcelain` ベース（成果物パス以外に変更が無いことを確認する形）で書くよう明記する（人が決定済みの方針 (a)）。`vault/rules/` は `agent_write_guard.py` が常に書き込みを拒否するため、成果物は提案ファイル方式（`vault/tasks/<計画ID>/T-02-proposal.md`）にする。実体への反映は人が行う。

## 分割方針
- 触るファイルが重ならない（`scripts/vcs_finish.sh` と `vault/tasks/<計画ID>/T-02-proposal.md`）ため、`after` 依存を付けず並行着手可能な2タスクに分ける
- issue #44 は既存の `github`/`gitlab` 分岐を持つ単一スクリプトの変更なので1タスクにまとめる（機能テストで push 有無・両ホスティング・失敗伝播を確認する）
- issue #42 はルール変更のため、`vault/rules/planner/planner.md` を直接触れない。提案ファイル方式（`docs/vault-spec.md` 12節）に従い、成果物を `vault/tasks/<計画ID>/T-02-proposal.md` にする1タスクとする
- どちらも人がすでに方針 (a) を決定済みのため、再検討や設計タスクは切らない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | vcs_finish.sh に PR/MR 作成前の自動 push を追加する（issue #44） | |
| T-02 | done | 1 | - | planner ルールに「他ファイル不変」基準を git status --porcelain ベースにする提案を書く（issue #42） | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01・T-02 とも `after` は `-`）
- 1タスクが1コンテキストで終わる粒度である
- T-01 は `scripts/vcs_finish.sh` のみを変更し、T-02 は `vault/tasks/<計画ID>/T-02-proposal.md` のみを変更する（`vault/rules/` 配下の実体は編集しない）
