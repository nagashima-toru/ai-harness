# Runbook（人が日々やること）

ハーネスは無人で回る。人の仕事は「ゴールを入れる」「blocked に答える」「PR をマージする」「月次で片づける」の4つ。

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
計画 ID（`P-YYYYMMDD-<slug>`）を決めてブランチ `work/<計画ID>` を作り、planner が計画票 `vault/plans/<計画ID>.md`（draft）とタスク票 `vault/tasks/<計画ID>/T-01.md` 以降を作る。粒度の確認を通ると計画票の `status` を `approved` にしてコミットし、続けて `/run` を実行する（人の承認を待たない）。planner に人への質問がある時だけ、質問を提示して止まる。会話で答えると、回答を反映してから承認と `/run` に進む。
粒度の基準は `docs/vault-spec.md` の第8節。
`/plan` も考える工程なので、強いモデル（opus）のセッションで実行する（選び方は 0 節と同じ）。続けて実行する `/run` もそのセッションのモデルのまま動く。creator・verifier はサブエージェントで、それぞれの定義のモデル（sonnet）で動く（creator は 8 節の手順で試せる）。

## 2. 計画は自動で承認される
`/plan` が計画票の `status` を `approved` にし、`vault/log/<計画ID>.md` に `- <日時> - draft→approved /plan による自動承認` を追記してコミットする。人が承認のコマンドを打つことは無い。計画の中身は、最後にできる PR で人が確認する。1ブランチにつき approved は1件（`plan_guard.py` が2件以上を検出する）。
計画を直したい時は、`/run` の途中でも止めて指示を出してよい。PR の段階で気づいた時は、マージせずに指示を出す。

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
  - 承認済み計画の全タスクが `done` になったら、計画票の `status` を `done` にしてコミットし、計画の記録を PR 本文に写し、残すべき情報を docs への追記か Issue 化で取り出し、`scripts/purge_plan.sh` で計画一式を除去してコミットしてから `bash scripts/vcs_finish.sh` を実行する（GitHub なら `gh api`（REST）で、GitLab なら `glab mr create` が呼ばれて PR/MR ができる。ホスティング無しの場合はブランチ名と `git merge --no-ff` の案内が出るので、それを人に伝える）
  - PR/MR ができたら、人が内容を確認して GitHub/GitLab 上の通常のマージ操作でマージする（ホスティング無しの場合は案内された `git merge --no-ff` を人が実行する）。コンフリクトがあれば計画のブランチ上で人が解決する。エージェントは `scripts/vcs_finish.sh` の実行までしか行わない。
  - PR のマージ方式：スカッシュマージを推奨する。main の履歴が1計画1コミットになり読みやすい。タスクごとの履歴は、`scripts/vcs_finish.sh` が作る PR 本文の「タスク履歴」表（タスク ID・title・コミット・verdict。生成は `scripts/pr_body.py`）から辿れる。表のコミットは PR の Commits タブで見られる。PR 本文には「タスク履歴」表に加えて計画の記録（ゴール・タスク表・log の全行）と verifier の指摘・取り出した情報が載り、計画一式は `main` に入らないので、マージ後に計画を調べる時は PR を見る。
    - GitHub でスカッシュする時は、リポジトリ設定の squash merge の既定コミットメッセージを `Pull request title and description` にする。表がスカッシュコミットのメッセージ（= main の `git log`）にも残る（設定は人が行う）
    - 通常のマージ（merge commit）も可。main にタスクごとのコミットが残る。ホスティング無しの `git merge --no-ff` の案内は今のまま
  - run の振り返り（手順8）で issue の起票に失敗すると、`vault/harness-improvements/<計画ID>.md` に提案が残る。提案に対応する計画を立てる時は、その計画の中でそのファイルを削除する（対応が済んだ提案ファイルを残さない）

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

`blocked→todo` は、人が `/plan unblock` で指示して初めて行われる。`/plan` スキルが `/plan unblock <計画ID> <id> [回答]` の形でない指示（「T-03 解除して」のような自由な文・AskUserQuestion への回答）を断る。フックでは確かめない（D-015 フェーズ2 で廃止）ので、エージェントは人の指示なしに解除しない。

代替手段として、人がエディタで計画票を直接直してもよい（「決定済み」への回答追記、`status` を `todo`、`attempt` を `0`、`question` を空に）。この場合は `/plan` スキルを通らない。変更後は自分で log に上の形式の行を追記してコミットする。

## 5. 一括削除の手順
`main` にマージ済みの計画一式（`vault/plans/<計画ID>.md`・`vault/tasks/<計画ID>/`・`vault/verdicts/<計画ID>/`・`vault/log/<計画ID>.md`）と `vault/archive/` を、人が `scripts/purge_plan.sh --merged` でまとめて削除する。新しい計画は run の手順7で PR の前に除去されるので、この手順は `main` に残った分を片づける時に使う。

対象の条件（すべて満たす計画）：

1. 計画 ID が `P-YYYYMMDD-<slug>` の形
2. 現在のブランチの計画でない
3. 計画票が `status: done`
4. タスク表が全行 `done`
5. `main` の版の計画票も `status: done`

`--keep` は無く、マージ済みは全部消す。

```bash
git switch -c purge/merged-<YYYYMMDD>
bash scripts/purge_plan.sh --merged --list
bash scripts/purge_plan.sh --merged --report
bash scripts/purge_plan.sh --merged --apply
git commit -m "一括削除: main にマージ済みの計画一式と vault/archive/ を削除"
```

PR を作り、人がマージする。

`--report` は `<計画ID>/<id>: blocked <補足>`（log の `→blocked` の行の補足＝そのとき聞いた質問）と `<計画ID>/<id>: reasons <理由>`（verdict の `reasons`）を出す。`--report` の出力を見て、未解決のもの・改善提案になるものを人が Issue 化してから `--apply` する。

`--apply` は対象の4種に加えて `vault/archive/` も丸ごと消える。コミットはしない。対象パスに未コミット・未追跡の変更があれば何も消さずに終了コード1になる。

実行者の制限：--merged --apply は人だけが実行する。エージェントは --list・--report だけを使う。他の計画の done のタスク票・verdict を消すのは、フック（`agent_write_guard.py`）と差分ゲート（`scripts/diff_gate.py`）を通らない経路になるため。

対象外：計画 ID が `P-YYYYMMDD-<slug>` の形でない旧形式の計画（`P-019` など）と、旧形式のタスク票（`vault/tasks/T-0036.md` など）は対象にならない。消す時は人が `git rm` する。`vault/harness-improvements/` も対象外。

## 6. ルールを足す
1. `vault/rules/{common,creator,verifier,planner}/` のどれかにルールファイル（`*.md`）を置く
2. 渡したい相手（全員／作成エージェント／verifier／planner）でディレクトリを決める
3. 反映させたい受け入れ基準の行にルールファイルを名指しして参照する
4. ルールの追加・変更は、人が編集するか、タスクの「成果物」に宣言して変える。フックは `vault/rules/` を止めず、宣言の無い変更は差分ゲート `scripts/diff_gate.py` が差し戻す。変更は PR の差分で見える

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
5. 注意：`usage_stats.py` の model 列は完全なモデル ID（`resolvedModel` をそのまま出す）で、log や `model_stats.py` の alias（`haiku`・`sonnet`）とは表記が違う。行を突き合わせる時は読み替える。
6. 元に戻すには、環境変数を外して起動し直す（`HARNESS_CREATOR_MODEL` を付けなければ、これまでどおり sonnet）。

## 9. 権限モードの選び方
- ハーネス自身（`.claude/` の下：`hooks/`・`skills/`・`agents/`・`settings.json`・`ai-harness.md`）を変える計画は、acceptEdits（編集を自動で許可するモード。例：`claude --permission-mode acceptEdits`）で立ち上げる
- それ以外の計画は auto モードでよい
- auto モードで、`.claude/` の変更が Self-Modification として拒否されてタスクが blocked になった時は、acceptEdits で立ち上げ直し、`/plan unblock <計画ID> <id>` → `/run` で再開する
- 理由：auto モードの分類器の判定は設定では変えられない（D-015「今回やらないこと」）

## 困ったとき
| 症状 | 見るところ |
|---|---|
| 終了できない（Stop フックがブロックする） | 表示された理由に従う。計画票のタスク表の doing/review 行と `vault/verdicts/<計画ID>/<id>.json` の整合 |
| フックが動かない | `bash scripts/smoke.sh`。`python3` のパス。フォルダを信頼済みか |
| verifier が書けない | `vault/verdicts/` 以外へ書こうとしていないか（`agent_write_guard.py` が拒否する） |
| エージェント定義（`.claude/agents/*.md`）やスキルを変えたのに反映されない | 定義はセッション開始時に読み込まれる。編集後はセッションを再起動する（`claude -p` は起動ごとに読み直すので影響なし） |
| 状態が壊れた | `vault/log/<計画ID>.md` を見て計画票のタスク表を手で直す。doing/review は着手可能集合の範囲で複数になりうる（`docs/vault-spec.md` 2節） |
| merge の途中で止まった（`git status` に `You have unmerged paths` や `All conflicts fixed but you are still merging`） | `git merge --abort` で取り込む前に戻す。計画ブランチへのタスクの取り込みは `transition.py` がやり直す（衝突なら blocked にする） |
| rebase の途中で止まった（`git status` に `rebase in progress`） | `git rebase --abort` で始める前に戻す |
| HEAD と作業ツリーが食い違っている（コミットしていない変更が残って次の操作が止まる、など） | 作業ブランチ（`work/<計画ID>` か creator の worktree のブランチ）の上でだけ、`git reset --hard HEAD`（または戻したいコミット）で作業ツリーを HEAD に戻す。`main` では使わない。 |

上の git の3行は、エージェントが自分で直してよい。`permissions.deny` に残っているのは `git push --force` 系・`rm -rf` 系・`sudo`・`gh pr merge`・`glab mr merge` だけで、作業ブランチの上の `git reset --hard`・`git clean`・`git branch -D` は止めない（D-015。壊れてもブランチを捨てて作り直せる）。半端な状態を見つける診断スクリプトは無い。
