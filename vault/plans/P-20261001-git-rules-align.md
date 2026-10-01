---
id: P-20261001-git-rules-align
status: approved
---
# ゴール

git 運用の記述を、現在の run の役割分担に揃える。役割分担は次のとおり：creator はブランチを切らず、コミットは受け入れ基準にある時だけ行う。worktree の未コミット分の収集・計画ブランチへのマージ・PR 作成（`bash scripts/vcs_finish.sh`）はオーケストレーターが行う。マージは人が行う。

1. `vault/rules/common/git.md` を改訂する。主語の無い「作業ステップごとにコミット」「全タスク done で gh pr create」を上の役割分担に合わせる。`vault/rules/creator/git-workflow.md`（フェーズ10で改訂済み）と矛盾させず、重複を避けて原則だけを書く。改訂後の git.md には、`.claude/skills/run/SKILL.md` の72行目（「コミットは受け入れ基準に含まれている場合だけ行う」）と76行目（「自己判断で解決しない」）が引用している文言を実在させ、出典の食い違いを解消する
2. 旧方式（creator が作業ステップごとにコミットする）を前提にした記述を直す。対象は `vault/rules/verifier/verifier.md` 19行目、`.claude/agents/verifier.md` 32行目、`docs/vault-spec.md` 22行目、`README.md` 69行目と76行目、`.claude/skills/run/SKILL.md` 111行目（主語の無い「コミットは受け入れ基準に含まれている場合だけ行う」）

`vault/rules/` の実体には書き込めないので、git.md と verifier.md の変更は提案ファイル（`vault/tasks/P-20261001-git-rules-align/<id>-proposal.md`）に全文で書く。実体への反映は人が行う。

## 分割方針
- ルールの提案は1タスク1ファイルにする。git.md は T-01、verifier.md は T-02
- 実体を直接直す4ファイルも、成果物を1つにする原則に従って1タスク1ファイルにする。`.claude/agents/verifier.md` は T-03、`docs/vault-spec.md` は T-04、`README.md` は T-05、`.claude/skills/run/SKILL.md` は T-06
- T-01〜T-06 は書き込むファイルがすべて別なので、互いに依存させず並行できる。T-02 と T-03 は verifier の同じ検査を記述しているので、両方の「決定済み」に同じ文案を書いて揃える
- smoke.sh で `fail=0` を確かめる作業は T-07 に切り出し、T-01〜T-06 の後に単独で動かす。smoke.sh は /tmp の固定パスを使うので、他タスクの受け入れ基準には入れない。T-07 では、SKILL.md の引用文言が T-01 の提案に実在することも突き合わせる

### 決定済み（人の回答。各タスク票にも写す）
- SKILL.md 72行目の出典の食い違いは案Aで解消する。git.md に creator のコミット原則を「コミットは受け入れ基準に含まれている場合だけ行う」の文言そのままで書き、SKILL.md 72行目の出典表記（`vault/rules/common/git.md`）は直さない（人の回答）
- SKILL.md 76行目の「`vault/rules/common/git.md` の既存方針」は、git.md 側の文言を「自己判断で解決しない」に揃えることで成り立たせる。76行目は直さない（人の回答）
- git.md の破棄のルールには「不採用の worktree の破棄はオーケストレーターが `scripts/discard_worktree.sh` で行う」の1句を足す（人の回答）
- git.md には原則と役割分担（誰が行うか）だけを書く。手順の詳細は書かない。具体的には、起点コミット、`blocked: <質問文>` の返し方、`git -C` のコマンド列、`git merge --abort` などで、これらは git-workflow.md と SKILL.md に任せる。PR 作成は `bash scripts/vcs_finish.sh` と書き、`gh pr create` の語は書かない
- verifier の宣言外ファイル検査（verifier.md 19行目・agents/verifier.md 32行目）について。理由付けを直すと、検査の範囲も変える必要がある。verifier が worktree に入る時点（run 手順5）は、オーケストレーターが未コミット分を収集する時点（手順6.3.1、PASS の後）より前なので、creator の変更はコミット済みの分と未コミットの分の両方にありうる。そのため検査対象を「`git diff --name-only <起点コミット>..HEAD` の出力」と「`git status --porcelain` に出る未コミットのファイル」の両方にする。除外対象・`note`/`reasons` の扱い・FAIL にしないことは変えない
- `docs/decisions.md`・過去の計画票・過去のタスク票・過去の設計文書にある旧方式の記述は直さない（経緯の記録のため）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | common/git.md 改訂版の提案を書く | |
| T-02 | done | 1 | - | verifier.md の宣言外ファイル検査の理由と範囲を直す提案を書く | |
| T-03 | done | 1 | - | agents/verifier.md 手順10の理由と範囲を直す | |
| T-04 | doing | 1 | - | vault-spec.md 22行目の証跡の説明を直す | |
| T-05 | doing | 1 | - | README.md の PR 作成の主語と手段を直す | |
| T-06 | doing | 1 | - | run SKILL.md 注意節のコミットの主語を creator にする | |
| T-07 | todo | 0 | T-01,T-02,T-03,T-04,T-05,T-06 | smoke を通し SKILL.md の引用と提案の一致を確認する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
- （着手を止めるものではない）verifier の宣言外ファイル検査に、未コミットのファイル（`git status --porcelain`）を加える件（T-02・T-03）。旧方式の理由付けを直すだけだと、「未コミット差分だけを見る方法では何も検出できない」という前提が成り立たなくなる。逆に検査をコミット済み（`起点コミット..HEAD`）だけに限ると、creator が受け入れ基準にコミットの無いタスクで書いた変更を取りこぼす。そのため検査範囲の追加まで含めて計画した。理由の文だけを直し、範囲は変えない方がよければ、着手前に指示してほしい
