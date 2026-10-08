# Runbook（人が日々やること）

ハーネスは無人で回る。人の仕事は「ゴールを入れる」「計画を承認する」「blocked に答える」「月次で片づける」の4つ。

まだインストールしていない場合は先に `docs/install.md` を読む。

## 0. 大きなゴールは先に設計する
```
/design <ゴール（自然文）>
```
受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる時だけ使う。調査と質問を経て `vault/designs/D-xxx.md` ができるので、フェーズのゴール文を1つずつ次の `/plan` に渡す。小さい要求はここを飛ばして `/plan` に直行してよい。
考える工程なので、強いモデル（opus）のセッション（`claude --model opus` か、セッション内の `/model opus`）で実行する。スキルにモデルは固定していないので、人がセッションのモデルを選ぶ。実行する工程（`/run`。creator・verifier）は sonnet のまま（creator は 8 節の手順で試せる）。

## 1. ゴールを入れる
```
/plan <ゴール（自然文）>
```
計画 ID（`P-YYYYMMDD-<slug>`）を決めてブランチ `work/<計画ID>` を作り、planner が計画票 `vault/plans/<計画ID>.md`（draft）とタスク票 `vault/tasks/<計画ID>/T-01.md` 以降を作り、一覧を提示して止まる。
粒度が粗い・依存がおかしい時は修正指示を出す。基準は `docs/vault-spec.md` の第8節。
`/plan` も考える工程なので、強いモデル（opus）のセッションで実行する（選び方は 0 節と同じ）。実行する工程（`/run`）に入る時は sonnet のセッションに戻す。creator・verifier は sonnet のまま（creator は 8 節の手順で試せる）。

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
  - 環境変数 `HARNESS_STRICT_STOP`：未設定ならラッパーが `1` を入れて子プロセスに渡す。Stop フックが `stop_hook_active` の真でも判定を続け、verdict の無い終了を止める。`HARNESS_STRICT_STOP=0` を明示すれば従来の動き（2回目の停止は通す）になる。承認済みの計画票が0件なら Stop フックは何もしない
  - タイムアウトは標準エラーの `run_unattended: timeout <秒>s` で分かる（cron のログや CI のログで確認できる）。ラッパーは vault のファイルに書かない
  - タイムアウトで止めた後は、次回の `/run` が `.claude/skills/run/SKILL.md` 手順2.2（再開手順）で中断した地点から続きを再開する。同じ地点で止まり続けても `HARNESS_MAX_ATTEMPTS` で blocked になって止まる
  - 初回は対象フォルダで一度 `claude` を対話起動してフォルダを信頼する（`.claude/settings.json` の許可設定は信頼後にしか効かない）
  - 上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）
  - 承認済み計画の全タスクが `done` になったら、計画票の `status` を `done` にし `bash scripts/vcs_finish.sh` を実行する（GitHub なら `gh` コマンドで、GitLab なら `glab mr create` が呼ばれて PR/MR ができる。ホスティング無しの場合はブランチ名と `git merge --no-ff` の案内が出るので、それを人に伝える）
  - PR/MR ができたら、人が内容を確認して GitHub/GitLab 上の通常のマージ操作でマージする（ホスティング無しの場合は案内された `git merge --no-ff` を人が実行する）。コンフリクトがあれば計画のブランチ上で人が解決する。エージェントは `scripts/vcs_finish.sh` の実行までしか行わない。
  - PR のマージ方式：スカッシュマージを推奨する。main の履歴が1計画1コミットになり読みやすい。タスクごとの履歴は、`scripts/vcs_finish.sh` が作る PR 本文の「タスク履歴」表（タスク ID・title・コミット・verdict。生成は `scripts/pr_body.py`）から辿れる。表のコミットは PR の Commits タブで見られる。
    - GitHub でスカッシュする時は、リポジトリ設定の squash merge の既定コミットメッセージを `Pull request title and description` にする。表がスカッシュコミットのメッセージ（= main の `git log`）にも残る（設定は人が行う）
    - 通常のマージ（merge commit）も可。main にタスクごとのコミットが残る。ホスティング無しの `git merge --no-ff` の案内は今のまま

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
計画単位でまとめて移す。月次で人が `scripts/archive_plans.sh` を実行する。

対象は、計画票が `status: done`・タスク表が全行 `done`・PR がマージ済み（`main` に `status: done` の計画票がある）の計画のうち、新しい順に `--keep`（既定5件）を残した、それより古い全部。「新しい」は log の最初の日時行の日時で決め、同じなら計画 ID の文字列順とする。現在のブランチの計画は常に残し、5件に数えない。

移す前に `bash scripts/archive_plans.sh --list` で、移す計画 ID の一覧を確かめられる。

配置は次の4種別（`<年-月>` は計画 ID の日付部分から決まり、移した日ではない）。

- `vault/archive/<年-月>/plans/<計画ID>.md`
- `vault/archive/<年-月>/tasks/<計画ID>/`
- `vault/archive/<年-月>/verdicts/<計画ID>/`
- `vault/archive/<年-月>/log/<計画ID>.md`

計画 ID を渡さなければ移す対象の全部を、渡せばその ID だけを移す。

手順は PR ブランチ（または人が切った作業ブランチ）の上で行い、`main` へは PR でマージする。

```bash
bash scripts/archive_plans.sh --dry-run <計画ID> ...      # または --from-file <path>
bash scripts/archive_plans.sh --apply <計画ID> ...
git commit
```

`--dry-run`（または `--from-file <path>`）で移動内容を確かめ、`--apply` で移し、人が `git commit` する。

エージェント（creator を含む）は --apply を実行しない。creator は `vault/plans/`・`vault/log/` に書き込めず、done のタスク票・verdict の編集も禁止されている。スクリプト経由の移動はフックが見えない経路でその禁止を回避することになるため、実行は人が行う。

安全装置：done、全行 done、`main` で done、log に日時行がある、現在のブランチの計画でない、新しい `--keep` 件に入らない、未コミットの変更が無い、移動先が無い。このどれか1件でも外れたら何も移さない。候補が `--keep` 件以下の時も何も移さない。

集計：`model_stats.py` の既定は `vault/log/*.md` だけである。archive 済みの log を含めるには、次のように明示して渡す。

```bash
python3 scripts/model_stats.py vault/archive/*/log/*.md
```

移した後のファイルは `agent_write_guard.py` の done 判定の対象外になる（フックは `vault/tasks/`・`vault/verdicts/` だけを見る）。`vault/archive/2026-09/` にある旧形式（`todo.md`・`tasks/T-0024.md` など）はそのままにする。

計画 ID は日付＋スラッグなので再利用の心配が無く、採番の調整は不要。

## 6. ルールを足す
1. `vault/rules/{common,creator,verifier,planner}/` のどれかにルールファイル（`*.md`）を置く
2. 渡したい相手（全員／作成エージェント／verifier／planner）でディレクトリを決める
3. 反映させたい受け入れ基準の行にルールファイルを名指しして参照する
4. エージェントは `vault/rules/` に書けない（フックが常に拒否する）。ファイルは人が自分で置く・直す
5. ルールの変更自体をタスクにする時は、成果物を `vault/tasks/<計画ID>/<id>-proposal.md` に下書きさせ、verifier の PASS 後に人が実体へ反映する（`docs/vault-spec.md` の「提案ファイル方式」）

## 7. ハーネス自体の更新を取り込む
このハーネスを他のプロジェクトに組み込んでいる場合、フックやスキルを直しても組み込み先には届かない。取り込みたい時に次を打つ。

```bash
bash /path/to/ai-harness/scripts/install.sh --update /path/to/your-project
```

未編集のファイルは `update <path>` で最新化され、組み込み先で編集したファイルは `skip (edited) <path>` と報告されるだけで上書きされない。`.claude/settings.json` は hooks の欠落エントリと `permissions.deny` の不足分だけが足される。詳細は `docs/install.md` の「ハーネスを更新する（2回目以降）」。

## 8. creator のモデルを比べる
creator のモデルだけを haiku に替えて計画を回し、sonnet の時と成績・使用量を比べる。verifier・planner のモデルは変えない。どの計画で試すか、採用するかどうかは人が決める。

1. 環境変数 `HARNESS_CREATOR_MODEL=haiku` を付けて回す。対話は、セッションの起動時に設定する（起動後に変えても run の Bash には効かない場合があるので、変えたい時は起動し直す）。

   ```bash
   HARNESS_CREATOR_MODEL=haiku claude        # 対話：起動後に /run
   env HARNESS_CREATOR_MODEL=haiku python3 scripts/run_unattended.py   # 無人（ラッパーは環境変数を子に引き継ぐ）
   ```

2. 値が効いているかは、run の中で `echo "${HARNESS_CREATOR_MODEL:-}"` を実行して確かめる。`haiku` と出れば効いている。空なら効いていない。
3. haiku が受け付けられない値などで creator の呼び出しが失敗した時は、run が止まって報告する（`.claude/skills/run/SKILL.md` 手順3）。
4. 計画が終わったら、次の2つで sonnet の時と比べる。

   ```bash
   python3 scripts/model_stats.py
   python3 scripts/usage_stats.py --plan <haiku で回した計画ID>
   python3 scripts/usage_stats.py --plan <sonnet で回した計画ID>
   ```

   - `model_stats.py` の出力で `haiku` と `sonnet` の行を見比べる（1回目 PASS 率・平均 attempt・blocked 率・指摘あり率）。
   - `usage_stats.py` は2つの計画の creator の行を見比べる（calls＝呼び出し回数、tokens_total／tokens_avg＝トークン数、duration_avg_s＝所要時間）。
   - archive 済みの計画は 5 節と同じく、log や会話記録を引数で明示する（例：`python3 scripts/model_stats.py vault/archive/*/log/*.md`）。
5. 注意：`usage_stats.py` の model 列は完全なモデル ID（`resolvedModel` をそのまま出す）で、log や `model_stats.py` の alias（`haiku`・`sonnet`）とは表記が違う。行を突き合わせる時は読み替える。
6. 元に戻すには、環境変数を外して起動し直す（`HARNESS_CREATOR_MODEL` を付けなければ、これまでどおり sonnet）。

## 9. サンドボックスを確かめる
サンドボックスを有効にした後（このリポジトリでは計画のマージ後、導入先では手で足した後）、人が新しいセッションで効き目を確かめる。導入先で有効にする手順は `docs/install.md` の「サンドボックスを有効にする（任意）」を参照する。

1. Claude Code を起動し直す。設定はセッションの開始時に読まれるため、設定を変えたセッションのままでは効かない。
2. `/sandbox` を開き、サンドボックスが有効であることを確かめる。有効でない・使えないと表示された時は、手順3〜5 を飛ばして下の「使えない環境」に進む。続けて Config タブで、`denyWrite` の `./vault/rules` と `~/.claude/projects` が実際の絶対パス（このリポジトリの `vault/rules` とホームの `.claude/projects`）に解決されていることを確かめる。
3. Bash で次を実行し、失敗する（Permission denied などで終わり、`vault/rules/x.md` が作られない）ことを確かめる。このコマンドは `agent_write_guard.py` の Bash の解析では拒否されない形なので、失敗すればサンドボックスが効いている。

```
python3 -c "open('vault/rules/x.md','w')"
```

4. 次が `fail=0` で通ることを確かめる。

```
bash scripts/smoke.sh
```

5. 計画の最後に、次の push と PR 作成が通ることを確かめる。このリポジトリでは、サンドボックスを入れた計画の次の計画の run の最後で確かめてよい。

```
bash scripts/vcs_finish.sh
```

### うまくいかなかった時
- 3 の `python3 -c` が成功して `vault/rules/x.md` ができた時：サンドボックスが効いていない。作られたファイルは人が消し、2 の `/sandbox` の表示と `denyWrite` のパスの書き方を見直す。
- 4 の smoke が通らない時：どのケースが落ちたかを見て、サンドボックスの書き込み・通信の制限によるものかを確かめる。直し方は別の計画で決める。
- 5 の `vcs_finish.sh` が通らない時（`gh` の認証・ssh の remote への push）：別の計画で `excludedCommands` に `bash scripts/vcs_finish.sh` を足す。それまでは人がサンドボックスの外（ターミナル）で `bash scripts/vcs_finish.sh` を実行する。

### 使えない環境
`/sandbox` でサンドボックスが有効でない（使えない環境）と分かった時は、手順3〜5 を飛ばす。この場合の守りはフックの Bash の解析で、`bash scripts/smoke.sh` は通る。サンドボックスを使いたければ `docs/install.md` の前提（`bubblewrap`・`socat` など）を見る。

## 困ったとき
| 症状 | 見るところ |
|---|---|
| 終了できない（Stop フックがブロックする） | 表示された理由に従う。計画票のタスク表の doing/review 行と `vault/verdicts/<計画ID>/<id>.json` の整合 |
| フックが動かない | `bash scripts/smoke.sh`。`python3` のパス。フォルダを信頼済みか |
| verifier が書けない | `vault/verdicts/` 以外へ書こうとしていないか（`agent_write_guard.py` が拒否する） |
| エージェント定義（`.claude/agents/*.md`）やスキルを変えたのに反映されない | 定義はセッション開始時に読み込まれる。編集後はセッションを再起動する（`claude -p` は起動ごとに読み直すので影響なし） |
| 状態が壊れた | `vault/log/<計画ID>.md` を見て計画票のタスク表を手で直す。doing は1件だけにする |
