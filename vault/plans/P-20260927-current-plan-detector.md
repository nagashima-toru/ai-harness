---
id: P-20260927-current-plan-detector
status: approved
---
# ゴール
`vault/plans/*.md` のうち frontmatter（ファイル先頭の `---` から次の `---` まで）の `status` が `approved` の計画票の計画 ID を1行1件で出力する `scripts/current_plan.sh` を新規作成する。本文中に `status: approved` という文字列があっても検出しない。`.claude/skills/run/SKILL.md` の手順1を、このスクリプトの出力行数（0件／1件／2件以上）で判定する手順に書き換える。`docs/vault-spec.md` 1節の「自分のブランチの計画票」の説明に、このスクリプトを使うことを追記する。`scripts/smoke.sh` にこのスクリプトのテストを足す（issue #72、`vault/designs/D-010.md` フェーズ1）。

## 分割方針
- T-01（`scripts/current_plan.sh` 本体）を先に切る。frontmatter 解析・id フォールバック・出力形式（1行1件、ファイル名順）を1つのスクリプトとして確定させる。他の3タスクはこの出力仕様に依存するため、T-01 の完了後に着手する
- T-02（`scripts/smoke.sh` へのテスト追加）・T-03（`.claude/skills/run/SKILL.md` 手順1の書き換え）・T-04（`docs/vault-spec.md` 1節への追記）は、いずれも T-01 のみに `after` で依存し、互いには依存しない。成果物がそれぞれ別の1ファイルなので並行して着手できる（着手可能集合）
- 4タスクとも成果物が1ファイルに特定でき、粒度基準（1計画5〜7タスク以内）に収まる

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | current_plan.sh で承認済み計画票を検出するスクリプトを作る | |
| T-02 | todo | 0 | T-01 | smoke.sh に current_plan.sh のテストを追加する | |
| T-03 | todo | 0 | T-01 | run スキルの手順1を current_plan.sh 判定に書き換える | |
| T-04 | todo | 0 | T-01 | vault-spec.md 1節に current_plan.sh の利用を追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
