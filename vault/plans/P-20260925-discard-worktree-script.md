---
id: P-20260925-discard-worktree-script
status: approved
---
# ゴール

`run` スキル手順6.3.2（verifier が FAIL で attempt が上限未満の時）が直接実行している `git worktree remove <worktree のパス> --force` と `git branch -D <ブランチ名>` を、新しいスクリプト `scripts/discard_worktree.sh <worktree のパス> <ブランチ名>` の呼び出しに置き換える（`vault/designs/D-006.md` フェーズ1）。

`.claude/settings.json` の deny ルール `Bash(git branch -D *)` は変更しない（スクリプトは既存 allow の `Bash(bash scripts/*)` で実行される）。スクリプトは以下をすべて確認してから削除を行い、確認に失敗した場合は何も削除せず非0で終わる。
1. 引数が2つであること
2. ブランチ名が `worktree-agent-` で始まること
3. `git worktree list --porcelain` 上で指定パスが登録済み worktree であり、その `branch` が `refs/heads/<ブランチ名>` と一致すること

`scripts/smoke.sh` に正常削除・拒否ケースを追加し、`scripts/install.sh` の配布対象とマニフェストにもスクリプトを加える（`scripts/uninstall.sh` はマニフェスト駆動のため変更不要）。PASS 時（手順6.3.1-4）の片付け手順は変更しない。

対象外（このタスクではやらない）：
- `settings.json` の deny ルールそのものの見直し
- PASS 時（手順6.3.1-4）の片付けをスクリプト経由にそろえること
- run 手順外で人やオーケストレーターが worktree を片付ける手順の整備
- `scripts/vcs_finish.sh` が `install.sh` の配布対象に無い件（別 issue）

`docs/vault-spec.md`・`docs/runbook.md` を確認したが、`git branch -D` を前提にした FAIL 時破棄手順の記述は無いため、この2ファイルは変更しない。

## 分割方針

1本のスクリプト新設が起点になるので、まず T-01 でスクリプト本体を契約として確定する（引数・検証条件・削除順序）。T-01 が決まれば、それを呼び出す側（`install.sh` での配布、`SKILL.md` での呼び出し置き換え）は互いに独立に進められるため、T-02（install.sh）と T-03（SKILL.md）は T-01 にのみ依存し、両者の間に依存関係は無い（並行可能）。

`scripts/smoke.sh` へのテストケース追加は、スクリプト本体（T-01）の挙動と、install.sh での配布・マニフェスト掲載（T-02）の両方を確認対象にするため、両方が揃ってから書く方が手戻りが無い。`P-20260924-uninstall-harness` の前例（`install.sh` 更新後に `smoke.sh` の回帰テストを追加する順序）にならい、T-04 は T-01・T-02 の後に置く。

依存に循環は無い：T-01 → {T-02, T-03}、T-02 → T-04（T-01 は T-02 経由で間接的に先行済み）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | scripts/discard_worktree.sh を作る（対象検証つき worktree/ブランチ破棄スクリプト） | |
| T-02 | todo | 0 | T-01 | scripts/install.sh に discard_worktree.sh を配布対象・マニフェスト対象として追加する | |
| T-03 | todo | 0 | T-01 | .claude/skills/run/SKILL.md 手順6.3.2 を discard_worktree.sh 呼び出しに置き換える | |
| T-04 | todo | 0 | T-01,T-02 | scripts/smoke.sh に discard_worktree.sh の動作確認ケース（正常系・拒否系3種・install配置確認）を追加する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01 → {T-02, T-03}、T-02 → T-04）
- 1タスクが1コンテキストで終わる粒度である
- 全タスク完了後、`bash scripts/smoke.sh | tail -1` が `fail=0` で終わる
- `.claude/settings.json` の `permissions.deny` に `Bash(git branch -D *)` が残っている（どのタスクも変更しない）。確認：`jq -r '.permissions.deny[]' .claude/settings.json | grep -Fx 'Bash(git branch -D *)'` がヒットする
- `.claude/hooks/agent_write_guard.py`・`docs/vault-spec.md`・`docs/runbook.md` を変更する成果物が無い
