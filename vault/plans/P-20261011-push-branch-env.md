---
id: P-20261011-push-branch-env
status: done
---
# ゴール
環境変数 `HARNESS_PUSH_BRANCH`（前後の空白を除いて空なら未設定）が設定されている時、`scripts/vcs_finish.sh` は GitHub・GitLab の経路で毎回 `git push -u origin HEAD:<値>` で push し、PR/MR の head（source branch）にその値を使う。`/plan`・`/design` の開始条件に「`HARNESS_PUSH_BRANCH` が設定され、現在のブランチがその値で、HEAD がローカルのベースブランチと同じコミットなら、ベース上とみなしてブランチを切る」を足す。`run`・`design` の MCP 代替時の head、`docs/` の説明（クラウドセッションでの使い方を含む）と `scripts/smoke.sh` のケースもそろえる。最後に決定事項を `docs/decisions.md` に取り出し、この設計文書（`vault/designs/D-20261010-base-branch-config.md`）を削除する（設計文書のフェーズ2。最終フェーズ）。

## 分割方針
- T-01 は `scripts/vcs_finish.sh` の実装と、それを確かめる `scripts/smoke.sh` のケースを1タスクにまとめる（スクリプトの動作は smoke のケースでしか機械的に確かめられないため。smoke のケースは vcs_finish.sh だけを検査する）
- T-02（スキル3本）・T-03（docs の2本）は文書だけで、T-01 と成果物が重ならないので並列に走れる
- T-04 は決定事項の取り出しと設計文書の削除。設計文書を読む T-01〜T-03 の後に置く
- `docs/install.md` は変えない（`HARNESS_PUSH_BRANCH` はセッションごとに値が変わる前提で、導入時の恒久設定の手順には入れない。T-03 の決定済み）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | vcs_finish.sh に HARNESS_PUSH_BRANCH の push と head を足し smoke のケースを足す | |
| T-02 | done | 1 | - | plan・design・run の SKILL.md に開始条件と MCP 代替時の head を足す | |
| T-03 | done | 1 | - | vault-spec.md と runbook.md に HARNESS_PUSH_BRANCH の説明を足す | |
| T-04 | done | 1 | T-01,T-02,T-03 | 決定事項を decisions.md に取り出し設計文書を削除する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
