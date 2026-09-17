---
name: run-queue
description: キューを処理する。「キューを処理して」「次のタスクをやって」「続きから」「続きをやって」「タスクを進めて」「run-queue」と言われたら必ずこのスキルを使う。vault/todo.md の先頭タスクを doing にして実装し、verifier で検証し、verdict に従って done / doing / blocked に更新する。
argument-hint: [task-id（省略時は先頭）]
---

キューを1件処理する。状態の正本は `vault/todo.md`、仕様は `docs/vault-spec.md`。

## 0. 現在時刻
`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'` で取る。ログ・verdict の日時はこれを使う。

## 1. 取り出す
1. `vault/todo.md` を読む
2. `doing` の行があればそれを続ける（`vault/tasks/<id>.md` の「進捗」から再開）。`review` の行があれば手順4へ
3. 無ければ `todo` の行を上から見て、`after` のタスクがすべて `done` である最初の1件を取る。引数 `$ARGUMENTS` に ID があればその行を取る
4. 取れる行が無ければ「キューは空です」と報告して終わる
5. 取った行の status を `doing`、attempt を `1` にする。`vault/log/queue.md` に `- <日時> <id> todo→doing attempt=1` を追記

## 2. 作る
1. `vault/tasks/<id>.md` の全見出しを読む。「決定済み」にある回答を優先し、質問はしない
2. 「成果物」を作る。受け入れ基準の確認コマンドは自分でも実行して通しておく
3. 進めながら「進捗」に箇条書きで追記する（セッションが切れても再開できる粒度）
4. 判断が必要で「決定済み」に答えが無いことが出たら、status を `blocked` にし question 列に質問を書き、log に追記して終わる

## 3. review にする
status を `review` にし、log に `- <日時> <id> doing→review attempt=<n>` を追記する。

## 4. 検証する
1. Agent ツールで `verifier` サブエージェントを呼ぶ。prompt はタスク ID だけ（例：`T-0001 を検証して vault/verdicts/T-0001.json を書いてください`）。作業内容の説明や言い訳を渡さない
2. 結果を待ち、`vault/verdicts/<id>.json` を読む（verifier の返答文ではなくファイルを根拠にする）

## 5. verdict に従う
- `PASS` → status を `done` にし、log に `- <日時> <id> review→done attempt=<n>` を追記
- `FAIL` かつ attempt < 上限（`HARNESS_MAX_ATTEMPTS`、既定 3） → status を `doing`、attempt を +1 にし、log に `review→doing attempt=<n+1> 理由要約` を追記。reasons を読んで修正し、手順2の3から繰り返す
- `FAIL` かつ attempt ≥ 上限 → status を `blocked`、question 列に reasons の要約を書き、log に `review→blocked attempt=<n> 理由要約` を追記して終わる

## 6. 次へ
todo に取れる行が残っていれば手順1に戻る。無ければ処理した ID と結果を1行ずつ報告して終わる。

## 注意
- Stop フックが verdict と status を照合する。手順を飛ばして終わろうとするとブロックされ、理由が表示される
- `done` のタスク票は編集しない。todo.md の列順・見出しは変えない
- git のコミットはタスク票の受け入れ基準に含まれている場合だけ行う
