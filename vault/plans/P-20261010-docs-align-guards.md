---
id: P-20261010-docs-align-guards
status: approved
---
# ゴール
文書を守りを絞った後の姿に揃える（D-015 フェーズ5）

`docs/runbook.md`・`docs/install.md`・`docs/vault-spec.md`・`docs/vision.md`・`docs/decisions.md`・`.claude/ai-harness.md`・`README.md`・`vault/rules/README.md`・`.claude/agents/planner.md`・`.claude/agents/creator.md` を、フェーズ1〜4 の後の実際の状態（`.claude/settings.json`・`.claude/hooks/*.py`・`scripts/diff_gate.py`・`.claude/skills/plan/SKILL.md`・`.claude/skills/run/SKILL.md` を正とする）に揃える。

- runbook の冒頭の「人の仕事」を「ゴールを入れる・blocked に答える・PR をマージする・月次で片づける」にする
- runbook の「困ったとき」に、git が半端な状態（merge・rebase の途中、HEAD と作業ツリーの食い違い）になった時にエージェントが自分で直す手順（`git merge --abort`・`git rebase --abort`・作業ブランチでの `git reset --hard`）を足す
- `docs/decisions.md` に、守りを絞った判断（D-015 の決定事項の1行目）を理由付きで1行足す
- runbook に「権限モードの選び方」の節を足す：ハーネス自身（`.claude/`）を変える計画は acceptEdits で立ち上げ、それ以外は auto モードでよい。auto モードで Self-Modification の拒否が出て blocked になった時は、acceptEdits で立ち上げ直して `/plan unblock` → `/run` で再開する
- `.claude/agents/planner.md` の受け入れ基準の指針に「受け入れ基準はゴールの達成を確認する。確認の範囲は成果物ではなくゴールの範囲（例：古い記述が残っていないことはリポジトリ全体）にし、除外する範囲は理由と一緒に決定済みに書く」を足す

文書の変更だけで、コード・設定は変えない（agents の frontmatter も変えない）。正本は `vault/designs/D-015.md` の「フェーズ5 文書を守りを絞った後の姿に揃える」と冒頭の「決定事項」表。前提のフェーズ1〜4 は done でマージ済み（#136・#137・#139・#141）。

## 分割方針
- 同じファイルを2つのタスクで変えない。1ファイル（または小さい文書のまとまり）ごとに1タスクにする
  - T-01：`docs/runbook.md`（人の仕事・困ったときの git 復旧・権限モードの選び方・unblock とルールの記述）
  - T-02：`docs/vault-spec.md`（2節の unblock の記述・11節の `vault/rules/` と差分ゲート・12節のやめた判定の書き方）
  - T-03：`docs/install.md`（サンドボックスの節の古い理由・人の仕事）
  - T-04：`docs/decisions.md`（判断の1行）と `docs/vision.md`（「承認」を外す）
  - T-05：`.claude/agents/planner.md`（ゴールの範囲の指針・下書きファイル方式・ガードの項目・サンドボックスの記述）
  - T-06：`.claude/agents/creator.md`・`.claude/ai-harness.md`・`README.md` と、リポジトリ全体の古い語の確認
- T-01〜T-05 は互いに依存しない（並行して取れる）。T-06 は全部の後にし、D-015 の候補どおりリポジトリ全体の `git grep` を受け入れ基準に入れる（ここで全タスクが合流する）
- 計画開始時点の `git grep`（除外：`vault/designs`・`vault/log`・`vault/archive`・`vault/plans`・`vault/tasks`・`vault/verdicts`・`scripts/smoke.sh`）で、古い語（`/plan approve`・`excludedCommands`・`提案ファイル`・`会話記録で確認`）が残っていたのは `.claude/agents/creator.md`・`.claude/agents/planner.md`・`.claude/ai-harness.md`・`README.md`・`docs/runbook.md`・`docs/vault-spec.md` の6ファイルだけで、どれも対象10ファイルに入っている。対象外のファイルに足すものは無い
- 計画の調査で分かった実際の状態：`scripts/diff_gate.py` は今も `vault/plans/`・`vault/log/`・`vault/verdicts/`・`vault/rules/` 配下の変更を宣言があっても違反にする（D-015「今回やらないこと」で差分ゲートは見直さない）。フックは `vault/rules/` を止めないが、creator のタスクの成果物にはできない。各タスクの文書はこの状態を書く
- `vault/rules/README.md` は上の理由で creator のタスクの成果物にできない（宣言しても差分ゲートで差し戻される）ので、どのタスクにも入れていない。扱いは「人への質問」の1

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | runbook.md の人の仕事・困ったときの git 復旧・権限モードの選び方・unblock とルールの記述を今の状態に揃える | |
| T-02 | doing | 1 | - | vault-spec.md の unblock の記述・vault/rules と差分ゲート・やめた判定の書き方を揃える | |
| T-03 | doing | 1 | - | install.md のサンドボックスの節の古い理由と人の仕事を揃える | |
| T-04 | todo | 0 | - | decisions.md に守りを絞った判断を1行足し、vision.md から承認を外す | |
| T-05 | todo | 0 | - | planner.md にゴールの範囲の指針を足し、下書きファイル方式・ガード・サンドボックスの古い記述を消す | |
| T-06 | todo | 0 | T-01,T-02,T-03,T-04,T-05 | creator.md・ai-harness.md・README.md を揃え、リポジトリ全体に古い語が残っていないことを確かめる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 範囲外（次の計画の候補。票は起こさない）
- 計画の調査で、対象10ファイルの外にも守りを絞る前の記述が見つかった。どれも古い語4つは含まず、ゴールの対象一覧に無いので変えない
  - `.claude/skills/run/SKILL.md` の注意（「タスク中は `vault/rules/` を編集しない（…フックでも拒否される）」）：今フックは止めず、差分ゲートが止める
  - `scripts/archive_plans.sh` の冒頭のコメント（「creator は vault/plans/・vault/log/ に書き込めず」）：コードのコメントで、このフェーズは文書だけ
  - `docs/decisions.md` の過去の行（2026-09-17 の書き込み先制限・Bash の書き込み判定など）：判断の記録なので書き換えない（T-04 の決定済み）
- 差分ゲートの `vault/rules/` の扱いと、D-015 の「エージェントも `vault/rules/` に書ける」の食い違いの整理（D-015 は差分ゲートを見直さない）

## 人への質問（回答済み）
1. `vault/rules/README.md` の直し方：`scripts/diff_gate.py` が `vault/rules/` 配下の変更を宣言があっても違反にするため、creator のタスクではこのファイルを変えられません（宣言すると review への遷移で必ず差し戻されます）。どれにしますか。
   - (a)（この計画の既定）この計画のタスクでは変えない。PR のマージ前に人がこのブランチの上で20行目を直す。直す文案：「エージェントのフックは `vault/rules/` への書き込みを止めない。ただし creator のタスクの成果物にはできない（差分ゲート `scripts/diff_gate.py` が `vault/rules/` 配下の変更を宣言があっても違反にする）。ルールの追加・変更はタスクにせず、人が編集する。変更は PR の差分で見える。」T-06 の2つ目の `git grep` からは、理由を書いて `vault/rules/README.md` を除外している（古い語4つはこのファイルに無いので、1つ目の確認には影響しない）
   - (b) 全タスクが done になった後、PR を作る前にオーケストレーターが上の文案で直接直してコミットする（オーケストレーターは成果物を作らない約束の例外になる）
   - (c) 差分ゲートを変えて `vault/rules/` を宣言すれば許すようにする（コードの変更なので、このフェーズの範囲外。別の計画にする）
   - 回答：(a)。この計画のタスクでは `vault/rules/README.md` を変えず、PR のマージ前に人がこのブランチの上で上の文案で直す
