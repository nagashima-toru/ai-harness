---
id: P-20261001-generic-rules
status: approved
---
# ゴール

D-010 フェーズ10（issue #80）：導入先に配る標準ルール・エージェント定義・仕様を、ハーネスの仕組みに関わる汎用の規律だけに絞る。`vault/rules/` の実体はフックが書き込みを拒否するので、ルールの変更は提案ファイル（`vault/tasks/<計画ID>/<id>-proposal.md`）として全文で書き、実体への反映は人が行う。提案は3つ作る。(1) 汎用化した `vault/rules/planner/planner.md`：契約タスクの項と、固有の経緯（T-xxxx・計画 ID・issue 番号）を外す。(2) 新規 `vault/rules/planner/ai-harness-lessons.md`：(1) で外した経緯を移す。配布しない。(3) 現在の run の役割分担に合わせた `vault/rules/creator/git-workflow.md`。実体を直接変更するのは次の3つ。`.claude/agents/planner.md` と `docs/vault-spec.md` 8節から「開発案件では契約タスクを先に切る」を外し、README の「拡張ポイント（ルール）」節に導入先で積む拡張の例として移す。`.claude/settings.json` の allow から `npm test*`・`npm run *`・`npx *`・`pytest *`・`make *` を外す。

PR 本文用：`Closes #80`

## 分割方針
- 提案3つ（planner.md 汎用版＝T-01、ai-harness-lessons.md＝T-02、git-workflow.md 改訂版＝T-03）は、成果物を1つにする原則に従って1タスク1ファイルにする。いずれも現行の `vault/rules/` 実体を読んで書くので、互いに依存させず並行可能にする
- 実体を変える `.claude/agents/planner.md`＋`docs/vault-spec.md`＋README（T-04）と、`.claude/settings.json`（T-05）はそれぞれ別タスクにする。T-01〜T-05 は書き込むファイルがすべて別なので並行可能
- `bash scripts/smoke.sh` の `fail=0` の確認は T-06 に切り出し、T-01〜T-05 の後に単独で動かす（smoke.sh が /tmp の固定パスを使うため、並行実行で偽の fail が出るのを避ける）。T-01〜T-05 の受け入れ基準に smoke は含めない

### 決定済み（設計文書 D-010 フェーズ10 から引き継ぎ。各タスク票にも写す）
- 固有の経緯を移すファイル名は `vault/rules/planner/ai-harness-lessons.md`（人の回答）。`install.sh` の標準ルールの列挙には加えない（配布しないため）
- 失敗例の本文は、汎用の教訓として planner.md 汎用版に残す（例：「複合コマンドを確認コマンドにしない」）。T-xxxx・計画 ID・issue 番号と、その経緯の説明だけを ai-harness-lessons.md に移す
- 提案ファイルは全文で書く（差分ではなく）。人がそのまま実体へコピーできるようにする
- 提案ファイルは、成果物を1つにする原則に従って、1タスク1ファイルとする
- 実体への反映は人が行う。この計画の受け入れ基準では、実体（`vault/rules/` 配下）が変わったことを検査しない
- `docs/decisions.md`・過去の設計文書・過去の計画票にある経緯の記述は変更しない
- 既存の導入先の allow は `merge_settings_json.py` が変更しないので、allow から外しても導入先に影響しない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | planner.md 汎用版の提案を書く | |
| T-02 | done | 1 | - | ai-harness-lessons.md の提案を書く | |
| T-03 | done | 1 | - | git-workflow.md 改訂版の提案を書く | |
| T-04 | todo | 0 | - | 契約タスクの記述を agents/planner.md・vault-spec.md から README の拡張例へ移す | |
| T-05 | todo | 0 | - | settings.json の allow から npm・npx・pytest・make を外す | |
| T-06 | todo | 0 | T-01,T-02,T-03,T-04,T-05 | smoke を通し配布対象に lessons が無いことを確認する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- `vault/rules/common/git.md` の「コミットは作業ステップごとに小さく分けて行う」「全タスクが done になったら gh pr create までを行う」は主語が書かれておらず、creator にも渡る。T-03 の git-workflow.md 改訂版（creator はコミットを受け入れ基準にある時だけ行う、PR はオーケストレーターが作る）と読み合わせた時の整合は、今回の計画では扱わない（ゴール外）

## 人への質問
- （着手を止めるものではない）`.claude/skills/run/SKILL.md` は「creator 側の『コミットは受け入れ基準に含まれている場合だけ行う』方針（`vault/rules/common/git.md`）」と書いているが、`vault/rules/common/git.md` にはその記述が無い。今回は T-03 の git-workflow.md 改訂版にこの方針を書くに留め、common/git.md と run SKILL.md の参照先は直さない。common/git.md の改訂を別の計画で行うか判断してほしい
