# Runbook（人が日々やること）

ハーネスは無人で回る。人の仕事は「ゴールを入れる」「計画を承認する」「blocked に答える」「月次で片づける」の4つ。

## 0. 大きなゴールは先に設計する
```
/design <ゴール（自然文）>
```
受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる時だけ使う。調査と質問を経て `vault/designs/D-xxx.md` ができるので、フェーズのゴール文を1つずつ次の `/plan` に渡す。小さい要求はここを飛ばして `/plan` に直行してよい。

## 1. ゴールを入れる
```
/plan <ゴール（自然文）>
```
planner が `vault/plans/P-xxx.md`（draft）とタスク票 `vault/tasks/T-xxxx.md` を作り、一覧を提示して止まる。
粒度が粗い・依存がおかしい時は修正指示を出す。基準は `docs/vault-spec.md` の第9節。

## 2. 計画を承認する
```
/plan approve P-xxx
```
plan の status が `approved` になり、タスクが `vault/todo.md` に `todo` で登録される。承認前のタスクは todo.md に載らない。

## 3. キューを回す
- 対話：`/run-queue`（1件処理して報告。続けて呼べば次へ）
- 無人：`claude -p "/run-queue"` を cron / CI から定期実行
  - 初回は対象フォルダで一度 `claude` を対話起動してフォルダを信頼する（`.claude/settings.json` の許可設定は信頼後にしか効かない）
  - 上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）

## 4. blocked に答えて todo に戻す
1. `vault/todo.md` で `status=blocked` の行の `question` を読む
2. 回答を `vault/tasks/<id>.md` の「決定済み」に書く（必要なら受け入れ基準も直す）
3. 行の `status` を `todo`、`question` を空にする。`attempt` は 0 に戻す
4. `vault/log/queue.md` に `- YYYY-MM-DD HH:MM T-xxxx blocked→todo 回答を決定済みに追記` を追記

`blocked→todo` は人だけが行う。エージェントには戻させない。

## 5. 月次で done を archive に移す
```bash
mkdir -p vault/archive/$(date +%Y-%m)
git mv vault/tasks/T-0001.md vault/archive/$(date +%Y-%m)/     # done のタスク票
git mv vault/verdicts/T-0001.json vault/archive/$(date +%Y-%m)/
```
- `vault/todo.md` から該当行を削除する（ID は再利用しない。採番は archive も含めた最大値 +1）
- `vault/log/queue.md` は消さない（追記専用）

## 6. ルールを足す
1. `vault/rules/{common,creator,verifier,planner}/` のどれかにルールファイル（`*.md`）を置く
2. 渡したい相手（全員／作成エージェント／verifier／planner）でディレクトリを決める
3. 反映させたい受け入れ基準の行にルールファイルを名指しして参照する

## 困ったとき
| 症状 | 見るところ |
|---|---|
| 終了できない（Stop フックがブロックする） | 表示された理由に従う。`vault/todo.md` の doing/review 行と `vault/verdicts/<id>.json` の整合 |
| フックが動かない | `bash scripts/smoke.sh`。`python3` のパス。フォルダを信頼済みか |
| verifier が書けない | `vault/verdicts/` 以外へ書こうとしていないか（`agent_write_guard.py` が拒否する） |
| エージェント定義（`.claude/agents/*.md`）やスキルを変えたのに反映されない | 定義はセッション開始時に読み込まれる。編集後はセッションを再起動する（`claude -p` は起動ごとに読み直すので影響なし） |
| 状態が壊れた | `vault/log/queue.md` を見て todo.md を手で直す。doing は1件だけにする |
