# Runbook（人が日々やること）

ハーネスは無人で回る。人の仕事は「ゴールを入れる」「計画を承認する」「blocked に答える」「月次で片づける」の4つ。

まだインストールしていない場合は先に `docs/install.md` を読む。

## 0. 大きなゴールは先に設計する
```
/design <ゴール（自然文）>
```
受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる時だけ使う。調査と質問を経て `vault/designs/D-xxx.md` ができるので、フェーズのゴール文を1つずつ次の `/plan` に渡す。小さい要求はここを飛ばして `/plan` に直行してよい。

## 1. ゴールを入れる
```
/plan <ゴール（自然文）>
```
計画 ID（`P-YYYYMMDD-<slug>`）を決めてブランチ `work/<計画ID>` を作り、planner が計画票 `vault/plans/<計画ID>.md`（draft）とタスク票 `vault/tasks/<計画ID>/T-01.md` 以降を作り、一覧を提示して止まる。
粒度が粗い・依存がおかしい時は修正指示を出す。基準は `docs/vault-spec.md` の第8節。

## 2. 計画を承認する
```
/plan approve <計画ID>
```
計画票 frontmatter の `status` が `approved` になる。承認前のタスクには着手しない。1ブランチにつき approved は1件（`plan_guard.py` が2件以上を検出する）。

## 3. キューを回す
- 対話：`/run`（1件処理して報告。続けて呼べば次へ）
- 無人：`claude -p "/run"` を cron / CI から定期実行
  - 初回は対象フォルダで一度 `claude` を対話起動してフォルダを信頼する（`.claude/settings.json` の許可設定は信頼後にしか効かない）
  - 上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）
  - 承認済み計画の全タスクが `done` になったら、計画票の `status` を `done` にし `gh pr create` する（`gh pr merge` はしない。マージは人が行う）

## 4. blocked に答えて戻す
1. 計画票（`vault/plans/<計画ID>.md`）のタスク表で `status=blocked` の行の `question` を読む
2. 回答を `vault/tasks/<計画ID>/<id>.md` の「決定済み」に書く（必要なら受け入れ基準も直す）
3. 行の `status` を `todo`、`question` を空にする。`attempt` は 0 に戻す
4. `vault/log/<計画ID>.md` に `- YYYY-MM-DD HH:MM <id> blocked→todo 回答を決定済みに追記` を追記

`blocked→todo` は人だけが行う。エージェントには戻させない。

## 5. 月次で done を archive に移す
計画単位でまとめて移す。計画票の全タスクが `done` になり、PR がマージされたら、その計画票・配下のタスク票・verdict・ログをまとめて `vault/archive/<年-月>/` に移す。

```bash
mkdir -p vault/archive/$(date +%Y-%m)
git mv vault/plans/<計画ID>.md vault/archive/$(date +%Y-%m)/
git mv vault/tasks/<計画ID> vault/archive/$(date +%Y-%m)/
git mv vault/verdicts/<計画ID> vault/archive/$(date +%Y-%m)/
git mv vault/log/<計画ID>.md vault/archive/$(date +%Y-%m)/
```
計画 ID は日付＋スラッグなので再利用の心配が無く、採番の調整は不要。

## 6. ルールを足す
1. `vault/rules/{common,creator,verifier,planner}/` のどれかにルールファイル（`*.md`）を置く
2. 渡したい相手（全員／作成エージェント／verifier／planner）でディレクトリを決める
3. 反映させたい受け入れ基準の行にルールファイルを名指しして参照する

## 7. ハーネス自体の更新を取り込む
このハーネスを他のプロジェクトに組み込んでいる場合、フックやスキルを直しても組み込み先には届かない。取り込みたい時に次を打つ。

```bash
bash /path/to/ai-harness/scripts/install.sh --update /path/to/your-project
```

未編集のファイルは `update <path>` で最新化され、組み込み先で編集したファイルは `skip (edited) <path>` と報告されるだけで上書きされない。`.claude/settings.json` は hooks の欠落エントリと `permissions.deny` の不足分だけが足される。詳細は `docs/install.md` の「ハーネスを更新する（2回目以降）」。

## 困ったとき
| 症状 | 見るところ |
|---|---|
| 終了できない（Stop フックがブロックする） | 表示された理由に従う。計画票のタスク表の doing/review 行と `vault/verdicts/<計画ID>/<id>.json` の整合 |
| フックが動かない | `bash scripts/smoke.sh`。`python3` のパス。フォルダを信頼済みか |
| verifier が書けない | `vault/verdicts/` 以外へ書こうとしていないか（`agent_write_guard.py` が拒否する） |
| エージェント定義（`.claude/agents/*.md`）やスキルを変えたのに反映されない | 定義はセッション開始時に読み込まれる。編集後はセッションを再起動する（`claude -p` は起動ごとに読み直すので影響なし） |
| 状態が壊れた | `vault/log/<計画ID>.md` を見て計画票のタスク表を手で直す。doing は1件だけにする |
