作業は「作成 → 検証」の二段構成。検証（verifier）が PASS しない限り完了できない。状態はすべて
`vault/` のファイルにあり、仕様の正本は `docs/vault-spec.md`。1セッション=1計画=1ブランチで、計画
の作成から実行までを1本のブランチに閉じる。

## 開始時に読む順
1. `vault/plans/*.md` を走査し、frontmatter の `status` が `approved` の計画票を1つ見つける
2. その計画票の「タスク表」を読む。`doing` の行があれば `vault/tasks/<計画ID>/<id>.md` の「進捗」から再開する
3. 無ければ `todo` の先頭（`after` が全部 `done` のもの）を取る
4. 「次は何をやる？」と聞かれたら、承認済み計画票のタスク表を読んで先頭タスクの ID と title を答える

## 状態遷移（5つで固定）
`todo → doing → review → (done | doing[attempt+1] | blocked)`。`blocked → todo` は人だけ。
- `doing` は計画内で常に1件だけ。2件目を取らない
- `done` にできるのは `vault/verdicts/<計画ID>/<id>.json` が PASS で、`attempt` が計画票のタスク表と一致する時だけ
- 状態を変えたら `vault/log/<計画ID>.md` に1行追記する（`- YYYY-MM-DD HH:MM T-01 doing→review attempt=1 補足`）
- 日時は JST：`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'`

## 質問のしかた
- 着手前にまとめて出す。着手後は質問せず、判断が必要になったら `blocked` にして question 列に書く
- タスク票の「決定済み」にある回答を優先する。勝手に決めない、勝手に広げない

## 役割
- 作成エージェント（メイン）：タスクを取り、着手時に `bash scripts/rules.sh creator` の列挙を読み、成果物を作り、状態と log を更新する
- `verifier` は `vault/verdicts/`、`planner` は `vault/plans/`・`vault/tasks/` にだけ書く（詳細は `vault/rules/common/roles.md`）

## スキル
`/plan <ゴール>`（計画を draft で作りブランチを切る。`/plan approve <計画ID>` で承認）・`/run`（自分のブランチの承認済み計画を1タスク処理する）・`/design <ゴール>`（大きなゴールを設計文書にする）

## 禁止
- `done` のタスク票・verdict を編集すること
- `rm -rf`、`git push --force` などの破壊的操作（settings.json で拒否）
- 計画票のタスク表の列順・見出し名を変えること（フックが表を解析する）
