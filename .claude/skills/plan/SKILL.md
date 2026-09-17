---
name: plan
description: ゴールをタスクに分割して計画を作る。「計画を立てて」「タスクに分割して」「これをやりたい」「plan」と言われたら必ずこのスキルを使う。planner サブエージェントで draft を作り、人の承認後に approved にして vault/todo.md に登録する。「計画を承認」「P-001 を承認」もこのスキル。
argument-hint: [ゴール | approve P-xxx]
---

ゴールを計画（`vault/plans/P-xxx.md`）とタスク票（`vault/tasks/T-xxxx.md`）に分割し、人の承認を経て `vault/todo.md` に登録する。仕様は `docs/vault-spec.md`。

引数：`$ARGUMENTS`

## A. 計画を作る（引数がゴールの時）
1. Agent ツールで `planner` サブエージェントを呼ぶ。prompt にはゴールと、関係するファイルのパスがあればそれを渡す
2. 生成された `vault/plans/P-xxx.md` と各タスク票を読み、粒度基準（受け入れ基準3〜7行、成果物1つ、依存に循環なし）を満たしているか確認する。満たしていなければ planner に修正を依頼する
3. 人に提示する：計画 ID、タスクの一覧（ID / title / after / 受け入れ基準の要約）、planner からの質問
4. 「承認するなら `/plan approve P-xxx`、直すなら指示をください」と伝えて**止まる**。承認前に todo.md へ登録しない

## B. 承認して登録する（引数が `approve P-xxx`、または人が承認を伝えた時）
1. `vault/plans/P-xxx.md` の frontmatter `status` を `approved` にする
2. 計画票の「タスク一覧」の順序で、`vault/todo.md` の「## タスク」表の末尾に行を追加する：`| T-xxxx | todo | 0 | <after または -> | <title> | |`
3. 「## 計画」表に `| P-xxx | approved | <title> |` を追加する
4. `vault/log/queue.md` に `- <日時> P-xxx draft→approved tasks=T-xxxx,T-xxxx` を追記する（日時は `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'`）
5. 登録した行を報告し、「`/run-queue` で処理を開始できます」と伝える

## 注意
- 計画の修正指示を受けたら planner を再度呼ぶか自分で計画票・タスク票を直し、再提示する
- 既存の todo / done と重複するタスクを作らない
