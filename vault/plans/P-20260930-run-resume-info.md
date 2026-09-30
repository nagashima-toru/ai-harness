---
id: P-20260930-run-resume-info
status: draft
---
# ゴール
`.claude/skills/run/SKILL.md` を改訂し、オーケストレーターが creator の完了時に受け取る worktree のパス・ブランチ名と、手順3.1の `PLAN_HEAD` を、`vault/log/<計画ID>.md` に記録行 `- <日時> <id> worktree path=<パス> branch=<ブランチ名> plan_head=<sha>` として1行追記するようにする。手順2.2の再開手順を次のとおり書き換える。review の行は、log の最新の記録行から worktree を復元して手順5へ進む。記録された worktree が `git worktree list` に無ければ、doing に戻して attempt+1 で作り直す。doing の行は、中断を1回の試行として attempt+1 にし、creator を呼び直す（上限に達したら blocked）。`docs/vault-spec.md` 7節に記録行の書式を追記する（issue #78、`vault/designs/D-010.md` フェーズ6）。

PR 本文では `Closes #78` を使う。

## 分割方針
- 依存の軸：記録行の書式（vault-spec 7節）を先に確定し、SKILL.md の書く側（手順3）、読む側（手順2.2）の順で書式を参照させる。フック（stop_gate.py・plan_guard.py）は log を読まないので変更しない。「ハング時の復旧」節も変えない（F7 で扱う）
- `.claude/skills/run/SKILL.md` を T-02・T-03 が触るので `after` で直列にする
- T-01：`docs/vault-spec.md` 7節に記録行の書式を追記する（契約）
- T-02：run SKILL.md 手順3に記録行の追記手順を足し、手順3.4の「永続化は不要」を削除する
- T-03：run SKILL.md 手順2.2の再開手順を書き換える
- 3タスクで7以内。`bash scripts/smoke.sh` の `fail=0` は各タスクの受け入れ基準に含める（log の新書式が既存フックを壊さないため）。次フェーズ候補は無い（D-010 のフェーズ7以降は別の計画）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | docs/vault-spec.md 7節に worktree の記録行の書式を追記する | |
| T-02 | todo | 0 | T-01 | run SKILL.md 手順3に worktree 記録行の追記手順を足し「永続化は不要」を削除する | |
| T-03 | todo | 0 | T-02 | run SKILL.md 手順2.2の review・doing の再開手順を記録行を使う形に書き換える | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
