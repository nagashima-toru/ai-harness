---
name: plan
description: ゴールをタスクに分割して計画を作る。「計画を立てて」「タスクに分割して」「これをやりたい」「plan」と言われたら必ずこのスキルを使う。計画 ID とブランチを決め、planner サブエージェントで draft を作り、人が `/plan approve <計画ID>` のコマンドで承認した後に計画票の status を approved にする。「計画を承認」「P-20260919-git-ops を承認」もこのスキル（自然文の場合は `/plan approve <計画ID>` を打つよう案内する）。blocked になったタスクの解除（unblock）にも使う。「blocked を解除」「T-02 の blocked を戻して」と言われたらこのスキルを使い、人が `/plan unblock <計画ID> <id> [回答]` のコマンドを打つよう案内する。
argument-hint: [ゴール | approve <計画ID> | unblock <計画ID> <id> [回答]]
---

ゴールを計画（`vault/plans/<計画ID>.md`）とタスク票（`vault/tasks/<計画ID>/T-01.md`）に分割し、人の承認を経て計画票の `status` を `approved` にする。blocked になったタスクは、人の `/plan unblock` の指示で `todo` に戻す。仕様は `docs/vault-spec.md`。

注意：このスキルは考える工程なので、強いモデル（opus）のセッションで実行する。

引数：`$ARGUMENTS`

## A. 計画を作る（引数がゴールの時）
1. 計画 ID を決める：`P-<TZ=Asia/Tokyo date '+%Y%m%d'>-<slug>`（採番は不要）。`slug` はゴールの内容から英小文字・ハイフン区切りで人が読める形を選ぶ（迷ったら人に確認してよい）
2. 現在のブランチが `main` であることを確認する。`main` でなければブランチを切らず「`main` に戻ってから `/plan` を実行してください」と伝えて**止まる**（既存の作業ブランチに別の計画を重ねる運用は入れない）
3. `git checkout -b work/<計画IDの英小文字>` でブランチを作る
4. Agent ツールで `planner` サブエージェントを呼ぶ。prompt にはゴールと、手順1で決めた計画 ID、関係するファイルのパスがあればそれを渡す。planner はこの計画 ID をそのまま使ってファイルを書く。この Agent ツール呼び出しは `run_in_background: false` を指定し、同期的に完了を待つこと（手順5以降で生成物を読んで判定するため、結果に依存する）
5. 生成された `vault/plans/<計画ID>.md` と各タスク票を読み、粒度基準（受け入れ基準3〜7行、成果物1つ、依存に循環なし）を満たしているか確認する。満たしていなければ planner に修正を依頼する
6. 人に提示する：計画 ID、タスクの一覧（ID / title / after / 受け入れ基準の要約）、planner からの質問
7. 「承認するなら `/plan approve <計画ID>`、直すなら指示をください」と伝えて**止まる**。承認前に `status` を変えない

## B. 承認する（引数が `approve <計画ID>` のコマンドの時）
1. 承認の指示が `/plan approve <計画ID>` のコマンドで来たことを確認する。人が自然文で承認を伝えた場合（引数が `approve <計画ID>` の形でない場合）は承認せず、「`/plan approve <計画ID>` を打ってください」と案内して**止まる**
2. `vault/plans/<計画ID>.md` の frontmatter `status` が `draft` であることを確認する。`draft` でなければ承認せず状況を伝えて止まる
3. frontmatter `status` を `approved` にする
4. `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'` で日時を取り、`vault/log/<計画ID>.md` に次の1行を追記する（ファイルが無ければ作る）：`- <日時> - draft→approved 人の指示: /plan approve <計画ID>`
5. `git add vault/plans/<計画ID>.md vault/log/<計画ID>.md` でファイルを名前で指定して stage し、`git commit`（メッセージ例：`<計画ID>: 計画を承認する`）する。work ブランチ上で行う。`git add .` や `git add -A` は使わない
6. 承認したことを報告し、「`/run` で処理を開始できます」と伝える

## C. blocked を解除する（引数が `unblock <計画ID> <id> [回答]` のコマンドの時）
1. 解除の指示が `/plan unblock <計画ID> <id> [回答]` のコマンドで来たことを確認する。人が自然文で解除を伝えた場合（引数が `unblock <計画ID> <id>` の形でない場合）は解除せず、「`/plan unblock <計画ID> <id> [回答]` を打ってください」と案内して**止まる**
2. `vault/plans/<計画ID>.md` のタスク表で、`<id>` の行の status が `blocked` であることを確認する。`blocked` でなければ解除せず状況を伝えて止まる
3. 回答があれば、タスク票 `vault/tasks/<計画ID>/<id>.md` の「決定済み」に回答を追記する。回答が無い時は何も追記しない（ハングやマージコンフリクトなど、答える質問が無い blocked）。回答の内容で受け入れ基準を直す必要がある時は、回答に基づく追記までにとどめ、大きな書き換えは planner を呼ぶよう案内する
4. 計画票の `<id>` の行の status を `todo`、attempt を `0`、question を空にする
5. `TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'` で日時を取り、`vault/log/<計画ID>.md` に次の1行を追記する：`- <日時> <id> blocked→todo 人の指示: /plan unblock <計画ID> <id>`
6. `git add vault/plans/<計画ID>.md vault/tasks/<計画ID>/<id>.md vault/log/<計画ID>.md` でファイルを名前で指定して stage し、`git commit`（メッセージ例：`<計画ID>: <id> の blocked を解除する`）する。回答が無く、タスク票を変えなかった時は、タスク票を add に含めない。work ブランチ上で行う。`git add .` や `git add -A` は使わない
7. 解除したことを報告し、「`/run` で再開できます」と伝える

1回のコマンドで解除するのは1行だけ。複数行を解除する時は、人がコマンドを行の数だけ打つ。

## 注意
- 計画の修正指示を受けたら planner を再度呼ぶか自分で計画票・タスク票を直し、再提示する
- 同じブランチに複数の計画を重ねない（1ブランチ1計画。`plan_guard.py` が approved 2件以上を検出する）
- 既存の done と重複するタスクを作らない
