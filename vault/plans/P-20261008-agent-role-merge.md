---
id: P-20261008-agent-role-merge
status: draft
---
# ゴール
標準の役割定義6本をエージェント定義に統合し、`vault/rules/` を導入先のルール専用にする（D-013 フェーズ4）

`vault/rules/` にある標準の役割定義6本（`vault/rules/common/roles.md`・`vault/rules/common/git.md`・`vault/rules/creator/creator.md`・`vault/rules/creator/git-workflow.md`・`vault/rules/verifier/verifier.md`・`vault/rules/planner/planner.md`）の内容を `.claude/agents/creator.md`・`.claude/agents/verifier.md`・`.claude/agents/planner.md` に統合する。`scripts/install.sh` は6本を配らなくし、`--update` では既存のマニフェストのハッシュで未編集と判定したものだけを削除し、編集済みのものは残して `note` で案内する。`scripts/uninstall.sh` も合わせる。`docs/vault-spec.md` 11節と `README.md` の拡張ポイントの節を「ハーネスは標準ルールを同梱しない。役割定義は `.claude/agents/` にある」の形にし、`vault/rules/README.md` の書き換え案を提案ファイルにする。

正本は `vault/designs/D-013.md` の「フェーズ4 標準の役割定義をエージェント定義に統合する」（ゴール文・受け入れ基準の候補・決定済み・依存）。`vault/rules/planner/ai-harness-lessons.md` と `scripts/rules.sh` は変えない。

## 分割方針
- エージェント定義ごとに1タスクにする（成果物を1つに保つ）。3本は別ファイルなので並行してよい
  - T-01：`.claude/agents/creator.md` ← `roles.md` の creator が関わる節・`git.md`・`creator/creator.md`・`creator/git-workflow.md`
  - T-02：`.claude/agents/verifier.md` ← `verifier/verifier.md`・`roles.md` の verifier が関わる節・`git.md` の verifier に関係する部分
  - T-03：`.claude/agents/planner.md` ← `planner/planner.md`・`roles.md` の planner が関わる節・`git.md` の planner に関係する部分
- T-04：`scripts/install.sh`（主）・`scripts/uninstall.sh`・`scripts/smoke.sh`。エージェント定義とは独立なので T-01〜T-03 と並行してよい。`scripts/smoke.sh` を変えるのはこのタスクだけ
- T-05：`docs/vault-spec.md` 11節（主）と `README.md` の拡張ポイントの節。T-01〜T-04 の後（統合先と install.sh の新しい動きを書くため）
- T-06：`vault/rules/README.md` の書き換え案を `vault/tasks/P-20261008-agent-role-merge/T-06-proposal.md` に書く。T-05 の後（文言を揃えるため）
- 各タスクは単体でマージしても smoke が `fail=0` で通る。6本が `vault/rules/` に残っている間も、人が削除した後も通るようにする（smoke は `$ROOT/vault/rules/` の6本を読まない）
- smoke の件数は計画作成時点で `smoke: pass=681 fail=0`。受け入れ基準は件数ではなく `fail=0` とケース名で見る
- 統合で落とした記述・言い換えた記述は、各タスク票の「進捗」に「落とした記述:」「言い換えた記述:」の行で列挙する（PR 本文に載せるため）。受け入れ基準には入れない（verifier は「進捗」を根拠にしない）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | 標準ルールの creator 向けの内容を .claude/agents/creator.md に統合する | |
| T-02 | todo | 0 | - | 標準ルールの verifier 向けの内容を .claude/agents/verifier.md に統合する | |
| T-03 | todo | 0 | - | 標準ルールの planner 向けの内容を .claude/agents/planner.md に統合する | |
| T-04 | todo | 0 | - | install.sh が標準ルール6本を配らず、--update で未編集のものを削除する | |
| T-05 | todo | 0 | T-01,T-02,T-03,T-04 | docs/vault-spec.md 11節と README.md の拡張ポイントを「標準ルールを同梱しない」形にする | |
| T-06 | todo | 0 | T-05 | vault/rules/README.md の書き換え案を提案ファイルに書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む
- `vault/rules/` は変わっていない（`git status --porcelain -- vault/rules` が空。6本の削除と README.md への反映は人が行う）

## 人が行う作業（PR のマージ前に同じブランチで）
- T-06 の提案ファイルの「人が行う作業」節に従い、6本を `git rm` し、提案の全文を `vault/rules/README.md` に反映してコミットする（エージェントは `vault/rules/` に書けないため、タスクにも成果物にも入れない）
- 反映後に `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` を含むことを確かめる

## 次フェーズの候補（票は起こさない）
- 6本の削除後に参照切れになる、11節・拡張ポイントの節の外の記述の修正（下の「人への質問」1を参照）。D-013 フェーズ7（参照切れの検査）と合わせて扱うのが自然

## 人への質問
1. 6本への参照は、このゴールの対象（`docs/vault-spec.md` 11節・`README.md` の拡張ポイントの節）の外にも残っている。今回の計画では変えず、D-013 フェーズ7で直す前提にしてよいか。残る箇所：
   - `.claude/ai-harness.md` 24行目（`vault/rules/common/roles.md` への参照。フェーズ7の対象ファイル）
   - `.claude/skills/run/SKILL.md` 70行目・116行目（`roles.md`・`git.md` への参照）、145行目（`vault/rules/creator/`・`vault/rules/verifier/` を変えない、の記述）
   - `docs/vault-spec.md` 167行目（6節。「`vault/rules/verifier/verifier.md` を根拠とする」）
   - `docs/install.md` 34行目（「標準ルール」を複製する）・92行目（「標準ルール4本など」）・174行目（「標準4本以外の `vault/rules/`」）。T-04 で install.sh の動きが変わるため、マージ時点で記述が古くなる
   - `docs/third-party-notices.md` 47〜55行目（6本の一覧）
2. `vault/rules/planner/ai-harness-lessons.md` は `vault/rules/planner/planner.md` の「やらないこと」を指している（2〜3行目・36〜37行目）。6本の削除後は `.claude/agents/planner.md` の「## やらないこと」節を指すように人が直すか（ゴールではこのファイルを変えないことになっているので、計画には入れていない。T-03 では見出し「## やらないこと」を残す）
