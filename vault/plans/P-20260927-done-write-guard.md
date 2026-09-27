---
id: P-20260927-done-write-guard
status: approved
---
# ゴール
`.claude/hooks/agent_write_guard.py` に、`agent_type` を問わず（メインセッション含む）適用する判定を追加する。書き込み先が `vault/tasks/<計画ID>/<id>.md` または `vault/verdicts/<計画ID>/<id>.json` で、かつ `vault/plans/<計画ID>.md` のタスク表でその id の status が `done` の場合は拒否する。計画票が見つからない・その id の行が無い・読めない場合は許可する（fail-open）。`docs/vault-spec.md` 12節に判定を1行追加し、`.claude/ai-harness.md` の「禁止」に「フックで拒否される」旨を追記する。`scripts/smoke.sh` にテストを足す（issue #76、`vault/designs/D-010.md` フェーズ2）。

## 分割方針
- T-01（`agent_write_guard.py` 本体の実装 + `scripts/smoke.sh` へのテスト追加）を先に切る。実装とその回帰テストは1PR分の関連する2ファイル変更として1タスクにまとめる（`P-20260926-write-guard-worktree-delegate`/T-01 と同じ扱い）。判定ロジックの詳細（対象パスの正規表現、判定順序、fail-open条件）はこのタスクで確定する
- T-02（`docs/vault-spec.md` 12節への1行追記）・T-03（`.claude/ai-harness.md`「禁止」への1行追記）は、いずれも T-01 が実装する挙動を正確に記述する必要があるため T-01 に `after` で依存させる。互いには依存せず、成果物もそれぞれ別の1ファイルなので T-01 完了後は並行して着手できる
- 3タスクとも成果物が1ファイル（またはT-01のみ関連2ファイル）に特定でき、粒度基準（1計画5〜7タスク以内）に十分収まる

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | agent_write_guard.py に done タスクへの書き込み拒否判定を追加し smoke.sh にテストを足す | |
| T-02 | todo | 0 | T-01 | vault-spec.md 12節に done タスク書き込み拒否判定を1行追記する | |
| T-03 | todo | 0 | T-01 | ai-harness.md の禁止節にフックで拒否される旨を追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
