---
id: P-20260926-progress-exclusion-criteria
status: approved
---
# ゴール

`vault/rules/planner/planner.md` に、「成果物以外の変更が無いこと」を確認する受け入れ基準を書く場合の恒久的な指針を追記する提案をまとめる（issue #51）。

`P-20260925-sandbox-hang-timeout`/T-01 で、受け入れ基準「成果物は `T-01-proposal.md` のみで、他ファイルは変更していない」の確認コマンド（`git status --porcelain | grep -v 'T-01-proposal.md'`）が attempt=1〜3 の3回とも文字通りFAILした。原因は creator が doing 中にタスク票自身の「進捗」節へ追記するため、その差分が常に非空として残ること（`docs/vault-spec.md` 5節）。その場は人の判断でタスク票自身のパスも除外する形に確認コマンドを直して解決したが、対症療法であり同種のタスクで再発する。

issue #51 の「提案」節にある次の2案のどちらを採用するか（あるいは両方併記するか）は planner（このタスクの creator）の判断に委ねられている。
- (A) 「成果物以外の変更が無いこと」を確認する受け入れ基準を書く場合、確認コマンドの除外パスに成果物だけでなくタスク票自身のパス（`vault/tasks/<計画ID>/<id>.md`）も含めるよう明記する
- (B) このパターンの受け入れ基準自体を書かず、verifier 組み込みの起点コミットベースの検査（`vault/rules/verifier/verifier.md` の該当項目。creator が「進捗」に `起点コミット: <hash>` を記録する運用とセット）に委ねることを推奨する

`vault/rules/` 配下の変更のため、反映は提案ファイル方式（`docs/vault-spec.md` 12節）でタスク化し、実体（`vault/rules/planner/planner.md`）への反映は人が手作業で行う。

## 分割方針

対象は1ファイル（`vault/rules/planner/planner.md`）への1件の追記案のみで、成果物は単一の提案ファイルに収まる。`P-20260925-acceptance-test-sandbox-fp`/T-03、`P-20260925-sandbox-hang-timeout`/T-01 と同じ「提案ファイルを書く」単一タスクの粒度に合わせ、1タスクで完結させる。分割の余地（契約タスクと実装タスクの分離など）は無い。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | planner.md に「成果物以外の変更が無いこと」の恒久指針を追記する提案を書く（issue #51） | |

## 計画の受け入れ基準
- タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（`after` は `-` のみ）
- 1タスクが1コンテキストで終わる粒度である
