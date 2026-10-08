---
id: P-20261008-agent-role-merge
status: approved
---
# ゴール
標準の役割定義6本をエージェント定義に統合し、`vault/rules/` を導入先のルール専用にする（D-013 フェーズ4）

`vault/rules/` にある標準の役割定義6本（`vault/rules/common/roles.md`・`vault/rules/common/git.md`・`vault/rules/creator/creator.md`・`vault/rules/creator/git-workflow.md`・`vault/rules/verifier/verifier.md`・`vault/rules/planner/planner.md`）の内容を `.claude/agents/creator.md`・`.claude/agents/verifier.md`・`.claude/agents/planner.md` に統合する。`scripts/install.sh` は6本を配らなくし、`--update` では既存のマニフェストのハッシュで未編集と判定したものだけを削除し、編集済みのものは残して `note` で案内する。`scripts/uninstall.sh` も合わせる。`docs/vault-spec.md` 11節と `README.md` の拡張ポイントの節を「ハーネスは標準ルールを同梱しない。役割定義は `.claude/agents/` にある」の形にし、ほかの文書に残る6本への参照も「役割定義は `.claude/agents/` にある」に書き換える（人の回答で、フェーズ7に回さず今回直す）。`vault/rules/README.md` の書き換え案と、`vault/rules/planner/ai-harness-lessons.md` の参照先の直しの案を、それぞれ提案ファイルにする。

正本は `vault/designs/D-013.md` の「フェーズ4 標準の役割定義をエージェント定義に統合する」（ゴール文・受け入れ基準の候補・決定済み・依存）。`scripts/rules.sh` は変えない。`vault/rules/` の実体（6本の削除・README.md・ai-harness-lessons.md）は人が直す。

## 分割方針
- エージェント定義ごとに1タスクにする（成果物を1つに保つ）。3本は別ファイルなので並行してよい
  - T-01：`.claude/agents/creator.md` ← `roles.md` の creator が関わる節・`git.md`・`creator/creator.md`・`creator/git-workflow.md`
  - T-02：`.claude/agents/verifier.md` ← `verifier/verifier.md`・`roles.md` の verifier が関わる節・`git.md` の verifier に関係する部分
  - T-03：`.claude/agents/planner.md` ← `planner/planner.md`・`roles.md` の planner が関わる節・`git.md` の planner に関係する部分
- T-04：`scripts/install.sh`（主）・`scripts/uninstall.sh`・`scripts/smoke.sh`。エージェント定義とは独立なので T-01〜T-03 と並行してよい。`scripts/smoke.sh` を変えるのはこのタスクだけ
- T-05：文書に残る6本への参照をすべて直す。対象は `docs/vault-spec.md`（11節と6節167行目）・`README.md`（拡張ポイントの節）・`docs/install.md`（34・92・174行目と「ハーネスを更新する」節）・`.claude/skills/run/SKILL.md`（70・116・145行目）・`.claude/ai-harness.md`（24行目）・`docs/third-party-notices.md`（47〜55行目）。どれも数行の書き換えで、成果物は「文書の6本への参照の書き換え」1つとしてまとめる（小さな文書の直しを分けすぎない。人の回答）。T-01〜T-04 の後（統合先の節名と install.sh の新しい動きを書くため。`docs/install.md` は T-04 の後に置く）
- T-06：`vault/rules/README.md` の書き換え案を `vault/tasks/P-20261008-agent-role-merge/T-06-proposal.md` に書く。T-05 の後（文言を揃えるため）
- T-07：`vault/rules/planner/ai-harness-lessons.md` の参照先の直しの案を `vault/tasks/P-20261008-agent-role-merge/T-07-proposal.md` に書く。T-03 の後（統合後の planner.md の節名に合わせるため）。T-06 とは別ファイル・別タスク（人の回答）
- 同じファイルを2つのタスクで変えない（`docs/vault-spec.md` 6節167行目は T-05 に入れた）
- 各タスクは単体でマージしても smoke が `fail=0` で通る。6本が `vault/rules/` に残っている間も、人が削除した後も通るようにする（smoke は `$ROOT/vault/rules/` の6本を読まない）
- smoke の件数は計画作成時点で `smoke: pass=681 fail=0`。受け入れ基準は件数ではなく `fail=0` とケース名で見る
- 統合で落とした記述・言い換えた記述は、T-01〜T-03 の「進捗」に「落とした記述:」「言い換えた記述:」の行で列挙する（PR 本文に載せるため）。受け入れ基準には入れない（verifier は「進捗」を根拠にしない）
- 6本への参照の洗い出しは計画作成時に `git grep` で行った（`vault/rules/`・`vault/designs/`・`vault/tasks/`・`vault/plans/`・`vault/log/`・`vault/verdicts/`・`vault/archive/` は対象外）。見つかったのは上の T-04・T-05 の対象だけ。`scripts/smoke.sh` の 241〜584行目にある `vault/rules/common/roles.md` などは書き込みガードの試験用のコマンド文字列で、ファイルを参照していないので残す。`docs/decisions.md` は判断の記録なので直さない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | 標準ルールの creator 向けの内容を .claude/agents/creator.md に統合する | |
| T-02 | done | 1 | - | 標準ルールの verifier 向けの内容を .claude/agents/verifier.md に統合する | |
| T-03 | done | 1 | - | 標準ルールの planner 向けの内容を .claude/agents/planner.md に統合する | |
| T-04 | done | 1 | - | install.sh が標準ルール6本を配らず、--update で未編集のものを削除する | |
| T-05 | doing | 1 | T-01,T-02,T-03,T-04 | 文書に残る標準ルール6本への参照を「役割定義は .claude/agents/ にある」に書き換える | |
| T-06 | todo | 0 | T-05 | vault/rules/README.md の書き換え案を提案ファイルに書く | |
| T-07 | done | 1 | T-03 | ai-harness-lessons.md の planner.md への参照の直し案を提案ファイルに書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む
- `vault/rules/` は変わっていない（`git status --porcelain -- vault/rules` が空。6本の削除・README.md・ai-harness-lessons.md への反映は人が行う）
- 6本への参照が、`vault/`・`scripts/smoke.sh`（ガードの試験用の文字列）・`scripts/install.sh`（削除の対象の一覧）の外に残っていない：`git grep -nE 'vault/rules/(common/roles|common/git|creator/creator|creator/git-workflow|verifier/verifier|planner/planner)\.md|(^|[^/])(common/roles|common/git|creator/creator|creator/git-workflow|verifier/verifier|planner/planner)\.md' -- ':!vault' ':!scripts/smoke.sh' ':!scripts/install.sh'` の出力が空

## 人が行う作業（PR のマージ前に同じブランチで）
- T-06 の提案ファイルの「人が行う作業」節に従い、6本を `git rm` し、提案の全文を `vault/rules/README.md` に反映する
- T-07 の提案ファイルに従い、`vault/rules/planner/ai-harness-lessons.md` の参照先を手で書き換える
- 上の2つをコミットし、`bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` を含むことを確かめる
- エージェントは `vault/rules/` に書けないため、どれもタスクにも成果物にも入れない

## 人への質問
1. （回答済み）6本への参照のうち、11節・拡張ポイントの節の外にあるもの（`.claude/ai-harness.md` 24行目、`.claude/skills/run/SKILL.md` 70・116・145行目、`docs/vault-spec.md` 167行目、`docs/install.md` 34・92・174行目、`docs/third-party-notices.md` 47〜55行目）をどうするか → 人の回答：フェーズ7に回さず今回の計画で全部直す。直し方は「役割定義は `.claude/agents/` にある」への書き換え。T-05 に入れた
2. （回答済み）`vault/rules/planner/ai-harness-lessons.md` が `vault/rules/planner/planner.md` を指している件 → 人の回答：参照先の直しの案を提案ファイルにする（T-06 とは別タスク）。反映は人が行う。T-07 に入れた
