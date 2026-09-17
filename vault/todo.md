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

## 計画
| id | status | title |
|---|---|---|
| P-001 | approved | 初期構築 |
| P-002 | approved | verdict.json に検証の根拠を残す |
| P-003 | approved | planner が満たせない受け入れ基準を書かないようにする |
