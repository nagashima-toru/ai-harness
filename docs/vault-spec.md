# Vault 仕様（正本）

エージェントと人が共有する状態はすべて `vault/` 配下のファイルに置く。この文書が命名・状態遷移の正本であり、CLAUDE.md や各スキルはここを参照する。

## 1. ディレクトリ

| パス | 内容 |
|---|---|
| `vault/plans/<計画ID>.md` | 計画票（テンプレート：`vault/templates/plan.md`）。**タスクの状態の正本**。キューと呼ぶのはこの票のタスク表のこと |
| `vault/tasks/<計画ID>/T-01.md` | タスク票（テンプレート：`vault/templates/task.md`） |
| `vault/verdicts/<計画ID>/T-01.json` | 検証結果。最新のみ、上書き |
| `vault/log/<計画ID>.md` | その計画の追記専用ログ |
| `vault/designs/D-001.md` | 設計文書（テンプレート：`vault/templates/design.md`）。`/plan` に渡す前の下ごしらえ |
| `vault/rules/` | 作成エージェント・verifier・planner に渡すルール（「ルール（`vault/rules/`）」の節を見る） |
| `vault/archive/<年-月>/{plans,tasks,verdicts,log}/` | done かつ PR がマージ済みの計画一式の移動先（`vault/` と同じ種別ごとのサブディレクトリ。詳細は表の後の段落）。参照用で、消しても運用に影響しない |

archive への移動は人が `scripts/archive_plans.sh --apply` で行う（手順は `docs/runbook.md` 5節）。エージェントは `--list`・`--dry-run` だけを使う。計画票が `status: done`・タスク表が全行 `done`・`main` でも `status: done`（マージ済み）・log に日時行がある計画を候補にし、新しい順に --keep（既定5）件を残す。それより古い全部を移す。現在のブランチの計画は候補に入れず、5件に数えない。「新しい」の基準は log の最初の日時行（`- YYYY-MM-DD HH:MM ` で始まる最初の行）の日時で、同じなら計画 ID の文字列順で後ろのものを新しいとみなす。`<年-月>` は計画 ID の日付部分から決める。移した後のファイルは agent_write_guard.py の done 判定の対象外になる（フックは `vault/tasks/`・`vault/verdicts/` だけを見る）。`vault/archive/` 配下はいざという時の参照用で、編集のチェックは不要。

計画をまたぐキューは持たない。**1セッション = 1計画 = 1ブランチ**で、計画の作成から実行・PR までを1本のブランチに閉じる。状態ファイルが計画ごとに分かれるので、複数のエージェントセッションが別々の計画を同時に進めても競合しない。

「自分のブランチの計画票」は `vault/plans/*.md` を走査し、frontmatter の `status` が `approved` のものを取る。2つ以上 `approved` があるのは異常（1ブランチ1計画の不変条件）。
実際にこの走査を行うスクリプトが `scripts/current_plan.sh`（`vault/plans/*.md` の frontmatter のみを見て、approved な計画票の計画 ID を1行1件で出力する）。

証跡は3層で残る。`vault/log/<計画ID>.md`（状態遷移）・`vault/verdicts/<計画ID>/T-01.json`（判定の根拠）・git の履歴（タスクごとのマージコミット。worktree での作業を計画ブランチへ `git merge --no-ff` で取り込んだもの）と、オーケストレーターが `bash scripts/vcs_finish.sh` で作る PR。どれも計画のブランチ内に閉じるので、セッション間で競合しない。

引数なしの `scripts/vcs_finish.sh` は、現在のブランチ（`work/<計画IDの英小文字>`）の計画が見つかれば、PR/MR のタイトルを `<計画ID>: <ゴールの1行目>`、本文を `scripts/pr_body.py` が出す「タスク履歴」表（タスク ID・title・`<計画ID>/<id>: done` コミットの短縮ハッシュ・verdict）にする。PR がスカッシュマージされて main にタスクごとのコミットが残らなくても、この表から辿れる。マージ方式の運用は `docs/runbook.md` 3節を参照。

## 2. 状態（5つで固定、英小文字）

| status | 意味 | 誰が付けるか |
|---|---|---|
| `todo` | 着手可。上から順に取る | planner / 人 |
| `doing` | 作業中。**`after` 依存の無い集合（着手可能集合）に限り複数件になりうる** | 作成エージェント |
| `review` | 作成完了、検証待ち | 作成エージェント |
| `blocked` | 人の判断待ち。question 必須 | 作成エージェント / フック |
| `done` | 完了。以後編集禁止 | 作成エージェント（verdict が PASS の時のみ） |

この5つは計画票のタスク表の中の状態で、状態を数える単位もその表の中に閉じる。別のブランチで別の計画が `doing` のタスクを持っていても干渉しない。

同時に `doing`/`review` になれるのは、着手可能集合（`todo` かつ `after` の依存が全て `done` なタスクの集合）のうち、互いに `after` で依存し合わないものに限る。計画票・`vault/log/<計画ID>.md` への書き込みは、並行して作業していても常にオーケストレーター（`run` のメインセッション）1プロセスに集約し、複数プロセスが同じファイルへ同時に書き込むことは無い。

遷移：`todo→doing→review→(done | doing[attempt+1] | blocked)`。`blocked→todo` は、人が `/plan unblock <計画ID> <id> [回答]` で指示した時だけ行える（フックが会話記録で裏付ける）。

`attempt` は「現在の試行回数」。`todo→doing` で 1 になり、`review→doing`（FAIL 後の再試行）で +1 する。上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）。上限に達して FAIL なら `blocked` にする。

`todo→doing` で一度に選べるタスク数（着手可能集合のうち、実際に `doing` へ回す件数）の上限は環境変数 `HARNESS_MAX_PARALLEL`（既定 3。`HARNESS_MAX_ATTEMPTS` と同じ環境変数パターン）。着手可能集合は「`todo` かつ `after` の依存が全て `done`」なタスクの集合で、計画票のタスク表の上から順に並べ、その先頭から `HARNESS_MAX_PARALLEL` 件までを選ぶ。

状態遷移は `scripts/transition.py` で1コマンドで行うのが推奨の経路である。呼び出しの形：

`python3 scripts/transition.py <計画ID> <id>[,<id>...] <遷移先> [--question <文> | --question-file <パス>] [--note <補足>] [--no-model]`

- 許す遷移は todo→doing、doing→doing、doing→review、doing→blocked、review→done、review→doing、review→blocked の7つ。`attempt` は todo→doing で 1、doing→doing・review→doing で +1、それ以外は変えない
- タスク表の status・attempt・question を書き換え、log に遷移行を追記し、計画票と log（done の時は verdict も）だけを `git commit -m "<計画ID>/<id,...>: <旧>→<新>" -- <パス...>` でコミットする。ほかの staged な変更は混ぜない。対象のリポジトリは実行時のカレントディレクトリの `git rev-parse --show-toplevel`
- question の `|` は `／` に、改行は空白に置き換えて表に書く。`--question-file` はファイルの中身を question にする（引用符の問題とガードの誤検知を避けるため）
- 拒否して何も変えない条件（終了コード 1）：遷移表に無い／計画票が approved でない／ブランチが `work/<計画IDの英小文字>` でない／`after` の依存が done でない／`attempt` が上限（`HARNESS_MAX_ATTEMPTS`）を超える／blocked への遷移に question が無い／review→done で PASS の verdict が無い（条件は10節の done の行の verdict の検査と同じ）
- 複数の id は、全部の行で同じ遷移が許される時だけ行う（1つでも拒否があれば何も変えない）。コミットは1回
- 終了コード：0 遷移した／1 前提を満たさず何も変えていない（理由は標準エラー）／2 引数の誤り
- 承認（draft→approved）と blocked の解除（`/plan approve`・`/plan unblock`）は扱わず、今の `/plan` の Edit のまま（10節の裏付けの検査が「HEAD と作業ツリーの比較」で働くため）
- 推奨の経路であって強制ではない。Edit による計画票の直接の書き換えはフックで拒否しない。done の行の verdict の検査（9節・10節）で「PASS の無い done」が残らないことを守る
- 今の `/run`（`.claude/skills/run/SKILL.md`）の手順はまだ `scripts/transition.py` を呼ばない

## 3. ID・ファイル名・ブランチ名

| 種別 | 形式 | 例 |
|---|---|---|
| 計画 ID | `P-YYYYMMDD-<slug>` | `P-20260919-git-ops` |
| タスク ID | 計画スコープの `T-` + 2桁 | `T-01` |
| ブランチ名 | 計画 ID を英小文字にして `work/` を付ける | `work/p-20260919-git-ops` |
| 設計文書 ID | `D-` + 3桁 | `D-001` |

- 計画 ID は日付とスラッグから作るので**採番が要らない**。並行するセッションが同時に計画を作っても衝突しない
- スラッグは英小文字・ハイフン区切り。人が計画を識別できればよく、生成アルゴリズムは規定しない
- タスク ID は計画の中で `T-01` から振る。計画が違えば同じ `T-01` があってよい
- 計画をまたいでタスクを一意に指す時は `<計画ID>/T-01` と書く（verdict の `task` もこの形式）
- 設計文書 ID だけは `vault/designs/` 内の既存の最大値 +1 で採番する。欠番は許容、再利用は禁止
- ディレクトリ・その他ファイルは小文字ケバブケース
- 日時は `YYYY-MM-DD HH:MM`（JST）。取得例：`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'`

## 4. 計画票の形式

計画票（`vault/plans/<計画ID>.md`）は、その計画のゴールと**タスクの状態**を持つ。テンプレートは `vault/templates/plan.md`。

frontmatter は `id` と `status` の2つ。

1行目の `---` から次の `---` の行（無ければ末尾）までを frontmatter として読む。値は前後の引用符を外して読む（例：`status: "approved"` も approved として扱う）。この読み方は `.claude/hooks/_hooklib.py` の `frontmatter_value` にあり、`scripts/current_plan.sh`・`scripts/archive_plans.sh` も同じ規則で読む。

| status | 意味 |
|---|---|
| `draft` | planner が作った直後。人の承認待ちで、まだ着手しない |
| `approved` | 人が承認した。このブランチで進行中の計画 |
| `done` | 全タスクが `done` になり `scripts/vcs_finish.sh` を実行済み |

`done` は **PR 作成済み**という意味で、main へのマージは含まない。マージは人が行い、エージェントは `scripts/vcs_finish.sh`（内部で GitHub なら PR を、GitLab なら MR を作成する。ホスティング無しなら人へのブランチ引き継ぎ案内を出す）までで、`gh pr merge`/`glab mr merge` は実行しない。これは `.claude/settings.json` の `permissions.deny` で機械的に止める（`Bash(gh pr merge*)`・`Bash(glab mr merge*)`）。あわせて `Bash(claude *)` も deny する。エージェントが入れ子で `claude -p "/plan approve ..."` を起動し、子セッションの会話記録に人の発言を偽造して承認の裏付け（10・12節）をすり抜けるのを防ぐため。

本文は `ゴール / 分割方針 / タスク一覧 / 計画の受け入れ基準`。このうち「タスク一覧」の表が状態の正本で、次の形にする。

```markdown
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | ハーネスの動作確認 | |
```

- 列の順序・列名・見出し名は変えない（フックがこの表を解析する）
- タスク表の行は行頭の空白を許す（`_hooklib.py` の `parse_tasks`。3フックが同じ規則で読む）
- `after`：依存タスク ID。未完了なら飛ばす。複数はカンマ区切り。無ければ `-`
- `question`：`blocked` の時に人へ聞くこと（必須）
- `after` が指せるのは同じ計画内のタスクだけ。表が計画ごとに分かれているため、計画をまたぐ依存は書けない

## 5. タスク票（`vault/templates/task.md`）

見出しは `目的 / 入力 / 成果物 / 受け入れ基準 / 決定済み / 進捗` の6つで固定。順序も変えない。

- 受け入れ基準は3〜7行。各行は真偽で判定できる文にし、機械で確認できるものは確認コマンドを併記する
- 受け入れ基準の行数は、「## 受け入れ基準」見出しから次の `## ` 見出しまでで、行頭が `- ` か `数字. ` の行を数える（`_hooklib.py` の `count_criteria`）。stop_gate の verdict 検査（9節）と plan_guard の粒度検査（10節）が同じ数え方を使う
- 進捗は doing 中に作成エージェントが追記する。セッションが切れた時はここから再開する

「成果物」の記法（D-012）：
- creator が変えるファイルはすべて、バッククォートで囲んだリポジトリ相対パスで「成果物」に書く。ディレクトリは末尾を `/` にする（その配下の変更をすべて含む）。自分のタスク票の「進捗」は書かなくてよい。「成果物は1つに特定する」（8節）は変えない（主な成果物を1つに決めたうえで、変えるファイルをすべて列挙する）

差分ゲート `scripts/diff_gate.py`（D-012 フェーズ3）は、作業ブランチの差分が「成果物」の宣言の範囲に収まっているかを調べる。
- 呼び出し：`python3 scripts/diff_gate.py <計画ID> <id> <base> <branch>`。対象のリポジトリは実行時のカレントディレクトリの `git rev-parse --show-toplevel`。リポジトリの状態は変えない
- 差分の取り方：`git diff --name-only --no-renames <base> <branch>`。コミット済みの差分だけを見る（未コミット分は対象外）。リネームは削除と追加の両方として扱う
- タスク票は `git show <base>:vault/tasks/<計画ID>/<id>.md`（base の版）で読む。branch 側で書き足した宣言は効かない（creator が自分で宣言を広げられないようにするため）
- 宣言の読み方：「## 成果物」節のバッククォートで囲まれた文字列をすべて候補にし、末尾が `/` なら前方一致、それ以外は完全一致。パスでない文字列が混じってもよい
- 判定の順（1つのパスに理由は1つ、最初に当たったものを使う）：
  - `vault/plans/`・`vault/log/`・`vault/verdicts/`・`vault/rules/` 配下は宣言があっても違反（理由：`<ディレクトリ> 配下は宣言があっても変更できない`）
  - 自分のタスク票は「## 進捗」以外の節（最初の見出しより前を含む）が変わっていれば違反（理由：`タスク票の「進捗」以外の節が変わっている`）
  - 宣言に一致すれば許す
  - それ以外は違反（理由：`「成果物」に宣言されていない`）
- `.claude/hooks/`・`.claude/settings.json`・`.claude/agents/` は宣言があれば許し、無ければ違反とする（特別扱いしない）
- 出力：違反1件につき `<パス>: <理由>` を1行、標準出力に出す
- 終了コード：0 違反なし／1 違反あり／2 引数の誤り・base にタスク票が無い・git コマンドが失敗した
- `check(root, plan_id, task_id, base, branch)` を import して使える。違反の `(パス, 理由)` のリストを返す
- 今の `/run`（`.claude/skills/run/SKILL.md`）の手順はまだ `scripts/diff_gate.py` を呼ばない

## 6. verdict.json

```json
{
  "task": "P-20260919-git-ops/T-01",
  "attempt": 1,
  "result": "PASS",
  "checked_at": "2026-09-16 10:00",
  "criteria": [
    {"text": "受け入れ基準の1行目", "ok": true, "note": "実行コマンド: `bash scripts/smoke.sh | tail -1` / 出力: smoke: pass=18 fail=0"}
  ],
  "reasons": ["FAIL の理由。PASS なら空配列"]
}
```

- `result` は `PASS` / `FAIL` の2値
- `task` は `<計画ID>/T-01` 形式。verdict 単体でどの計画のタスクかが分かるようにする
- `attempt` は計画票のタスク表の attempt と一致させる。一致しない verdict は「無い」ものとして扱う（古い verdict で done にしない）
- `criteria` は受け入れ基準と同じ行数・同じ順序
- `note` は必須（空にしない）。確認に使ったコマンド（または確認方法）と出力の要点を1〜3行で書く。人が verdict だけを読んで判定の根拠を追えるようにする
  - 書式の例：`実行コマンド: \`<command>\` / 出力: <判定に使った部分の要点>`
  - 確認コマンドが実行できなかった場合（権限拒否・ツール不足など）は、その旨と代替の確認方法、その結果をセットで書く。例：`\`awk ...\` は権限拒否で実行不可。代替として README.md を Read で確認し、使い方節に cron の行が1行あった`
  - 受け入れ基準がルールを根拠にした場合（`vault/rules/` 配下のファイル名や「コーディングルールに従う」等を参照する行）は、参照したルールファイルのパスを `note` に書く
- `reasons` は FAIL の理由だけでなく、次の3つの記録にも使う（`vault/rules/verifier/verifier.md` を根拠とする）。いずれも `result` を FAIL にはしない。
  - 基準が曖昧で判定不能だった場合
  - 基準が緩いと判断した場合（確認コマンドは通るが、タスク票の「目的」の達成を保証しない）
  - 宣言外ファイルの変更を検出した場合（タスク票の「成果物」に書かれていないファイルが変わっていた）

## 7. ログ `vault/log/<計画ID>.md`

計画ごとに1ファイル。追記のみ。1行 = `- YYYY-MM-DD HH:MM T-01 doing→review attempt=1 補足`

ファイル名で計画が特定できるので、行の中のタスク ID は計画スコープの短い形（`T-01`）でよい。計画のブランチ内に閉じるので、並行するセッションの追記と競合しない。

タスクに紐づかない計画単位の行は、タスク ID の位置を `-` にする。`/plan approve` の承認は次の形で1行追記する（承認の根拠の記録）：`- <日時> - draft→approved 人の指示: /plan approve <計画ID>`

blocked の解除（`/plan unblock`）はタスクに紐づくので、タスク ID の位置にその id を書き、次の形で1行追記する（解除の根拠の記録）：`- <日時> <id> blocked→todo 人の指示: /plan unblock <計画ID> <id>`

run の再開情報（creator が作業した worktree のパス・ブランチ名・その時点の計画ブランチの HEAD）は、次の形で1行追記する：`- <日時> <id> worktree path=<パス> branch=<ブランチ名> plan_head=<sha>`（例：`- 2026-09-30 10:15 T-01 worktree path=/path/to/.claude/worktrees/agent-xxxx branch=worktree-agent-xxxx plan_head=<40桁の sha>`）。`plan_head=` の値は `git rev-parse HEAD` の完全な sha とする。この行は状態遷移ではない（`→` を含まない）補足行で、`→` を含む遷移行以外は状態の集計（`model_stats.py` など）に使わない。creator の完了報告の受領直後に、run が1タスク1行ずつ追記する（複数タスクの場合はタスクごとに1行）。再開時に参照するのは、その id の最後の記録行とする。`doing` の中断時の再開の補足は `中断から再開` とする。

実行したモデルの記録：遷移行の補足の先頭に、その遷移を行わせたエージェントのモデルを置く。`doing→review`・`doing→blocked` の行には `creator=<モデル>`、`review→done`・`review→doing`・`review→blocked` の行には `verifier=<モデル>` を付ける。モデルの値は `.claude/agents/<name>.md` の frontmatter の `model` とする。他の補足（理由要約など）が続く場合は、その後ろに空白区切りで書く。記録先は log だけで、verdict.json の形式は変えない。

`scripts/transition.py`（2節）で遷移した時は、log の日時をスクリプトが実行時の JST（UTC+9 固定）で書く。`creator=`・`verifier=` は、対象リポジトリの `.claude/agents/creator.md`・`verifier.md` の frontmatter の `model` からスクリプトが自動で付ける（読めない時は付けない）。`--no-model` を付けると付けない（中断からの再開・ハング・worktree が無い時の行のため）。`--note` の値は、モデルの記録の後ろに補足として書かれる。

- 例（creator）：`- 2026-10-01 10:30 T-01 doing→review attempt=1 creator=sonnet`
- 例（verifier）：`- 2026-10-01 10:40 T-01 review→done attempt=1 verifier=sonnet`

モデルの集計は `scripts/model_stats.py` が行う。引数に渡した log ファイル群（既定は `vault/log/*.md`）を読み、遷移行（`<状態>→<状態>` を含む行）以外は無視する（`worktree path=...` の記録行やハングの補足行も含む）。`vault/archive/` 配下の log は既定の対象に含めず、引数で明示的に渡した時だけ集計する（例：`python3 scripts/model_stats.py vault/archive/*/log/*.md`。log のファイル名が `<計画ID>.md` のまま残るので計画 ID が取れる）。定義は次のとおり：

- 対象タスク：`計画ID/id` の最後の遷移行が `→done` または `→blocked` のもの（計画 ID は log のファイル名から取る）
- 集計キー：そのタスクの `doing→review`・`doing→blocked` 行のうち、`creator=` が付いた最後の行の値。`creator=` が付いていない行は読み飛ばす。`creator=` 付きの行が1つも無いタスクは `unknown` として扱う（エラーにしない）
- 1回目 PASS 率：`review→done attempt=1` で終わった件数 ÷ 対象タスク数
- 平均 attempt：最後の遷移行の `attempt=` の平均
- blocked 率：`→blocked` で終わった件数 ÷ 対象タスク数

出力はタブ区切りで、1行目を見出し `model	tasks	first_pass_rate	avg_attempt	blocked_rate` とし、率は小数2桁で出す。verifier のモデル別の集計は出さない（記録だけ残す）。

## 8. 粒度の基準（planner と人が共有する）

- 受け入れ基準が3〜7行で書ける
- 成果物が1つに特定できる（「〜を改善」は不可）
- 1コンテキストで終わる（目安：人手で1〜2時間相当）
- run で必ず変わるファイル（計画票のタスク表、`vault/log/<計画ID>.md`、タスク票の「進捗」）を「変更していない」と差分で検査する受け入れ基準は書かない。形式の不変を見たい時は見出し行・列構成に限定した確認コマンドにする（例：`git diff -- vault/plans/<計画ID>.md | grep -E '^[+-](## |\| id )'`）
- `vault/rules/`（common・planner）にルールがある場合は、その具体的な基準を受け入れ基準や決定済みに反映する。ただし受け入れ基準3〜7行の上限は優先し、超えそうな場合は要約に留める
- 「受け入れ基準が3〜7行」と「1計画は7タスク以下」は、計画が draft の間、plan_guard フックで機械検査される（詳細は10節）。各基準が「真偽で判定できる文か」は機械では検査されず、planner・verifier の運用に残る

## 9. Stop フックの判定

`.claude/hooks/stop_gate.py` は、自分のブランチの承認済み計画票のタスク表と verdict を読んで判定だけを行い、状態は書き換えない。approved な計画票を1件に特定した直後に、status が done の行それぞれについて、attempt が一致する正しい PASS の verdict があるかを検査する（doing/review の行の検査より前。条件と理由の順は10節の done の行の verdict の検査と同じ）。続いて、doing/review が複数件になりうる前提（2節）のため、doing/review の行それぞれについて下表の判定を行い、いずれか1行でもブロック対象なら停止をブロックする。

| 状況 | 判定 |
|---|---|
| `stop_hook_active` が真 | 許可（`HARNESS_STRICT_STOP=1` なら無視して判定を続ける） |
| 未コミットの変更がある（git の作業ツリーかどうかは `git rev-parse --is-inside-work-tree` で判定し、`.git` がファイルの worktree も対象にする） | ブロック：作業ステップごとにコミットしてから終了する |
| done の行に attempt が一致する正しい PASS の verdict が無い（verdict が無い・JSON として読めない・task / attempt が不一致・result が PASS でない・形式が不正） | ブロック：表の上から最初のその行について、status を review に戻し verifier を実行するよう指示する |
| doing / review のタスクが無い | 許可 |
| verdict が無い、または task / attempt が不一致 | ブロック：verifier を実行して verdict を書く |
| verdict が不正（result が PASS/FAIL 以外、criteria の要素に text/ok/note が無い、criteria の行数がタスク票の受け入れ基準の行数（5節の数え方）と不一致、note が空、reasons が配列でない） | ブロック：何が不正かを示し、verifier を再実行して書き直す |
| FAIL かつ attempt < 上限 | ブロック：doing に戻し attempt を +1 して修正 |
| FAIL かつ attempt ≥ 上限 | ブロック：blocked にし question を書く（既に blocked なら許可） |
| PASS だが status が done でない | ブロック：done にし log に追記 |

## 10. plan_guard フックの判定

`.claude/hooks/plan_guard.py` は PostToolUse（`Write|Edit|MultiEdit|Bash`）で、自分のブランチの計画票のタスク表を検査し、doing/review の集合内に `after` 依存関係が張られている（doing/review のいずれかの行の `after` 列に、まだ `done` でない他の doing/review 行の id が含まれる）・blocked なのに question が空・status が5値以外・id の重複・データ行の列数が6でない、のいずれかならブロックして直し方を示す。計画票が無い場合とデータ行が無い場合は何もしない。

粒度の検査（8節）も plan_guard が行う。契機は、自分のブランチの draft の計画票、またはそのタスク票（`vault/tasks/<計画ID>/<id>.md`）への Write/Edit（`file_path` で判定）のみで、Bash は対象外。
- タスク票：「## 受け入れ基準」見出しから次の `## ` 見出し（または EOF）までの、行頭が `- ` か `数字. ` の行数を数え、3〜7行の範囲外ならブロックして理由（行数と範囲）を示す
- 計画票：タスク表のデータ行が7行を超えるとブロックする（1計画は7タスク以下）
- 計画票の status が draft でなくなった後（approved 以降）は、これらの粒度検査は行わない
- 各基準が「真偽で判定できる文か」は機械では判定できず、planner・verifier の運用に残る

done の行の verdict の検査も plan_guard が行う（D-012 フェーズ1）。自分のブランチの approved な計画票のタスク表で status が done の行それぞれについて、vault/verdicts/<計画ID>/<id>.json があり、JSON として読め、task が <計画ID>/<id>、attempt がタスク表の値と一致し、result が PASS で、形式が正しい（9節の「verdict が不正」の条件に当たらない）ことを、この順に確かめる。満たさない行があれば、表の上から最初の1行についてブロックし、その行の status を review に戻して verifier を実行するよう指示する。この検査は上の段落の検査（列数・status・依存・blocked の question・id の重複）の後に行い、それらのブロック理由が先に出る。検査の本体は .claude/hooks/_hooklib.py の done_rows_without_pass で、Stop フック（9節）と共通。done のタスクの verdict への書き込みは agent_write_guard が拒否する（12節）ため、直す手順は review に戻してから verifier を実行する順になる。draft・done の計画票と vault/archive/ は検査しない。

承認の裏付けの検査も plan_guard が行う（D-010 フェーズ4）。Bash による書き込みは PreToolUse 側では内容を組み立てられず取りこぼすため、その補完として、作業ツリーの計画票（status が approved のもの）を `git show HEAD:<path>` の版と比べ、HEAD では approved でない（HEAD 無し・未追跡を含む）ものを「今回承認された」計画票とみなす。その計画 ID について、会話記録の人の発言に `/plan approve <計画ID>` が無ければブロックし、`git restore vault/plans/<計画ID>.md` で元に戻すよう指示する。会話記録が読めない時（定義は12節）はブロックせず、`additionalContext` で「承認の裏付けを検査できなかった」旨の警告を出す。非 git ディレクトリでは何もしない。同じ承認に何度も当たらないよう、`/plan approve` は承認の直後にコミットする（HEAD が approved になれば対象外）。人の発言の定義・コマンドの一致規則は12節を参照する。

blocked の解除の裏付けの検査も plan_guard が行う（D-010 フェーズ5）。承認と同じ理由で PreToolUse を補完するため、作業ツリーの各計画票のタスク表を `git show HEAD:<path>` の版と比べ、HEAD では status が `blocked` で、作業ツリーでは同じ id の行が `blocked` でないものを「今回解除された」行とみなす（HEAD 無し・未追跡は blocked の行が無い扱い）。その計画 ID・タスク ID について、会話記録の人の発言に `/plan unblock <計画ID> <id>` が無ければブロックし、`git restore vault/plans/<計画ID>.md` で元に戻すよう指示する。会話記録が読めない時（定義は12節）はブロックせず、`additionalContext` で「解除の裏付けを検査できなかった」旨の警告を出す。非 git ディレクトリでは何もしない。同じ解除に何度も当たらないよう、`/plan unblock` は解除の直後にコミットする（HEAD で blocked でなくなれば対象外）。

## 11. ルール（`vault/rules/`）

「ルール」を作成エージェント・verifier・planner に渡す拡張ポイント。ハーネスは planner / creator / verifier の役割定義を標準ルールとして同梱する（`common/roles.md`・`creator/creator.md`・`verifier/verifier.md`・`planner/planner.md`）と、git 運用のルール（`common/git.md`・`creator/git-workflow.md`）。コーディングルール・開発標準・方式設計・テスト標準・テスト観点などドメイン固有のルールは、置き場と読み込み口だけを用意し、インストール先で書く。

### ディレクトリと振り分け
```
vault/rules/
  README.md      # 書き方・振り分けの説明（install.sh が複製）
  common/        # 作成エージェント・verifier・planner の全員に渡す
  creator/       # 作成エージェントだけに渡す
  verifier/      # verifier だけに渡す
  planner/       # planner だけに渡す
```
- 「全員 / 作成のみ / 検証のみ / 計画のみ」の4パターンはディレクトリだけで振り分ける。frontmatter や索引ファイルは持たない
- ファイルは `*.md`、小文字ケバブケース。読み込み順は `common/` → 役割ディレクトリ、各ディレクトリ内はファイル名順（決定的にする）
- 1ファイルは100行以内を目安に、話題ごとに分ける（機械的な強制はしない）
- 雛形は `vault/templates/rule.md`（見出し：目的 / ルール / 確認方法）

### ルールと受け入れ基準の関係
ルールは受け入れ基準を増やすものではなく、**基準の判定方法を与えるもの**。受け入れ基準が `vault/rules/` のルールを参照する時（例：「コーディングルールに従っている」）だけ、verifier はルールを根拠に真偽を判定する。受け入れ基準がルールに触れていなければ、ルールを理由に FAIL にしない。作成側だけに渡した `creator/` のルールは verifier から見えないため、それを根拠に落とすこともない。

### 改ざん防止
`vault/rules/` への書き込みは、タスクの状態や承認済み計画の有無を問わず、フックが常に拒否する（実装は `.claude/hooks/agent_write_guard.py`）。作成エージェントがタスク中にルールを書き換え、verifier の判定基準を自分で緩めることを防ぐ。ルール変更を成果物とするタスクは提案ファイル方式で進める。詳細は「12. agent_write_guard フックの改ざん防止判定」。

## 12. agent_write_guard フックの改ざん防止判定

`.claude/hooks/agent_write_guard.py` は verifier / planner 向けの書き込み先制限（本節冒頭）とは別に、`agent_type` を問わず（メインエージェント含む）適用する判定を持つ。以下のとおり判定する。

| 状況 | 判定 |
|---|---|
| 対象が `vault/rules/` 配下への書き込み（Write/Edit/MultiEdit/NotebookEdit の `file_path`、または Bash のリダイレクト・`tee`・`sed -i`・`rm`/`mv`/`cp` 等） | ブロック：`vault/rules/ へは書き込めません` を reason に含める。タスクの状態（`todo`/`doing`/`review`）・承認済み計画の有無は問わない。解除口は無い |
| 対象が `vault/tasks/<計画ID>/<id>.md` または `vault/verdicts/<計画ID>/<id>.json` で、該当 id の計画票（`vault/plans/<計画ID>.md`）のタスク表上の status が `done`（計画票が無い・読めない・該当 id の行が無い場合はこの判定の対象外。Bash の書き込み動詞が `git add` / `git commit` だけのコマンドも対象外：ステージ・コミットはファイル内容を変えないため。リダイレクト・`cp`/`mv`/`rm`・`sed -i`・`tee`・`git rm` など内容を変える書き込みが混在する場合は対象） | ブロック：`done` のタスク票・verdict は編集できません。agent_type を問わず（メインセッション含む）拒否する。`git add` / `git commit` のみのコマンドが対象外なのは判定範囲の定義であって解除口ではなく、内容を変える書き込みが混在すれば従来どおり拒否する。解除口は無い |
| 対象が `vault/plans/<計画ID>.md` で、Write/Edit/MultiEdit により frontmatter の status を approved 以外（ファイルが無い場合を含む）から approved にする（承認：draft→approved） | メインセッション（`agent_type` が空）かつ会話記録の人の発言に `/plan approve <計画ID>` がある時だけ許可。`agent_type` が空でない（planner・creator 等）、または会話記録が読めたのに該当する発言が無い時はブロック：`/plan approve <計画ID>` で指示した時だけ許可される旨を reason に含める。会話記録が読めない時（定義は下記）はブロックしない（許可。警告は plan_guard が出す：10節） |
| 対象が `~/.claude/projects/` 配下（会話記録。`~` は `os.path.expanduser` で展開して判定する）への書き込み（Write/Edit/MultiEdit/NotebookEdit の `file_path`、または Bash の書き込み対象パス） | ブロック：`~/.claude/projects/ 配下（会話記録）へは書き込めません` を reason に含める。`agent_type`・タスクの状態を問わず、解除口は無い。承認の裏付けが会話記録に依るため、エージェントによる改ざんを防ぐ |
| 対象が `vault/plans/<計画ID>.md` で、Write/Edit/MultiEdit により、書き込み前に status が `blocked` の行が、書き込み後に同じ id の行の status が `blocked` 以外になる（解除：blocked→他。行が消えるだけの場合・書き込み後の内容を組み立てられない場合は対象外） | メインセッション（`agent_type` が空）かつ会話記録の人の発言に `/plan unblock <計画ID> <id>` がある時だけ許可。`agent_type` が空でない、または会話記録が読めたのに該当する発言が無い時はブロック：`/plan unblock <計画ID> <id>` で指示した時だけ許可される旨を reason に含める。会話記録が読めない時（定義は下記）はブロックしない（許可。警告は plan_guard が出す：10節）。1回の書き込みで複数行を解除する場合は、行ごとに一致する発言を要求する |
| 上記に該当しない（`vault/rules/` 以外への書き込み、または `done` でないタスクへの書き込み） | 許可（この判定は素通り。既存の verifier/planner 向け判定へ進む） |

この判定は既存の verifier/planner 向け `ALLOWED` 判定より前に実行される。verifier・planner が `vault/rules/` に書こうとした場合も、この判定で先に拒否される。

**承認の裏付けの判定に使う会話記録**（agent_write_guard.py と plan_guard.py の両方が、フックに渡される `transcript_path` の会話記録（JSONL）を同じ規則で読む。解析は共通モジュール `.claude/hooks/_hooklib.py` の関数を使う。10節はここを参照する）：
- 人の発言：`type` が `user`、`message.content` が文字列、`isMeta` が真でない行だけ。`content` が配列の行（`tool_result` など）と `isMeta` の行は対象外。探す範囲はそのセッションの会話記録全体
- コマンドの一致：人の発言が `<command-name>/plan</command-name>` と、引数が `approve <計画ID>` の `<command-args>` を含む（スラッシュコマンドとして打った場合）か、先頭が `/plan approve <計画ID>` である（文として打った場合）。計画 ID は完全一致で比べる
- 「読めない」：`transcript_path` が無い・ファイルが無い・どの行も JSON として読めない・人の発言が1件も無い、のいずれか。この時はブロックせず許可し、警告に落とす。読めたうえでコマンドが無い時はブロックする
- `unblock` のコマンドの一致：承認と同じ形（スラッシュコマンドの `<command-args>`、または先頭が `/plan` の文）で、引数の先頭3トークンが `unblock <計画ID> <id>` であること。計画 ID・タスク ID は空白区切りのトークンで完全一致を比べ、後ろに回答が続いてよい。1回のコマンドで解除するのは1行だけで、複数行を解除するにはコマンドをその行数だけ打つ。`/run` の遷移（todo→doing→review→done/doing）には blocked から出るものが無いので、この判定に当たるのは `/plan unblock` だけ
- 対象外（今回やらないこと）：自然文での解除、AskUserQuestion への回答での解除、計画票からの行の削除の検査
- 会話記録の形式は Claude Code の公開仕様ではなく、変わりうる。形式の変化は `scripts/smoke.sh` のサンプルで検知する

### 検知範囲：`gh api` / `curl` によるリモート直叩き（issue #6）

Bash 経由の検知は、ローカルの作業ツリーへのリダイレクトやコマンド（`rm`/`mv`/`cp`/`tee`/`sed -i`/`git ...`）だけでなく、`gh api`（`-X` の指定有無を問わない）と、GitHub Contents API を直接叩く `curl`（`api.github.com` / `raw.githubusercontent.com` / `githubusercontent.com` 宛）も対象にする。これらはローカルの作業ツリーに触れずに GitHub 上のファイルを直接書き換えられる経路であり、コマンド文字列に対象パス（`vault/rules/` 配下）が含まれる場合にブロックする。

D-002 の設計思想は「人の操作を前提にしない（エージェントが到達できない経路だけが安全）」ことを理想とするが、この判定は拒否リスト方式（危険な経路をパターンで列挙してブロックする方式）であり、その理想への完全な到達ではない。既知の抜け穴（`gh api`・GitHub API への直接 `curl`）を塞ぐ拡張にとどまり、未知のコマンド経路（例：他の CLI や言語ランタイムから GitHub API を叩く、別のホスト名を使うプロキシ経由など）を完全に列挙することはできないという残存リスクがある。

### Bash の書き込み対象の解析（issue #91・#87）

Bash コマンドの判定は2段になっている。`analyze_bash_writes` が shlex でコマンドをトークン化し、セグメント（`;`・`&&`・`||`・`|`・`&`・引用符外の改行で区切る）ごとに実際の書き込み対象（verb と target の組）を求める。解析できた時はその対象で判定する。書き込み対象は `bash_write_targets` が1回のフック呼び出しで1度だけ計算する（同じコマンドはメモ化）。解析できた時は `analyze_bash_writes` の結果を返す。解析できない時（`analyze_bash_writes` が `None`）は fail-closed とし、書き込み動詞の正規表現に一致した時だけ、4通りの従来判定の候補の和集合（リダイレクト先・`extract_bash_write_targets` の対象・保護対象パスを含む path-like トークン）を返す。保護対象パスは `vault/rules/`・`vault/plans/`・`vault/log/`・`vault/tasks/`・`vault/verdicts/`・`.claude/projects` で、候補の末尾の `)`・`"`・`'`・バッククォート・`;` は落とす。各判定はこの結果をパスで絞り込む。

- 解析の規則：引用符内の文字列・ヒアドキュメント本文・読み取りコマンド（`grep`・`cat`・`git show` 等）の引数は書き込み対象にしない。コマンド語は basename で照合する（`/bin/rm` は `rm`）。先頭の `VAR=値` は読み飛ばす。`2>` のような fd 番号付きのリダイレクト、`>&2` のような fd 複製（宛先がファイルでないもの）は対象にしない
- verb ごとの書き込み対象：リダイレクト（`>`・`>>`・`>|`・`&>`・`&>>`、`>&` の宛先がファイルの時）・`tee`（非フラグ引数）・`sed -i`／`--in-place`（非フラグ引数）・`cp`／`mv`（全ての非フラグ引数と `-t`／`--target-directory` の dir）・`rm`／`mkdir`／`touch`／`chmod`／`chown`（非フラグ引数）・`git add`（パス引数）・`git commit`（対象パスなし）・git の書き込み系サブコマンド（`rm`・`mv`・`checkout`・`switch`・`reset`・`restore`・`clean`・`stash`・`merge`・`rebase`・`push`。パス引数）。書き込みが無ければ空の対象で、書き込み無しとして扱う
- 解析できない形：コマンド置換（`$(`・バッククォート・`<(`・`>(`）、サブシェル（`(`・`)`）、`cd` などの作業ディレクトリ変更（`pushd`・`popd` を含む）、変数・グロブを含む書き込み対象（`$`・`*`・`?`・`[`・`{`）、インタプリタやラッパー（`bash -c`・`sh`・`python3`・`awk`・`perl`・`xargs`・`find`・`env`・`sudo`・`eval`・`source` 等）、シェルの制御構文（`if`・`for`・`while` 等）、`git -C` のような git の前置オプション、本文に `$(` かバッククォートがある展開されるヒアドキュメント（区切り語を引用符で囲んだ `<<'EOF'` は展開されないので解析できる）、閉じていない引用符・区切り語の行が無いヒアドキュメント
- 6つの判定での使い方（`agent_write_guard.py` の `main` の順）：
  - `vault/rules/` 拒否・会話記録（`~/.claude/projects/`）拒否・creator の `vault/plans/`・`vault/log/` 拒否：verb を問わず、`bash_write_targets` の全ての target を、解析の成否にかかわらずそれぞれのパスで絞り込んで判定する。`vault/rules/` 拒否は、解析の成否にかかわらず先に `gh api`／`curl` 経由のリモート直叩きの検査も行う（前小節）
  - done 判定：`git add`・`git commit` の対象を除いた target で判定する（`git add`・`git commit` はファイル内容を変えないため）。解析できない時も、`git add` / `git commit` だけのコマンドを除く判定（issue #84）は残り、それ以外は和集合の全候補で判定する。コマンド置換を含むと解析できず、コミットメッセージ中の done の verdict パスが書き込み対象とみなされて拒否されるため、done 遷移の運用では run/SKILL.md 手順6.3.4 のとおりログ追記・`git add`・`git commit` を別々の Bash 呼び出しに分け、コミットメッセージにコマンド置換を使わない（issue #87）
  - verifier／planner の `ALLOWED` 判定：解析できた時は次の順に判定する。(1) 書き込みが無ければ許可。(2) `git-add`・`git-commit`・`git-write` が1つでもあれば拒否。(3) 全ての target が repo の外なら許可。(4) repo 内の target が `cp`／`mv` だけで、コピー・移動先（従来の抽出で求めた宛先）が全て repo の外なら許可。(5) repo 内の target が全て `redirect`・`mkdir`・`touch` で、`ALLOWED` のパス配下なら許可。いずれにも当たらなければ拒否。解析できない時は和集合の候補で判定する。書き込み動詞が無ければ許可。`extract_bash_write_targets` の対象が1つ以上あり、和集合の全候補が repo の外なら許可。リダイレクト先が1つ以上あり、和集合の全候補が `ALLOWED` 配下で、破壊的な動詞を含まなければ許可。それ以外は拒否
- main 直接コミット拒否：main ブランチ上では、解析できた時は verb `git-commit`（`&&`・`;`・改行で連結した後ろも含む）がある時だけ拒否し、`grep "git commit"` のような読み取り・引用符内・ヒアドキュメント本文は許可する。解析できない時は（和集合の対象外で）今どおり従来の `git commit` の正規表現に加え、`git -C . commit` のような `git -<オプション> … commit` の形も拒否する。非 git リポジトリ・ブランチを取得できない時（detached HEAD 等）はこの判定を素通りする
- 採らなかったこと：`$(cat <<'EOF' …)` の標準形のコミットメッセージを許可する案は採らない。コマンド置換の中身は任意のコマンドを実行でき、許可の形を作るとすり抜けを作りやすいため。コミットの起点を記録する欄も採らない
- 一本化で変わった点（D-011 フェーズ3）：
  - verifier・planner の解析できない形のコマンドで、repo の外だけに書き込むのに引数・引用符の中に保護対象パスがあるもの（例：`python3 -c "open('vault/tasks/P/T-01.md')" > /tmp/x.txt`）：変更前は許可→変更後は拒否（和集合に repo 内の path-like 候補が入るため）
  - 変わったのは拒否する側だけで、許可が増えた形は無い
- 残る弱点：拒否リスト方式であることは変わらない。`ln`・`dd of=`・`rsync` などの書き込みは従来どおり検出しない。`cp`・`mv` は全ての非フラグ引数を対象にするため、読み取り元に `vault/rules/` を置く `cp vault/rules/x /tmp/` のようなコマンドは誤検知として拒否される（人の回答による判断）。解析できない時の候補には `cd vault/rules/ && ...`（末尾の `/`）や `F=vault/rules/...; ... $F` を取りこぼす既知の穴があり、今回は直していない

**フックの共通モジュール**（`.claude/hooks/_hooklib.py`）：3フックで共通に使う関数（worktree 委譲・計画票の frontmatter（`frontmatter_value`）とタスク表（`parse_tasks`）とタスク票の受け入れ基準の行数（`count_criteria`）の読み取り・会話記録の人の発言とコマンドの一致判定）を置く。各フックは、自分のファイルと同じディレクトリ（`__file__` 起点）を `sys.path` の先頭に入れて import し、worktree への委譲先ではその worktree の版を読む。import する前に `sys.dont_write_bytecode = True` にして `__pycache__` を作らない。読み込みに失敗したら、標準エラーに理由を書いて終了コード2で終わる（PreToolUse ではブロック扱い。委譲先なら委譲元の判定にフォールバックする）。Stop フックだけは、`stop_hook_active` が真で `HARNESS_STRICT_STOP` が `1` でなければ0で終わる。Bash の書き込み解析（`analyze_bash_writes` など）は `agent_write_guard.py` だけが使うので、共通モジュールに置かない。

### 提案ファイル方式（ルール自体を変更するタスク用）

エージェントは `vault/rules/` に一切書き込めない（人だけが実体を編集できる）。ルールファイルそのものを成果物とするタスクは、次の手順で進める。

- タスク票の「成果物」は実パス（`vault/rules/...`）ではなく `vault/tasks/<計画ID>/<id>-proposal.md` にする。中身は追記・変更したい内容の下書き（差分でも全文でもよい）
- verifier は実体ではなく、この提案ファイルの内容を受け入れ基準に照らして検証する
- 提案ファイルから実体（`vault/rules/` 配下）への反映は、人が手作業で行う。反映を自動化するスクリプト・スキルは無い
- 複数のルールファイルにまたがる変更は、成果物を1つに保つ原則（`vault/templates/task.md`）に従ってタスクを分割する

この方式は `todo`/`doing`/`review` のどの状態でも同じで、ローカル・リモートいずれのセッションでも人の起動時操作（環境変数など）を必要としない。

## 13. 設計文書（`vault/designs/`）

大きなゴールを `/plan` に渡す前に、調査と人への質問を済ませて決定事項を固めるための文書。`/design` スキルが `vault/designs/D-001.md` に書く。テンプレートは `vault/templates/design.md`。

### ID と採番
- `D-` + 3桁（`D-001`）。採番は `vault/designs/` 内の既存ファイルの最大値 +1。タスク・計画とは独立した系列
- frontmatter は `id` のみ。`status` は持たない。設計文書は一度提示して終わる読み物であり、5状態遷移の対象ではない

### 形式
本文は「決定事項」（人に聞いて確定した回答）と、フェーズごとの4点セットの繰り返しで構成する。4点セットの見出しは以下に固定する。

| 見出し | 内容 |
|---|---|
| ゴール文 | `/plan` にそのまま貼れる自然文。1フェーズ分のゴール |
| 受け入れ基準の候補 | planner が受け入れ基準に起こす叩き台。3〜7行 |
| 決定済み | 作成エージェントが聞きそうなことへの先回りの回答 |
| 依存 | 先に終えているべきフェーズ |

「受け入れ基準の候補」は、そのフェーズだけが単体で `main` にマージされてもシステムが動作する状態を保証する内容にする。フェーズは `/plan` によって1本の PR として `main` に単体マージされる実行単位であり、他フェーズの実装を前提にしないと動作しない基準は書かない。

### ブランチと PR
- `/design` は `main` から `git checkout -b design/d-xxx`（`xxx` は D-ID の3桁を小文字化したもの。例：D-002 → `design/d-002`）でブランチを切り、設計文書をそのブランチ上でコミットする（`main` 上では `agent_write_guard.py` が `git commit` を拒否するため）
- 設計文書は全フェーズ分を一括で1回の PR で `main` にマージする（フェーズ単位で分割マージしない）。`scripts/vcs_finish.sh` を実行して PR/MR を作り（ホスティング無しの場合は案内を受け取り）、人がレビューして `main` へマージする（`/plan` の `run` が最後に作る PR と同じ運用。`gh pr merge`/`glab mr merge` はエージェントが実行しない。マージは人が行う）
- マージのタイミングはフェーズ1の実装着手前。人が PR をレビュー・マージしてから、フェーズ1のゴール文を `/plan` に渡す

### `/plan` との関係
- `/design` は planner サブエージェントを呼ばない。設計文書を書いて提示し、そこで止まる
- 人が設計文書を確認してから、フェーズのゴール文を1つずつ `/plan` に渡す
- この時点で設計文書は `main` にマージ済みなので、`/plan` は既存の手順どおり「現在のブランチが `main` であることを確認してから `work/...` を切る」を変えずに使える
- 使うのは、受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる時だけ。小さい要求は `/plan` に直行する
