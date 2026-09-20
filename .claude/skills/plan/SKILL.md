---
name: plan
description: ゴールをタスクに分割して計画を作る。「計画を立てて」「タスクに分割して」「これをやりたい」「plan」と言われたら必ずこのスキルを使う。計画 ID とブランチを決め、planner サブエージェントで draft を作り、人の承認後に計画票の status を approved にする。「計画を承認」「P-20260919-git-ops を承認」もこのスキル。
argument-hint: [ゴール | approve <計画ID>]
---

ゴールを計画（`vault/plans/<計画ID>.md`）とタスク票（`vault/tasks/<計画ID>/T-01.md`）に分割し、人の承認を経て計画票の `status` を `approved` にする。仕様は `docs/vault-spec.md`。

引数：`$ARGUMENTS`

## A. 計画を作る（引数がゴールの時）
1. 計画 ID を決める：`P-<TZ=Asia/Tokyo date '+%Y%m%d'>-<slug>`（採番は不要）。`slug` はゴールの内容から英小文字・ハイフン区切りで人が読める形を選ぶ（迷ったら人に確認してよい）
2. 現在のブランチが `main` であることを確認する。`main` でなければブランチを切らず「`main` に戻ってから `/plan` を実行してください」と伝えて**止まる**（既存の作業ブランチに別の計画を重ねる運用は入れない）
3. `git checkout -b work/<計画IDの英小文字>` でブランチを作る
4. Agent ツールで `planner` サブエージェントを呼ぶ。prompt にはゴールと、手順1で決めた計画 ID、関係するファイルのパスがあればそれを渡す。planner はこの計画 ID をそのまま使ってファイルを書く
5. 生成された `vault/plans/<計画ID>.md` と各タスク票を読み、粒度基準（受け入れ基準3〜7行、成果物1つ、依存に循環なし）を満たしているか確認する。満たしていなければ planner に修正を依頼する
6. 人に提示する：計画 ID、タスクの一覧（ID / title / after / 受け入れ基準の要約）、planner からの質問
7. 「承認するなら `/plan approve <計画ID>`、直すなら指示をください」と伝えて**止まる**。承認前に `status` を変えない

## B. 承認する（引数が `approve <計画ID>`、または人が承認を伝えた時）
1. `vault/plans/<計画ID>.md` の frontmatter `status` を `approved` にする
2. 承認したことを報告し、「`/run` で処理を開始できます」と伝える

## 注意
- 計画の修正指示を受けたら planner を再度呼ぶか自分で計画票・タスク票を直し、再提示する
- 同じブランチに複数の計画を重ねない（1ブランチ1計画。`plan_guard.py` が approved 2件以上を検出する）
- 既存の done と重複するタスクを作らない
