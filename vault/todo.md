# キュー

## ルール
- todo の一番上から1件だけ doing にする。doing は常に1件
- done にできるのは verdicts/<id>.json が PASS の時だけ
- 迷ったら blocked にして question を書く。勝手に決めない
- 状態を変えたら log/queue.md に1行追記する

## タスク
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-0001 | done | 1 | - | ハーネスの動作確認（README の使い方節に1行追記） | |
| T-0002 | done | 1 | - | verdict.json の note 要件を仕様と verifier プロンプトに追記 | |
| T-0003 | done | 1 | - | planner に「run-queue で必ず変わるファイルの差分不変を受け入れ基準にしない」ルールを追記 | |
| T-0004 | done | 1 | - | stop_gate.py に verdict 形式検証を追加し smoke.sh と vault-spec.md を更新 | |
| T-0005 | done | 1 | - | todo_guard フックで todo.md の整合性を PostToolUse でチェックする | |
| T-0006 | done | 1 | - | vault-spec.md に「ルール（vault/rules/）」節を追加し置き場を作る | |
| T-0007 | done | 1 | - | scripts/rules.sh を新規作成し smoke.sh にケースを追加する | |
| T-0008 | done | 1 | - | run-queue にルール読み込み手順を追加する | |
| T-0009 | done | 1 | - | verifier にルール読み込みと参照時の判定手順を追加する | |
| T-0010 | done | 1 | - | planner.md にルール読み込み手順を追加し vault-spec.md の粒度基準を更新する | |
| T-0011 | done | 1 | - | agent_write_guard.py に doing/review 中の vault/rules/ 書き込み拒否を追加する | |

## 計画
| id | status | title |
|---|---|---|
| P-001 | approved | 初期構築 |
| P-002 | approved | verdict.json に検証の根拠を残す |
| P-003 | approved | planner が満たせない受け入れ基準を書かないようにする |
| P-004 | approved | stop_gate で verdict の形式を検証する |
| P-005 | approved | todo.md の整合性チェックをフック化する |
| P-006 | approved | vault/rules/ の仕様と置き場を決める |
| P-007 | approved | ルール解決スクリプト scripts/rules.sh を作る |
| P-008 | approved | run-queue にルール読み込みを追加する |
| P-009 | approved | verifier にルール読み込みを追加する |
| P-010 | approved | planner にルール読み込みを追加する |
| P-011 | approved | 改ざん防止フック（agent_write_guard.py 拡張） |
