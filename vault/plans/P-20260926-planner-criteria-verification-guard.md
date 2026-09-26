---
id: P-20260926-planner-criteria-verification-guard
status: approved
---
# ゴール

`vault/rules/planner/planner.md` に、「コード変更を伴う受け入れ基準では、`grep` 等による単語の出現有無・出現回数だけを唯一の確認コマンドにせず、実際の入出力・実行結果を確認するコマンドを併記する」という指針を追記する提案をまとめる（issue #68）。

`P-20260926-fix-smoke-sh-failures` の run 実行中、verifier が T-03・T-04 それぞれの受け入れ基準1（`grep -n "worktrees" <file>` の出力が1行以上）について「語の出現回数のみを見る緩い基準で、単独では実際の除外動作を保証しない」と指摘しつつ、直後の基準（実際の実行結果で目的達成を確認するもの）で PASS 判定した。今回は後続の基準が機能検証を兼ねていたため実害はなかったが、grep 存在チェックだけを唯一の受け入れ基準として書いてしまうケースがあると、文字列が意図しない場所（コメント・別の条件分岐等）に追加されただけでも PASS してしまう可能性がある。

- 該当箇所: `vault/tasks/P-20260926-fix-smoke-sh-failures/T-03.md` の受け入れ基準1、`vault/tasks/P-20260926-fix-smoke-sh-failures/T-04.md` の受け入れ基準1
- 根拠: `vault/verdicts/P-20260926-fix-smoke-sh-failures/T-03.json`・`T-04.json` の reasons（verifier の指摘そのもの）

`vault/rules/` 配下の変更のため、反映は提案ファイル方式（`docs/vault-spec.md` 12節）でタスク化し、実体（`vault/rules/planner/planner.md`）への反映は人が手作業で行う。

スコープは issue #68 が提案している範囲（`planner.md` へのガイドライン追記）に留める。verifier 側のルール変更など、関連する別の改善へは広げない。

## 分割方針

対象は1ファイル（`vault/rules/planner/planner.md`）への1件の追記案のみで、成果物は単一の提案ファイルに収まる。`P-20260926-progress-exclusion-criteria`/T-01、`P-20260925-acceptance-test-sandbox-fp`/T-03 と同じ「提案ファイルを書く」単一タスクの粒度に合わせ、1タスクで完結させる。契約タスクと実装タスクを分ける必要のある開発案件ではないため、分割の余地は無い。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | planner.md に「grepの単語出現チェック単独禁止」の恒久指針を追記する提案を書く（issue #68） | |

## 計画の受け入れ基準
- タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（`after` は `-` のみ）
- 1タスクが1コンテキストで終わる粒度である
