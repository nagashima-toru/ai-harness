---
id: P-20261011-verifier-note-merge-base
status: approved
---
# ゴール
GitHub Issue #183 に対応する。`.claude/agents/verifier.md` の「手順」7の note の書式の例 `git diff --numstat -- README.md` は、`scripts/transition.py` が review への遷移で worktree の未コミット分を収集コミットにした後は空になる。例を、PR #185 で `.claude/agents/planner.md` の差分確認の指針に入れた形 `git diff --merge-base work/<計画IDの英小文字> --numstat -- <path>` に揃える。

## 分割方針
- 調査の結果、作業ツリーと比べる形（`git diff [--numstat] -- <path>`）の例は、`.claude/`・`docs/`・`README.md`・`vault/rules/`・`vault/templates/`・`scripts/` の中に3か所あった。成果物を1ファイルに絞るため、1か所ごとに1タスクにする。
  - `.claude/agents/verifier.md` 29行目（Issue #183 の本体）→ T-01
  - `.claude/agents/planner.md` 64行目の、形式の不変を見る確認コマンドの例 `git diff -- vault/plans/<計画ID>.md | grep -E ...` → T-02
  - `docs/vault-spec.md` 248行目の同じ例 → T-03
- T-01・T-02 は互いに依存しない。ゴールの範囲全体に古い形が残っていないことを見る基準は、3か所すべてが直った後でないと通らないので、最後の T-03 にだけ置き、T-03 の `after` を T-01,T-02 にする。
- 範囲外（変えない）：
  - `vault/rules/planner/ai-harness-lessons.md`・`.claude/agents/creator.md` 57行目の `git diff main -- ...`・`git diff --quiet` は、過去に起きたことの経緯の記録で、例ではないため。
  - `.claude/skills/run/SKILL.md` 172行目の `git diff <PLAN_HEAD>..HEAD -- ...`、`docs/vault-spec.md` 70行目・142行目の `git diff` は、コミットどうし（またはマージ衝突中のメインの作業ツリー）を比べる形で、収集コミットの影響を受けないため。
  - `vault/plans/`・`vault/tasks/`・`vault/log/`・`vault/verdicts/`・`vault/designs/` は、計画・記録が古い形を引用するのが当然で、ゴールの対象（手順書・仕様の例）ではないため。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | verifier.md の note の書式の例を merge-base の形にする | |
| T-02 | doing | 1 | - | planner.md の形式の不変を見る例を merge-base の形にする | |
| T-03 | todo | 0 | T-01,T-02 | vault-spec.md の形式の不変を見る例を merge-base の形にする | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
