---
id: P-20261022-unblock-clear-stale-verdict
status: approved
---
# ゴール
GitHub Issue #227「unblock 後の再実行で古い PASS の verdict が有効に見える（attempt が再び一致する）」を直す。`/plan unblock` は attempt を 0 に戻すので、前回の blocked の時の verdict（attempt=1, PASS）が残ると、再着手で review（attempt=1）になった時に新しい verifier の完了前に stop_gate が古い PASS を有効とみなす（誤ブロック・誤って done にする危険）。古い verdict を仕組みで（文書の指示だけに頼らず）除去し、メイン側（未追跡でも追跡済みでも）と worktree 側の両方で、`/run` 手順6の1のコピーで古い PASS が復活しないようにする。あわせて `.claude/skills/plan/SKILL.md` B節・`.claude/skills/run/SKILL.md` 手順6の1・`docs/vault-spec.md` を更新し、`scripts/smoke.sh` に回帰テストを足す。

## 分割方針
- 仕組みの置き場所：`scripts/transition.py` は blocked→todo を扱わない（解除は `/plan` の Edit のまま。`docs/vault-spec.md` 2節）。そのため同等の機械的な仕組みとして、再着手の todo→doing（通常の着手・`--resume-worktree` の両方）で `transition.py` がその id の古い verdict を除去する。todo の行は stop_gate の検査対象外で、古い verdict が害になるのは doing・review になってからなので、再着手の入口で消せば unblock の経路（`/plan` の Edit・人の手作業）に関係なく効く
- T-01 は仕組みの本体（`scripts/transition.py`）と回帰テスト（`scripts/smoke.sh`）。テストが本体の動作の確認そのものなので同じタスクにする
- T-02（`docs/vault-spec.md`）と T-03（スキルの文書2本）は文書の更新。T-02 は T-01 と並行できる（同じファイルを触らない・新しく作るファイルが無い）。T-03 は計画全体で古い記述が残っていないことを確かめるので T-01・T-02 の後に置く
- `.claude/hooks/stop_gate.py`・`.claude/hooks/_hooklib.py` は変えない（verdict の判定の仕方は正しく、古い verdict が残ることが問題のため）
- コードを変更するタスク（T-01）があるので、最後に計画単位のレビュータスク（T-04）を置く
- 参考：直接修正の旧案は PR #228（コミット 460f19f、plan/SKILL.md に1行足しただけ）で、文書の指示だけに頼るため不足として閉じた

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | 再着手の todo→doing で transition.py が古い verdict をメイン側と worktree 側から除去し、smoke に回帰テストがある | |
| T-02 | done | 1 | - | docs/vault-spec.md に再着手での古い verdict の除去の仕様が書かれている | |
| T-03 | done | 1 | T-01,T-02 | plan/SKILL.md の unblock と run/SKILL.md 手順6の1が古い verdict の除去に合っている | |
| T-04 | review | 1 | T-01,T-02,T-03 | 計画の差分が `/code-review` を通過する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
