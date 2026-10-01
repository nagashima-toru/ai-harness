# Runbook（人が日々やること）

ハーネスは無人で回る。人の仕事は「ゴールを入れる」「計画を承認する」「blocked に答える」「月次で片づける」の4つ。

まだインストールしていない場合は先に `docs/install.md` を読む。

## 0. 大きなゴールは先に設計する
```
/design <ゴール（自然文）>
```
受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる時だけ使う。調査と質問を経て `vault/designs/D-xxx.md` ができるので、フェーズのゴール文を1つずつ次の `/plan` に渡す。小さい要求はここを飛ばして `/plan` に直行してよい。
考える工程なので、強いモデル（opus）のセッション（`claude --model opus` か、セッション内の `/model opus`）で実行する。スキルにモデルは固定していないので、人がセッションのモデルを選ぶ。実行する工程（`/run`。creator・verifier）は sonnet のまま。

## 1. ゴールを入れる
```
/plan <ゴール（自然文）>
```
計画 ID（`P-YYYYMMDD-<slug>`）を決めてブランチ `work/<計画ID>` を作り、planner が計画票 `vault/plans/<計画ID>.md`（draft）とタスク票 `vault/tasks/<計画ID>/T-01.md` 以降を作り、一覧を提示して止まる。
粒度が粗い・依存がおかしい時は修正指示を出す。基準は `docs/vault-spec.md` の第8節。
`/plan` も考える工程なので、強いモデル（opus）のセッションで実行する（選び方は 0 節と同じ）。実行する工程（`/run`）に入る時は sonnet のセッションに戻す。creator・verifier は sonnet のまま。

## 2. 計画を承認する
```
/plan approve <計画ID>
```
計画票 frontmatter の `status` が `approved` になる。承認前のタスクには着手しない。1ブランチにつき approved は1件（`plan_guard.py` が2件以上を検出する）。

## 3. キューを回す
- 対話：`/run`（1件処理して報告。続けて呼べば次へ）
- 無人：`python3 scripts/run_unattended.py` を cron / CI から定期実行（素の `claude -p "/run"` を直接呼ばず、タイムアウト付きラッパー経由にしてハングで居座らないようにする）
  - 環境変数 `HARNESS_RUN_CMD`：実行するコマンド。未設定なら既定の `claude -p "/run"` が実行される
  - 環境変数 `HARNESS_RUN_TIMEOUT`：制限時間（秒、既定 3600）。超えると SIGTERM を送り、10秒待っても終わらなければ SIGKILL し、終了コード124で終わる。時間内に終わった場合は子の終了コードをそのまま返す
  - タイムアウトは標準エラーの `run_unattended: timeout <秒>s` で分かる（cron のログや CI のログで確認できる）。ラッパーは vault のファイルに書かない
  - タイムアウトで止めた後は、次回の `/run` が `.claude/skills/run/SKILL.md` 手順2.2（再開手順）で中断した地点から続きを再開する。同じ地点で止まり続けても `HARNESS_MAX_ATTEMPTS` で blocked になって止まる
  - 初回は対象フォルダで一度 `claude` を対話起動してフォルダを信頼する（`.claude/settings.json` の許可設定は信頼後にしか効かない）
  - 上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）
  - 承認済み計画の全タスクが `done` になったら、計画票の `status` を `done` にし `bash scripts/vcs_finish.sh` を実行する（GitHub なら `gh` コマンドで、GitLab なら `glab mr create` が呼ばれて PR/MR ができる。ホスティング無しの場合はブランチ名と `git merge --no-ff` の案内が出るので、それを人に伝える）
  - PR/MR ができたら、人が内容を確認して GitHub/GitLab 上の通常のマージ操作でマージする（ホスティング無しの場合は案内された `git merge --no-ff` を人が実行する）。コンフリクトがあれば計画のブランチ上で人が解決する。エージェントは `scripts/vcs_finish.sh` の実行までしか行わない。

## 4. blocked に答えて戻す
```
/plan unblock <計画ID> <id> [回答]
```
1. 計画票（`vault/plans/<計画ID>.md`）のタスク表で `status=blocked` の行の `question` を読む
2. `/plan unblock <計画ID> <id> <回答>` を打つ。答える質問が無い blocked（ハングやマージコンフリクトなど）は回答を省いてよい。1回のコマンドで解除するのは1行だけ。複数あれば1行ずつ打つ

エージェントが次を行う。
- 回答を `vault/tasks/<計画ID>/<id>.md` の「決定済み」に追記する（回答を省いた時は追記しない）
- 計画票のその行の `status` を `todo`、`attempt` を `0`、`question` を空にする
- `vault/log/<計画ID>.md` に `- YYYY-MM-DD HH:MM <id> blocked→todo 人の指示: /plan unblock <計画ID> <id>` を追記する
- 変更をコミットする

`blocked→todo` は、人が `/plan unblock` で指示して初めて行われる。フックが会話記録の人の発言にこのコマンドがあるかを確認するので、エージェントが独断で解除することはできない。「T-03 解除して」のような自由な文や AskUserQuestion への回答では解除できない。

代替手段として、人がエディタで計画票を直接直してもよい（「決定済み」への回答追記、`status` を `todo`、`attempt` を `0`、`question` を空に）。この場合フックは働かない。変更後は自分で log に上の形式の行を追記してコミットする。

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
