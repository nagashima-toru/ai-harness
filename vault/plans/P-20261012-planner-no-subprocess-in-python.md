---
id: P-20261012-planner-no-subprocess-in-python
status: approved
---
# ゴール
GitHub Issue #187 の提案1を取り込む。`.claude/agents/planner.md` の「## やらないこと」に、確認コマンドを `python3 -c` の中から subprocess（`subprocess.check_output` 等）で git などの外部コマンドを呼ぶ形にしない旨の箇条を1つ加え、代わりの書き方（外部コマンドは単独のコマンドとして基準に書く・パイプ1段まで）と、planner 自身が確認コマンドをガードを通る形で試走してから書くことを示す。「## 書き終えた後の確認」にも対応する確認項目を1つ加える。

対象外：Issue #187 の提案2（`/plan` 手順2の detached HEAD 分岐。#178/#180 で `.claude/skills/plan/SKILL.md` に実装済み）と気づき3（creator の起動通知）。

## 分割方針
成果物は `.claude/agents/planner.md` の1ファイルで、追加は2箇条と小さいため、1タスクにまとめる。経緯集 `vault/rules/planner/ai-harness-lessons.md` への経緯の追記はゴールに含まれないため扱わない（次フェーズの候補に書く）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | planner.md に python3 -c 内の subprocess で外部コマンドを呼ぶ確認コマンドを禁じる指針を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- 経緯集 `vault/rules/planner/ai-harness-lessons.md` に、今回の教訓の経緯（Issue #187：導入先で `python3 -c` 内の `subprocess.check_output(['git','show',...])` を使う基準が creator の worktree で拒否された）を足す。ゴールの指定どおり今回は planner.md のみを成果物にし、票は起こさない。
