---
id: P-20261021-worktree-base-and-criterion-pipe
status: approved
---
# ゴール
GitHub Issue #209 と #220 を1計画で直す。
- #209：`/run` 手順3で creator を Agent ツールの `isolation: "worktree"` で呼ぶと、`.claude/settings.json` が `worktree.baseRef: "head"` のままでも worktree が計画ブランチ（`PLAN_HEAD`）ではなく main（push 先ブランチの tip）から切られることがある（原因は未確定）。手順3.6 にこの症状の既知の原因と回避策（セッションを作り直して `/run` で再開する）を書き、オーケストレーターが `git worktree add -b <branch> <path> <PLAN_HEAD>` で起点を明示して worktree を作り、パスを creator に渡す経路を用意する（`--resume-worktree` と同じく prompt の `作業する worktree: <パス>` で渡す）。
- #220：`scripts/amend_task.py --replace-criterion` が基準の文に `transition.clean_text` を通しており、`|` が全角 `／` に変わる。基準の文は改行だけを空白にし、`|` はそのまま書く（`--note` は今のまま）。smoke に `|` が残る検査を足す。

## 分割方針
- #220 は T-01 の1タスクに閉じ、#209 のタスク（T-02〜T-05）とは依存させない（触るのは `scripts/amend_task.py` と `scripts/smoke.sh` の amend の検査の後ろだけで、T-02 の smoke の追加箇所（discard_worktree.sh の検査の後ろ）と離れている）。
- #209 は既存の仕組みを再利用する小さな設計にする。新しく作るのは worktree を作るスクリプト `scripts/add_worktree.sh` の1本だけで、作る worktree・ブランチの名前は Agent ツールと同じ形（`.claude/worktrees/agent-<8桁の16進>`・`worktree-agent-<同じ8桁>`）にするので、`scripts/discard_worktree.sh`・transition.py の `--worktree` の検証（`check_worktree`）・`--resume-worktree`・log の記録行はそのまま使える。creator には、unblock で引き継いだ id と同じく `isolation` を付けずにパスを prompt で渡す（この経路は既にある）。
  - T-02：スクリプト本体・install.sh の `SCRIPTS_FILES`・README のスクリプト表・smoke の検査
  - T-03：run/SKILL.md の手順3（作る経路への切り替えと、3.6 の既知の原因と回避策）。T-02 で作るスクリプトをバッククォートで参照するので T-02 の後
  - T-04：creator.md の受け渡し（`作業する worktree:` が新規の worktree にも来る）と `## git` 節。リポジトリ全体に isolation で creator を呼ぶ記述が残っていないことを確かめるので T-03 の後
  - T-05：docs/vault-spec.md の仕様と docs/decisions.md の記録。T-02 の後
- `.claude/settings.json` の `worktree.baseRef` は変えない（導入先へのマージ・smoke の install 検査が前提にしており、外すのは今回のゴールの外）。
- コードを変更するタスク（T-01・T-02）があるので、最後に計画単位のレビュータスク T-06 を置く。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | amend_task.py の --replace-criterion が基準の文の縦棒をそのまま残す | |
| T-02 | doing | 1 | - | 起点を明示して worktree を作る scripts/add_worktree.sh を足す | |
| T-03 | todo | 0 | T-02 | run 手順3で creator の worktree を add_worktree.sh で作り、3.6 に既知の原因と回避策を書く | |
| T-04 | todo | 0 | T-02,T-03 | creator.md の受け渡しと git 節を add_worktree.sh の経路に合わせる | |
| T-05 | todo | 0 | T-02 | vault-spec に add_worktree.sh の仕様を書き decisions に記録する | |
| T-06 | todo | 0 | T-01,T-02,T-03,T-04,T-05 | 計画の差分が `/code-review` を通過する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
