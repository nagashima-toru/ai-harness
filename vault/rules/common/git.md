## 目的
1セッション1計画1ブランチの前提で、ブランチ・コミット・PR・破棄の原則と、それぞれを誰が行うか（creator / オーケストレーター / 人）を定める。

## ルール
- ブランチ：`/plan` が計画ごとに1つだけ切る（`work/<計画IDの英小文字>`）。1ブランチ=1計画で、作業はそのブランチに閉じる。creator はブランチを切らない（run が worktree を用意する）
- `main` へは直接コミットしない。すべてのコミットは計画のブランチ上で行う（`agent_write_guard.py` がフックで強制する）
- コミット（creator）：creator のコミットは受け入れ基準に含まれている場合だけ行う
- コミット（オーケストレーター）：worktree に残った未コミット分は、PASS の後にオーケストレーター（run のメインセッション）がまとめてコミットし、計画ブランチへ `git merge --no-ff` で取り込む。計画票・log・verdict の状態遷移を書いてコミットするのもオーケストレーター
- PR：全タスクが `done` になった後、オーケストレーターが `bash scripts/vcs_finish.sh` で作る。マージは人が行う。エージェントは `gh pr merge` を実行しない
- 破棄：作業ツリーの変更の破棄は `git restore` だけを使い、`git clean` / `git reset --hard` は使わない（`.claude/settings.json` の `permissions.deny` で拒否済み）。不採用になった worktree の破棄は、オーケストレーターが `scripts/discard_worktree.sh` で行う
- コンフリクト（オーケストレーター）：計画ブランチへのマージで起きたコンフリクトは自己判断で解決しない。マージを行うオーケストレーターがタスクを `blocked` にし、question に状況を書いて人の判断を仰ぐ
- コンフリクト（creator）：判断が要る時は、自分で解決せずオーケストレーターに返す
- 手順の詳細は `vault/rules/creator/git-workflow.md` と `.claude/skills/run/SKILL.md` に従う

## 確認方法
- `bash scripts/rules.sh creator`（および `verifier`・`planner`）の出力に `vault/rules/common/git.md` が含まれるか
- 各行が真偽で判定できるか（ブランチが1計画1本か、creator のコミットが受け入れ基準にある分だけか、PR が `scripts/vcs_finish.sh` でだけ作られているか、`main` に直接コミットしていないか）
