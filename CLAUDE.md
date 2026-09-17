# AI協働ハーネス 共通ルール

作業は「作成 → 検証」の二段構成。検証（verifier）が PASS しない限り完了できない。
状態はすべて `vault/` のファイルにある。詳細な仕様は `docs/vault-spec.md` を正本とする。

## 開始時に読む順
1. `vault/todo.md`
2. `doing` の行があれば `vault/tasks/<id>.md` の「進捗」から再開する
3. 無ければ `todo` の先頭（`after` が全部 `done` のもの）を取る
4. 「次は何をやる？」と聞かれたら、todo.md を読んで先頭タスクの ID と title を答える

## 状態遷移（5つで固定）
`todo → doing → review → (done | doing[attempt+1] | blocked)`。`blocked → todo` は人だけ。

- `doing` は常に1件だけ。2件目を取らない
- `done` にできるのは `vault/verdicts/<id>.json` が PASS で、`attempt` が todo.md と一致する時だけ
- 状態を変えたら `vault/log/queue.md` に1行追記する（`- YYYY-MM-DD HH:MM T-0001 doing→review attempt=1 補足`）
- 日時は JST：`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'`

## 質問のしかた
- 着手前にまとめて出す。着手後は質問せず、判断が必要になったら `blocked` にして question 列に書く
- タスク票の「決定済み」にある回答を優先する。勝手に決めない、勝手に広げない

## 役割
- 作成エージェント（メイン）：タスクを取り、成果物を作り、状態と log を更新する
- `verifier`：受け入れ基準を照合し verdict を書く。`vault/verdicts/` 以外に書かない
- `planner`：ゴールをタスクに分割し draft を書く。`vault/plans/`・`vault/tasks/` 以外に書かない

## スキル
- `/run-queue`：キューを1件処理する（「続きから」「次のタスクをやって」）
- `/plan <ゴール>`：計画を draft で作る。`/plan approve P-xxx` で承認して todo.md に登録する

## フック
- Stop：`.claude/hooks/stop_gate.py` が todo.md と verdict を照合し、整合しない終了をブロックする（判定のみ、状態は書き換えない）
- PreToolUse：`.claude/hooks/agent_write_guard.py` が verifier / planner の書き込み先を制限する
- PostToolUse：`.claude/hooks/todo_guard.py` が todo.md の整合性（doing の重複・blocked の question 空・status 不正・id 重複・列数不正）を検査する

## 禁止
- `done` のタスク票・verdict を編集すること
- `rm -rf`、`git push --force` などの破壊的操作（settings.json で拒否）
- todo.md の列順・見出し名を変えること（フックが表を解析する）
