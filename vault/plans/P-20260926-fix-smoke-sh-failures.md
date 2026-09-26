---
id: P-20260926-fix-smoke-sh-failures
status: approved
---
# ゴール

issue #59 対応。`bash scripts/smoke.sh` に、着手前 HEAD（`acc5de6` 時点、その後 `b47e507` まで進んでも変わらず）から既に存在する既知の未修正の失敗が複数あり、タスクの受け入れ基準で「全件PASS」を確認コマンドにすると毎回 blocked 判断が必要になる問題を解消する。既存の失敗をそれぞれ根本原因まで特定して修正し、`bash scripts/smoke.sh` が fail=0 で通る状態に戻す。あわせて、今回のような環境依存の失敗が今後 `.claude/hooks/`・`scripts/` を触るタスクのたびに blocked を誘発しないよう、planner 向けの指針を追記する提案を作る。

### 現状の失敗（このブランチの HEAD で実測。`bash scripts/smoke.sh` → `smoke: pass=152 fail=4`）
1. `(worktree) verifier が worktree 内の vault/verdicts/ に Write（CLAUDE_PROJECT_DIR はメインチェックアウト側のまま）→ 許可`（want=allow got=deny）
2. `(worktree nested) verifier が worktree 内の未作成ネストディレクトリ vault/verdicts/P-NEW/ に Write（事前 mkdir なし）→ 許可`（want=allow got=deny）
3. `新規インストール先で参照される scripts がすべて揃っている`（want='' got='hello.sh'）
4. `(a) discard_worktree.sh 正常系: worktree/ブランチとも削除されrc0`（want='True' got='False'）

### 特定した根本原因（それぞれ別ファイル・別原因）
- 1・2：`.claude/hooks/agent_write_guard.py` の `normalize()` が `os.path.abspath()` しか使わず、シンボリックリンクを解決しない。macOS では `mktemp -d` が返すパス（`/var/folders/...`）と `git rev-parse --show-toplevel` が返す解決済みパス（`/private/var/folders/...`）が食い違うため、worktree 内の書き込み先を「root の外」と誤判定して deny してしまう。実機で `mktemp -d` の結果と `git rev-parse --show-toplevel` の結果を比較し再現を確認済み。
- 4：`scripts/discard_worktree.sh` が `TARGET_PATH` を `os.path.abspath()` で求めており、同じ macOS の `/var` ↔ `/private/var` シンボリックリンク解決の食い違いにより `git worktree list --porcelain` の `worktree <path>` 行と文字列が一致せず、「登録済み worktree ではありません」と誤判定して何も削除しない。
- 3：`scripts/install.sh` の `.claude/` 複製ループ（136行目 `for f in $(cd "$SRC/.claude" && find . -type f ...)`）が `.claude/worktrees/`（`.gitignore` 済みの、実行中に作られる git worktree の実体ディレクトリ）を除外していない。このリポジトリには現在 `.claude/worktrees/agent-ad253953d267a95f7/` という未削除の worktree（リポジトリ全体の入れ子コピー）が実在し、これを新規インストール先へまるごと複製してしまう。その入れ子コピー内の `docs/roadmap-rules-extension.md`・`vault/archive/2026-09/tasks/T-0014.md` に例示テキストとして書かれている `scripts/hello.sh`（実在しないダミー名）を `scripts/smoke.sh` の `missing_referenced_scripts()` が「参照されているのに無い」と誤検知する。実際に `bash scripts/install.sh <tmp>` を実行し、複製先に `.claude/worktrees/agent-.../docs/roadmap-rules-extension.md` が複製されることを確認済み。`.claude/worktrees/` 配下に未削除 worktree が残っている限り、どの内容が複製されるか・件数が変わるフレーキーな性質を持つ。

## 分割方針
4つの失敗はそれぞれ独立した1ファイルの修正で閉じる（T-01〜T-04）。ファイルが重ならず、依存関係も無いため `after` は付けず、並行して着手できる（`HARNESS_MAX_PARALLEL` の範囲で同時 doing 可）。

- T-01：`.claude/hooks/agent_write_guard.py`（失敗1・2の根本原因）
- T-02：`scripts/discard_worktree.sh`（失敗4の根本原因）
- T-03：`scripts/install.sh`（失敗3の根本原因。`.claude/worktrees/` を複製対象から除外する）
- T-04：`scripts/smoke.sh` の `missing_referenced_scripts()`（issue の提案2。T-03 だけで失敗3は解消する見込みだが、`.claude/worktrees/` 配下の走査除外はテスト自身の頑健性としても独立に価値があるため、T-03 とは別ファイル・別タスクとして行う。T-03 への依存は付けない＝どちらが先でも成立する）

T-05 は issue の提案3（planner 向け指針の追記）。`vault/rules/` への書き込みはどのエージェントも常に拒否されるため（`docs/vault-spec.md` 12節）、成果物は実体パスではなく提案ファイル `vault/tasks/P-20260926-fix-smoke-sh-failures/T-05-proposal.md` にする。他タスクの成果物ファイルとは重ならないため、依存は付けない。

各タスクの受け入れ基準は「該当する失敗ケースが `ok` になること」と「他のケースに新規の `NG` が増えていないこと（回帰が無いこと）」で判定する。T-01〜T-04 が全て `done` になった時点で `bash scripts/smoke.sh` の合計は `fail=0` になる見込みだが、各タスク単体の受け入れ基準では「全件PASS（fail=0）」という他タスク分も含めた合成条件は書かない（他タスクの完了順序に依存する基準は1タスクの受け入れ基準として不適切であり、今回の issue の発端そのものである「合成された全件PASSを基準にすると個々のタスクが人の判断待ちで詰まる」問題を再発させないため）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | agent_write_guard.py のパス比較でシンボリックリンクを解決し worktree 誤 deny を無くす | |
| T-02 | done | 1 | - | discard_worktree.sh のパス比較でシンボリックリンクを解決し worktree 削除判定を安定させる | |
| T-03 | done | 1 | - | install.sh の複製対象から .claude/worktrees/ を除外する | |
| T-04 | done | 1 | - | smoke.sh の missing_referenced_scripts が .claude/worktrees/ 配下を誤検知しないようにする | |
| T-05 | review | 1 | - | smoke.sh の全件PASSを基準にする際の指針を planner ルールへ追記する提案を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
（なし。issue #59 本文の提案1〜3をいずれも採用し、実機再現で特定した根本原因ごとに分割した。提案4「何もしない」は不採用）
