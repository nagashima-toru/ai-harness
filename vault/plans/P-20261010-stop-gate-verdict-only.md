---
id: P-20261010-stop-gate-verdict-only
status: approved
---
# ゴール
stop_gate を verdict の検査だけにする（D-015 フェーズ4）

`.claude/hooks/stop_gate.py` から、未コミットの変更でのブロックを削る。判定は、worktree への委譲・`stop_hook_active`・approved な計画票の件数・done の行の verdict・doing/review の行の verdict だけにする。`scripts/smoke.sh` の未コミットのケースを、ブロックしないことを確かめる形に直し、`docs/vault-spec.md` 9節の判定表を合わせる。

正本は `vault/designs/D-015.md` の「## フェーズ4 stop_gate を verdict の検査だけにする」（ゴール文・受け入れ基準の候補・決定済み）。

## 分割方針
- コードとテスト（`stop_gate.py` と smoke のケース）を T-01 に、文書（`docs/vault-spec.md` 9節）を T-02 に分ける。T-02 は T-01 の後（直列）
  - コードとテストを分けないのは、未コミットの判定を削った時点で smoke の既存ケース（(f) と `(stop_gate worktree) 未コミットのファイルがある → ブロック`）が NG になり、同じタスクで直さないと `fail=0` を満たせないため
- 計画作成時の調査：`has_uncommitted_changes` を使うのは `stop_gate.py` だけ（`git grep -n has_uncommitted_changes -- .claude scripts docs` で、ほかは `scripts/smoke.sh` 160行のコメントだけ）。D-015 の決定済みに従い削る。`import subprocess` もこの関数でしか使っていない
- `scripts/run_unattended.py` と `HARNESS_STRICT_STOP` の既定は変えない（D-015 の決定済み）。どのタスクの成果物にも入れない
- 計画作成時点の smoke は `pass=471 fail=0`。受け入れ基準は件数ではなく `fail=0` とケース名で見る
- 9節以外の文書（runbook など）の古い記述はフェーズ5で揃えるので、この計画では扱わない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | stop_gate.py から未コミットの変更でのブロックを削り smoke のケースを直す | |
| T-02 | todo | 0 | T-01 | docs/vault-spec.md 9節の判定順と判定表から未コミットの変更を外す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む

## 次フェーズの候補（票は起こさない）
- D-015 フェーズ5（文書を守りを絞った後の姿に揃える）。この計画には含めない
