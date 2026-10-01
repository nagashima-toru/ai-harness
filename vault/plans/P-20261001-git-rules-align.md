---
id: P-20261001-git-rules-align
status: draft
---
# ゴール

`vault/rules/common/git.md` を改訂する。(1) 主語が書かれていない「作業ステップごとにコミット」「全タスク done で gh pr create」を、現在の run の役割分担に合わせる。役割分担は次のとおり：creator はブランチを切らず、コミットは受け入れ基準にある時だけ行う。worktree の未コミット分の収集・計画ブランチへのマージ・PR 作成（`bash scripts/vcs_finish.sh`）はオーケストレーターが行う。マージは人が行う。改訂は `vault/rules/creator/git-workflow.md`（フェーズ10で改訂済み）と矛盾させず、重複を避けて原則だけを書く。(2) `.claude/skills/run/SKILL.md` の手順6.3.1（72行目）は、creator の「コミットは受け入れ基準に含まれている場合だけ行う」方針の出典を `vault/rules/common/git.md` としているが、git.md にその記述が無い。この食い違いを解消する。手順6.3.5（76行目）の「`vault/rules/common/git.md` の既存方針」（コンフリクトは自己判断で解決しない）の参照も、改訂後に成り立つようにする。

`vault/rules/` の実体には書き込めないので、git.md の変更は提案ファイル（`vault/tasks/P-20261001-git-rules-align/T-01-proposal.md`）に全文で書く。実体への反映は人が行う。

## 分割方針
- (2) は「git.md に書く（SKILL.md は直さない）」案を推奨として計画した（理由は末尾「人への質問」）。この案では、(1) の改訂で git.md に creator のコミット原則を書く。その文言を SKILL.md 72行目の引用と一字一句同じにし、76行目の引用（「自己判断で解決しない」）とも同じにすることで、SKILL.md を変えずに参照を成り立たせる。そのため (1) と (2) は同じ提案ファイル1つ（T-01）にまとめる
- smoke.sh で `fail=0` を確かめる作業は T-02 に切り出し、T-01 の後に単独で動かす。smoke.sh は /tmp の固定パスを使うので、他タスクの受け入れ基準には入れない。T-02 では、SKILL.md の2か所の引用文言が提案ファイルにあることも突き合わせる
- 人が「SKILL.md の出典を `vault/rules/creator/git-workflow.md` に直す」案（人への質問の案B）を選んだ場合は、SKILL.md の実体を変えるタスクを別に起こす。T-02 の `after` にそのタスクを加え、T-01 の「決定済み」のうち引用文言の一致に関する項目を外す。今回は票を起こしていない

### 決定済み（各タスク票にも写す）
- git.md には原則と役割分担（誰が行うか）だけを書く。手順の詳細は書かない。具体的には、起点コミット、`blocked: <質問文>` の返し方、`git -C` のコマンド列、`git merge --abort` などで、これらは `vault/rules/creator/git-workflow.md` と `.claude/skills/run/SKILL.md` に任せる
- PR 作成は `bash scripts/vcs_finish.sh` と書き、`gh pr create` の語は書かない（vcs_finish.sh が GitHub・GitLab・ホスティング無しを振り分けるため）
- `.claude/agents/verifier.md`・`vault/rules/verifier/verifier.md`・`docs/vault-spec.md` 22行目・`README.md` 69/76行目にも旧方式の記述が残っているが、この計画では変更しない（ゴール外。「次フェーズの候補」に記載）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | common/git.md 改訂版の提案を書く | |
| T-02 | todo | 0 | T-01 | smoke を通し SKILL.md の引用と提案の一致を確認する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- `vault/rules/verifier/verifier.md` 19行目と `.claude/agents/verifier.md` 32行目に「creator は作業ステップごとにコミットするため」という理由付けが残っており、現在の run の役割分担（creator は受け入れ基準にある時だけコミットし、未コミット分はオーケストレーターが収集する）と合っていない。起点コミットを使った検査そのものは引き続き有効だが、理由の文を直す必要がある
- `docs/vault-spec.md` 22行目の「git のステップごとのコミット」と、`README.md` 69/76行目の「gh pr create」（主語はエージェント）も、vcs_finish.sh とオーケストレーターの記述に合わせる候補になる
- `.claude/skills/run/SKILL.md` 111行目（「注意」節）の「git のコミットはタスク票の受け入れ基準に含まれている場合だけ行う」は主語が無い。読み手はオーケストレーター（run のメインセッション）なので、手順6.3.1 で行うオーケストレーター自身のコミットと矛盾して読める

## 人への質問
- （推奨案で着手できる。案Bを選ぶ場合だけ回答がほしい）SKILL.md 72行目の出典の食い違いをどう解消するか。
  - 案A（推奨）：git.md に「creator のコミットは受け入れ基準に含まれている場合だけ行う」を原則として書く。SKILL.md は直さない。理由は4つ。1つ目に、ゴール(1)でこの原則はもともと git.md に書く内容である。2つ目に、git-workflow.md 自身が「原則の理由は `vault/rules/common/git.md` に譲る」と書いており、原則は common、手順は creator という配置に合う。3つ目に、common/git.md は verifier・planner にも配られるので、verifier が「未コミット分はオーケストレーターが収集する」前提を知っている方がよい。4つ目に、SKILL.md の実体を変えずに済み、変更が1ファイルの提案に収まる。欠点は、人が提案を実体へ反映するまで食い違いが残ること
  - 案B：SKILL.md 72行目の出典を `vault/rules/creator/git-workflow.md` に直す。git-workflow.md には既に「受け入れ基準にある時だけ行う」があるので、すぐに食い違いが解消する。ただし、git.md にも同じ原則を書く(1)と組み合わせると出典が2か所に分かれる。また SKILL.md の実体を変える別タスクが要る
- 76行目の「`vault/rules/common/git.md` の既存方針」（コンフリクトは自己判断で解決しない）について。現行の git.md の語は「自己判断で解決せず」で、意味は合っているが文言が一致していない。T-01 では「自己判断で解決しない」の語で書き、主語をオーケストレーター（マージを行う者）にする。これで参照は成り立つので、SKILL.md 76行目は直さない計画にした
- （確認）現行 git.md の「変更を破棄する時は `git restore` のみ」は、run の FAIL 再試行でオーケストレーターが `scripts/discard_worktree.sh` によって worktree を破棄する運用と、字面の上でぶつかる。T-01 では「作業ツリーの変更の破棄は `git restore` のみ。不採用の worktree の破棄はオーケストレーターが `scripts/discard_worktree.sh` で行う」と、役割分担に合わせて1句足す。足さない方がよければ指示してほしい
