---
name: run
description: 自分のブランチの計画を進める。「タスクを進めて」「次のタスクをやって」「続きから」「続きをやって」「run」と言われたら必ずこのスキルを使う。承認済みの計画票（vault/plans/ の status: approved）のタスク表を読み、先頭タスクを doing にして実装し、verifier で検証し、verdict に従って done / doing / blocked に更新する。全タスクが done になったら PR を作る。
argument-hint: [task-id（省略時は先頭）]
---

自分のブランチの計画を1タスク処理する。状態の正本は承認済みの計画票（`vault/plans/<計画ID>.md` のタスク表）、仕様は `docs/vault-spec.md`。

## 0. 現在時刻
`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'` で取る。ログ・verdict の日時はこれを使う。

## 1. 計画票を見つける
1. `vault/plans/*.md` を走査し、frontmatter の `status` が `approved` の計画票を探す
2. 0件なら「承認済みの計画が見つかりません。`/plan approve <計画ID>` を実行してください」と報告して終わる
3. 2件以上なら「approved な計画票が複数あります（異常）。人に確認してください」と報告して終わる（`plan_guard.py` が書き込み時に検出しているはずだが、念のためここでも扱う。修復はしない）
4. 見つかった1件を計画票、その frontmatter の `id` を計画 ID とする

## 2. 取り出す
1. 計画票の「タスク表」を読む
2. `doing` の行があればそれを続ける（`vault/tasks/<計画ID>/<id>.md` の「進捗」から再開）。`review` の行があれば手順4へ
3. 無ければ `todo` の行を上から見て、`after` のタスクがすべて `done` である最初の1件を取る。引数 `$ARGUMENTS` に ID があればその行を取る
4. 取れる行が無ければ「取れるタスクがありません」と報告して終わる
5. 取った行の status を `doing`、attempt を `1` にする。`vault/log/<計画ID>.md` に `- <日時> <id> todo→doing attempt=1` を追記

## 3. 作る
1. `vault/tasks/<計画ID>/<id>.md` の全見出しを読む。「決定済み」にある回答を優先し、質問はしない
2. `bash scripts/rules.sh creator` を実行し、列挙されたファイルをすべて読み、以降の成果物作成でそれに従う（列挙が空なら何もしない）。読んだファイルがあれば「進捗」に「読んだルール: a.md, b.md」の形で1行記録する
3. 「成果物」を作る。受け入れ基準の確認コマンドは自分でも実行して通しておく
4. 進めながら「進捗」に箇条書きで追記する（セッションが切れても再開できる粒度）
5. 判断が必要で「決定済み」に答えが無いことが出たら、status を `blocked` にし question 列に質問を書き、log に追記して終わる

## 4. review にする
status を `review` にし、`vault/log/<計画ID>.md` に `- <日時> <id> doing→review attempt=<n>` を追記する。

## 5. 検証する
1. Agent ツールで `verifier` サブエージェントを呼ぶ。prompt はタスク ID だけ（例：`<計画ID>/<id> を検証して vault/verdicts/<計画ID>/<id>.json を書いてください`）。作業内容の説明や言い訳を渡さない
2. 結果を待ち、`vault/verdicts/<計画ID>/<id>.json` を読む（verifier の返答文ではなくファイルを根拠にする）

## 6. verdict に従う
- `PASS` → status を `done` にし、`vault/log/<計画ID>.md` に `- <日時> <id> review→done attempt=<n>` を追記
- `FAIL` かつ attempt < 上限（`HARNESS_MAX_ATTEMPTS`、既定 3） → status を `doing`、attempt を +1 にし、`vault/log/<計画ID>.md` に `review→doing attempt=<n+1> 理由要約` を追記。reasons を読んで修正し、手順3の3から繰り返す
- `FAIL` かつ attempt ≥ 上限 → status を `blocked`、question 列に reasons の要約を書き、`vault/log/<計画ID>.md` に `review→blocked attempt=<n> 理由要約` を追記して終わる

## 7. 次へ・完了
- 計画票に取れる行が残っていれば手順2に戻る
- 全タスクが `done` になったら、計画票 frontmatter の `status` を `done` にし、`gh pr create` を実行して PR を作る（`gh pr merge` は実行しない。マージは人が行う）。draft PR にするかは規定しない
- どちらでもなければ、処理した ID と結果を1行ずつ報告して終わる

## 注意
- Stop フックが verdict と status を照合する。手順を飛ばして終わろうとするとブロックされ、理由が表示される
- `done` のタスク票は編集しない。計画票のタスク表の列順・見出しは変えない
- git のコミットはタスク票の受け入れ基準に含まれている場合だけ行う
- タスク中は `vault/rules/` を編集しない（verifier の判定基準を自分で変えないため。フックでも拒否される）
