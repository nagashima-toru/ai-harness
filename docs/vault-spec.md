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
| `vault/harness-improvements/<計画ID>.md` | run の振り返り（`.claude/skills/run/SKILL.md` 手順8）で issue の起票に失敗した時の改善提案。提案に対応した計画が、その計画の中で削除する。5状態遷移の対象ではない |
| `vault/rules/` | 作成エージェント・verifier・planner に渡すルール（「ルール（`vault/rules/`）」の節を見る） |
| `vault/archive/<年-月>/{plans,tasks,verdicts,log}/` | done かつ PR がマージ済みの計画一式の移動先（`vault/` と同じ種別ごとのサブディレクトリ。詳細は表の後の段落）。参照用で、消しても運用に影響しない |

archive への移動は人が `scripts/archive_plans.sh --apply` で行う（手順は `docs/runbook.md` 5節）。エージェントは `--list`・`--dry-run` だけを使う。計画票が `status: done`・タスク表が全行 `done`・`main` でも `status: done`（マージ済み）・log に日時行がある計画を候補にし、新しい順に --keep（既定5）件を残す。それより古い全部を移す。現在のブランチの計画は候補に入れず、5件に数えない。「新しい」の基準は log の最初の日時行（`- YYYY-MM-DD HH:MM ` で始まる最初の行）の日時で、同じなら計画 ID の文字列順で後ろのものを新しいとみなす。`<年-月>` は計画 ID の日付部分から決める。移した後のファイルは agent_write_guard.py の done 判定の対象外になる（フックは `vault/tasks/`・`vault/verdicts/` だけを見る）。`vault/archive/` 配下はいざという時の参照用で、編集のチェックは不要。

計画をまたぐキューは持たない。**1セッション = 1計画 = 1ブランチ**で、計画の作成から実行・PR までを1本のブランチに閉じる。状態ファイルが計画ごとに分かれるので、複数のエージェントセッションが別々の計画を同時に進めても競合しない。

「自分のブランチの計画票」は `vault/plans/*.md` を走査し、frontmatter の `status` が `approved` のものを取る。2つ以上 `approved` があるのは異常（1ブランチ1計画の不変条件）。
実際にこの走査を行うスクリプトが `scripts/current_plan.sh`（`vault/plans/*.md` の frontmatter のみを見て、approved な計画票の計画 ID を1行1件で出力する）。

証跡は3層で残る（計画ブランチの中の証跡。マージ後は PR の本文とコミット履歴から辿る）。`vault/log/<計画ID>.md`（状態遷移）・`vault/verdicts/<計画ID>/T-01.json`（判定の根拠）・git の履歴（タスクごとの状態のコミット（transition.py の `<計画ID>/<id,...>: <旧>→<新>`）・worktree 側の収集コミット（`<計画ID>/<id>: creator 成果物をオーケストレーターが収集`）・計画ブランチへの `--no-ff` のマージコミット（`<計画ID>/<id>: マージ`））と、オーケストレーターが `bash scripts/vcs_finish.sh` で作る PR。どれも計画のブランチ内に閉じるので、セッション間で競合しない。

計画一式4種（`vault/plans/<計画ID>.md`・`vault/tasks/<計画ID>/`・`vault/verdicts/<計画ID>/`・`vault/log/<計画ID>.md`）は、run の手順7で PR を作る直前に除去し、`main` には入れない。除去は `bash scripts/purge_plan.sh [--dry-run] <計画ID>` で行う。条件は、ブランチが `work/<計画IDの英小文字>`・計画票が `status: done`・タスク表が1行以上で全行 `done`・対象パスに未コミットの変更が無いこと。存在しないパスは飛ばす。`--dry-run` は消す予定のパスを1行1件で出し、何も変えない。終了コードは 0（消した／dry-run で出した）・1（条件を満たさない、または `git rm` の失敗）・2（引数の誤り、git リポジトリの外）。スクリプトはコミットしない（オーケストレーターが `<計画ID>: 計画一式を除去` でコミットする）。`vault/harness-improvements/<ファイル名>` は除去の対象外。

証跡は PR に残る。PR 本文に計画のゴール・タスク表・log の全行・verifier の指摘が写り、タスク票と verdict の中身は PR のコミット履歴から辿る。残すべき情報は、除去の前に docs への追記か Issue 化で取り出す（取り出した結果は PR 本文の `## 取り出した情報` に載る）。

引数なしの `scripts/vcs_finish.sh` は、現在のブランチ（`work/<計画IDの英小文字>`）の計画が見つかれば、PR/MR のタイトルを `<計画ID>: <ゴールの1行目>`、本文を `scripts/pr_body.py` が出す「タスク履歴」表（タスク ID・title・`<計画ID>/<id>: done`（従来の run）か `<計画ID>/<id>: review→done`（transition.py。複数 id の `<計画ID>/T-01,T-02: review→done` も含む）のコミットの短縮ハッシュ・verdict）にする。PR がスカッシュマージされて main にタスクごとのコミットが残らなくても、この表から辿れる。マージ方式の運用は `docs/runbook.md` 3節を参照。

環境変数 `HARNESS_PR_BODY_FILE`（本文のファイルのパス）が空でない値で設定されていて、引数が無い時だけ、上の「タスク履歴」表の代わりにそのファイルの中身を本文にする。引数がある時は見ない。GitHub は `gh api -X POST repos/<owner>/<repo>/pulls -f title=<タイトル> -f head=<ブランチ> -f base=main -F body=@<パス> --jq .html_url`（REST）を呼ぶ。owner/repo は origin の URL の最後の2つの区切りから取り、取れなければ push の前に終了コード2で終わる。作った PR の URL は標準出力に出す。base は `main` 固定。引数なしで計画が見つからない時は、最新コミットの件名と本文でタイトルと本文を作る。引数がある時は `gh pr create` にそのまま渡す。GitLab は `glab mr create --title <タイトル> --description <ファイルの中身> --yes` を呼ぶ。タイトルは `HARNESS_PR_TITLE`（未設定か空なら計画 ID、計画が見つからなければ現在のブランチ名）で、この経路でだけ使う。ファイルが読めない時は push の前に標準エラーへ出して終了コード2で終わる（ホスティング無しの経路では検査しない）。run は全タスクが done になった後、この経路で本文（計画 ID の1行・`scripts/pr_body.py` の出力・`## verifier の指摘`・`scripts/plan_record.py` の出力・`## 取り出した情報` の順）を渡す（6節・7節）。

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

遷移：`todo→doing→review→(done | doing[attempt+1] | blocked)`。`blocked→todo` は、人が `/plan unblock <計画ID> <id> [回答]` で指示した時だけ行う。フックでは確かめない（D-015 フェーズ2 で廃止）ので、エージェントは人の指示なしに解除しない。

`attempt` は「現在の試行回数」。`todo→doing` で 1 になり、`review→doing`（FAIL 後の再試行）で +1 する。上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）。上限に達して FAIL なら `blocked` にする。

`todo→doing` で一度に選べるタスク数（着手可能集合のうち、実際に `doing` へ回す件数）の上限は環境変数 `HARNESS_MAX_PARALLEL`（既定 3。`HARNESS_MAX_ATTEMPTS` と同じ環境変数パターン）。着手可能集合は「`todo` かつ `after` の依存が全て `done`」なタスクの集合で、計画票のタスク表の上から順に並べ、その先頭から `HARNESS_MAX_PARALLEL` 件までを選ぶ。

状態遷移は `scripts/transition.py` で1コマンドで行うのが推奨の経路である。呼び出しの形：

`python3 scripts/transition.py <計画ID> <id>[,<id>...] <遷移先> [--question <文> | --question-file <パス>] [--note <補足>] [--no-model]`

- 許す遷移は todo→doing、doing→doing、doing→review、doing→blocked、review→done、review→doing、review→blocked の7つ。`attempt` は todo→doing で 1、doing→doing・review→doing で +1、それ以外は変えない
- タスク表の status・attempt・question を書き換え、log に遷移行を追記し、計画票と log（done の時は verdict も）だけを `git commit -m "<計画ID>/<id,...>: <旧>→<新>" -- <パス...>` でコミットする。ほかの staged な変更は混ぜない。対象のリポジトリは実行時のカレントディレクトリの `git rev-parse --show-toplevel`
- question の `|` は `／` に、改行は空白に置き換えて表に書く。`--question-file` はファイルの中身を question にする（引用符の問題とガードの誤検知を避けるため）
- 拒否して何も変えない条件（終了コード 1）：遷移表に無い／計画票が approved でない／ブランチが `work/<計画IDの英小文字>` でない／`after` の依存が done でない／`attempt` が上限（`HARNESS_MAX_ATTEMPTS`）を超える／blocked への遷移に question が無い／review→done で PASS の verdict が無い（条件は10節の done の行の verdict の検査と同じ）
- 複数の id は、全部の行で同じ遷移が許される時だけ行う（1つでも拒否があれば何も変えない）。コミットは1回
- worktree 運用（フェーズ4）：creator が作業した worktree を渡すと、review・done・doing・blocked の前後の git 操作まで1コマンドで行う。呼び出しの形：`python3 scripts/transition.py <計画ID> <id> <review|done|doing|blocked> --worktree <パス> --branch <ブランチ> [--plan-head <sha>]`。`--plan-head` は review・done・blocked で必須、doing では使わない。id は1つだけ。`--worktree` と `--branch` はそろって使う。`--worktree` を渡さない呼び出しは今の（フェーズ2の）動きのまま
- worktree とブランチの検証は `scripts/discard_worktree.sh` と同じ条件：ブランチ名が `worktree-agent-` で始まる、`git worktree list --porcelain` にそのパスが登録済み、登録されたブランチが一致（パスは realpath で比べる）。`--plan-head` は40桁の sha に解決できること。満たさなければ何も変えず終了コード 1
- review（doing→review）：(1) worktree に未コミット分があれば `git add -A` して `<計画ID>/<id>: creator 成果物をオーケストレーターが収集` でコミットする。(2) 新規コミットの判定：`git rev-list <plan-head>..<branch>` が0件なら doing→blocked にして worktree を残す。(3) 差分ゲート（5節。`diff_gate.check`、base は plan-head）。(4) 違反なしなら、log に再開情報の記録行（7節）と doing→review の行を書いてコミットする。違反ありなら差し戻し：attempt+1 が上限（`HARNESS_MAX_ATTEMPTS`）以内なら、タスク票の「進捗」に `- 差し戻し（attempt=<n>）: 宣言外の変更 <パス>, ...` を足し、doing のまま attempt+1 にして worktree とブランチを破棄する。上限を超えるなら doing→blocked にして worktree を残す
- done（review→done）：PASS の verdict を確認し（条件は10節の done の行の検査と同じ）、worktree の未コミット・未追跡分は収集しない（マージに入れない）。新規コミットの判定（0件なら review→blocked）→ 差分ゲート（違反なら review→blocked。タスク票の「進捗」には書かない）→ メインの作業ツリーで `git merge --no-ff <branch> -m "<計画ID>/<id>: マージ"` → フェーズ2と同じ review→done（計画票・log・verdict をコミット）→ `git worktree remove --force` と `git branch -d` で後始末（失敗は警告だけで終了コード 0）。マージが衝突したら `git diff --name-only --diff-filter=U` で衝突ファイルを取り、`git merge --abort` で中止して review→blocked にする（question に衝突ファイル。worktree とブランチは残す）
- doing（review→doing。verifier の FAIL の再試行。review からだけ）：verdict が JSON として読め、task・attempt が一致し、result が FAIL の時だけ行う。attempt+1 が上限以内なら review→doing にして worktree とブランチを破棄する。log の補足は reasons の先頭1件を80文字で切ったもの。上限を超えるなら、reasons を `／` でつないで200文字で切ったものを question にして review→blocked にし、worktree を残す
- blocked（doing→blocked。creator の blocked の報告。doing からだけ）：`--question` か `--question-file` が必須。再開情報の記録行（7節）と doing→blocked の行を書いてコミットし、worktree は残す。worktree の中身には触れない（収集・差分ゲートはしない）
- 終了コード：0 遷移した（worktree 運用では review/done にした）／1 前提を満たさず何も変えていない（理由は標準エラー）／2 引数の誤り／3 差し戻した（doing→doing・review→doing。creator を呼び直す）／4 blocked にした。終了コード 3・4 の時は、何をしたかを標準出力に1行で出す（run が完了報告に写せるように）
- 承認（draft→approved。`/plan` の自動承認）と blocked の解除（`/plan unblock`）は扱わず、`/plan` の Edit のまま
- 推奨の経路であって強制ではない。Edit による計画票の直接の書き換えはフックで拒否しない。done の行の verdict の検査（9節・10節）で「PASS の無い done」が残らないことを守る
- `/run`（`.claude/skills/run/SKILL.md`）は、計画票のタスク表と log の変更をすべて `scripts/transition.py` で行う。場面と遷移先の対応：着手は複数 id の todo→doing、creator の完了後は `--worktree` の review、creator の blocked 報告と分岐元の不一致は `--worktree` の blocked、PASS は `--worktree` の done、FAIL は `--worktree` の doing、中断からの再開・ハング・worktree が無い時は `--no-model --note` の doing・blocked。呼び出しの形の早見表は run/SKILL.md にある。例外として、計画票の frontmatter の approved→done（手順7）は Edit で行い、その後 `git add vault/plans/<計画ID>.md` と名前を指定した `git commit` でコミットしてから `scripts/vcs_finish.sh` を呼び（`vcs_finish.sh` は計画票の変更をコミットしないため）、計画一式の除去（`scripts/purge_plan.sh` の `git rm` と除去のコミット）も transition.py を通さない例外で、承認・blocked の解除は `/plan` の Edit のまま

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
| `draft` | planner が書いている間。粒度の検査（8節・10節）の対象で、まだ着手しない |
| `approved` | `/plan` が粒度の確認を通した後に自動で承認した。このブランチで進行中の計画 |
| `done` | 全タスクが `done` になり、計画一式を除去して `scripts/vcs_finish.sh` を実行済み |

done にした計画票は除去のコミットで消えるため計画ブランチの履歴にだけ残る（`main` にある done の計画票はこの方式より前のもの）。

`done` は **PR 作成済み**という意味で、main へのマージは含まない。マージは人が行い、エージェントは `scripts/vcs_finish.sh`（内部で GitHub なら PR を、GitLab なら MR を作成する。ホスティング無しなら人へのブランチ引き継ぎ案内を出す）までで、`gh pr merge`/`glab mr merge` は実行しない。これは `.claude/settings.json` の `permissions.deny` で機械的に止める（`Bash(gh pr merge*)`・`Bash(glab mr merge*)`）。

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
  - `vault/plans/`・`vault/log/`・`vault/verdicts/` 配下は宣言があっても違反（理由：`<ディレクトリ> 配下は宣言があっても変更できない`）
  - 自分のタスク票は「## 進捗」以外の節（最初の見出しより前を含む）が変わっていれば違反（理由：`タスク票の「進捗」以外の節が変わっている`）
  - 宣言に一致すれば許す
  - それ以外は違反（理由：`「成果物」に宣言されていない`）
- `.claude/hooks/`・`.claude/settings.json`・`.claude/agents/` は宣言があれば許し、無ければ違反とする（特別扱いしない）
- `vault/rules/` 配下も特別扱いせず、宣言があれば許し、無ければ違反とする（D-015 で保護をやめたため）
- 出力：違反1件につき `<パス>: <理由>` を1行、標準出力に出す
- 終了コード：0 違反なし／1 違反あり／2 引数の誤り・base にタスク票が無い・git コマンドが失敗した
- `check(root, plan_id, task_id, base, branch)` を import して使える。違反の `(パス, 理由)` のリストを返す
- `scripts/transition.py` の worktree 運用（2節）が `scripts/diff_gate.py` を import して `check` を使う。`/run` は手順4（review）と手順6（done）で transition.py を通して差分ゲートを使う

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
- `reasons` は FAIL の理由だけでなく、次の2つの記録にも使う（`.claude/agents/verifier.md` を根拠とする）。いずれも `result` を FAIL にはしない。
  - 基準が曖昧で判定不能だった場合
  - 基準が緩いと判断した場合（確認コマンドは通るが、タスク票の「目的」の達成を保証しない）

`reasons` の使われ方：`reasons` は言い換えず、分類しない。`scripts/verdict_notes.py <計画ID> [--dir <ディレクトリ>]` が、計画の verdict のうち `reasons` が空でないものを要素ごとに `<id>: <reason>` の1行で標準出力に出す（`<id>` はファイル名から `.json` を除いたもの、ファイル名順、要素内の改行は空白1つにする）。出す行が無ければ `指摘なし` の1行だけを出す。読み込み先は既定で `vault/verdicts/<計画ID>/` の `*.json` で、`--dir` を渡すとそのディレクトリ（`<id>.json` を直接持つ。archive など）を読み、計画 ID は使わない。JSON として読めない・`reasons` が無い／配列でない verdict は読み飛ばし、標準エラーに出す。ファイルには書き込まない。終了コードは 0（出力した。「指摘なし」を含む）・1（読み込み先のディレクトリが無い）・2（引数の誤り）。run の手順7（全タスクが done になった後）で、この出力を PR 本文の「verifier の指摘」節と完了報告に入れる（本文は `HARNESS_PR_BODY_FILE` で `scripts/vcs_finish.sh` に渡す。1節）。また `model_stats.py` の指摘あり率（7節）の元になる。

## 7. ログ `vault/log/<計画ID>.md`

計画ごとに1ファイル。追記のみ。1行 = `- YYYY-MM-DD HH:MM T-01 doing→review attempt=1 補足`

ファイル名で計画が特定できるので、行の中のタスク ID は計画スコープの短い形（`T-01`）でよい。計画のブランチ内に閉じるので、並行するセッションの追記と競合しない。

タスクに紐づかない計画単位の行は、タスク ID の位置を `-` にする。`/plan` の自動承認は次の形で1行追記する：`- <日時> - draft→approved /plan による自動承認`。D-015 フェーズ2 より前の承認の行（補足が `人の指示:` で始まるもの）は書き換えない

blocked の解除（`/plan unblock`）はタスクに紐づくので、タスク ID の位置にその id を書き、次の形で1行追記する（解除の根拠の記録）：`- <日時> <id> blocked→todo 人の指示: /plan unblock <計画ID> <id>`

run の再開情報（creator が作業した worktree のパス・ブランチ名・その時点の計画ブランチの HEAD）は、次の形で1行追記する：`- <日時> <id> worktree path=<パス> branch=<ブランチ名> plan_head=<sha>`（例：`- 2026-09-30 10:15 T-01 worktree path=/path/to/.claude/worktrees/agent-xxxx branch=worktree-agent-xxxx plan_head=<40桁の sha>`）。`plan_head=` の値は `git rev-parse HEAD` の完全な sha とする。この行は状態遷移ではない（`→` を含まない）補足行で、`→` を含む遷移行以外は状態の集計（`model_stats.py` など）に使わない。creator の完了後に run が transition.py の review・blocked（`--worktree` 付き）を呼ぶと、transition.py が1タスク1行ずつ書く。再開時に参照するのは、その id の最後の記録行とする。`doing` の中断時の再開の補足は `中断から再開` とする。

再開・ハング・worktree が無い時の遷移行は、run が transition.py を `--no-model --note "<補足>"` で呼んで書く。補足は `中断から再開`・`中断が上限に達した`・`worktree が無いため作り直し`・`worktree が無いため`・`creator呼び出しハングにより再試行`・`creator呼び出しハング`・`verifier呼び出しハング` のいずれか。

`scripts/transition.py` の worktree 運用（2節）が書く行：再開情報の記録行は、review・blocked の時に transition.py が遷移の行の直前に、同じ日時で書く（run が別に追記する必要は無い）。差し戻しの行は `- <日時> <id> doing→doing attempt=<n+1> 宣言外の変更: <パス>, ...` で、モデル（`creator=`・`verifier=`）を付けない。done の前に blocked にした時の補足は `新規コミット無し`・`宣言外の変更: <パス>, ...`・`マージコンフリクト` のいずれか。

実行したモデルの記録：遷移行の補足の先頭に、その遷移を行わせたエージェントのモデルを置く。`doing→review`・`doing→blocked` の行には `creator=<モデル>`、`review→done`・`review→doing`・`review→blocked` の行には `verifier=<モデル>` を付ける。`verifier=` の値は `.claude/agents/verifier.md` の frontmatter の `model` とする。`creator=` の値は、環境変数 `HARNESS_CREATOR_MODEL` が空でなければその値、無ければ `.claude/agents/creator.md` の frontmatter の `model` とする（詳細は次の段落）。他の補足（理由要約など）が続く場合は、その後ろに空白区切りで書く。記録先は log だけで、verdict.json の形式は変えない。

`scripts/transition.py`（2節）で遷移した時は、log の日時をスクリプトが実行時の JST（UTC+9 固定）で書く。`creator=`・`verifier=` はスクリプトが自動で付ける（値が取れない時は付けない）。`creator=` の値は環境変数 `HARNESS_CREATOR_MODEL`（空白を除いて空でなければ）の値を優先し、無ければ対象リポジトリの `.claude/agents/creator.md` の frontmatter の `model` とする。`verifier=` の値は環境変数の影響を受けず、常に `.claude/agents/verifier.md` の frontmatter の `model` とする。`--no-model` を付けると（環境変数の有無にかかわらず）どちらも付けない（中断からの再開・ハング・worktree が無い時の行のため）。`--note` の値は、モデルの記録の後ろに補足として書かれる。

- 例（creator）：`- 2026-10-01 10:30 T-01 doing→review attempt=1 creator=sonnet`
- 例（verifier）：`- 2026-10-01 10:40 T-01 review→done attempt=1 verifier=sonnet`

log の全行は `scripts/plan_record.py` が PR 本文に写す。使い方は `python3 scripts/plan_record.py <計画ID>`。出力は `## 計画の記録` の下に `### ゴール`・`### タスク表`・`### log` を順に並べ、log は `<details>` で畳む。ファイルには書き込まない。終了コードは 0（出力した）・1（計画票か log が無い）・2（引数の誤り）。log は除去されて `main` に残らないので、`scripts/model_stats.py` の既定（`vault/log/*.md`）で計画をまたいで集計できるのは計画ブランチの中と除去より前の分だけで、除去後の集計は PR 本文の log から人が行う。

モデルの集計は `scripts/model_stats.py` が行う。引数に渡した log ファイル群（既定は `vault/log/*.md`）を読み、遷移行（`<状態>→<状態>` を含む行）以外は無視する（`worktree path=...` の記録行やハングの補足行も含む）。`vault/archive/` 配下の log は既定の対象に含めず、引数で明示的に渡した時だけ集計する（例：`python3 scripts/model_stats.py vault/archive/*/log/*.md`。log のファイル名が `<計画ID>.md` のまま残るので計画 ID が取れる）。定義は次のとおり：

- 対象タスク：`計画ID/id` の最後の遷移行が `→done` または `→blocked` のもの（計画 ID は log のファイル名から取る）
- 集計キー：そのタスクの `doing→review`・`doing→blocked` 行のうち、`creator=` が付いた最後の行の値。`creator=` が付いていない行は読み飛ばす。`creator=` 付きの行が1つも無いタスクは `unknown` として扱う（エラーにしない）
- 1回目 PASS 率：`review→done attempt=1` で終わった件数 ÷ 対象タスク数
- 平均 attempt：最後の遷移行の `attempt=` の平均
- blocked 率：`→blocked` で終わった件数 ÷ 対象タスク数
- 指摘あり率（`noted_rate`）：対象タスクのうち、verdict の `reasons` が空でない配列のタスクの件数 ÷ 対象タスク数（分母は `tasks` 列と同じ）。verdict の場所は log のパスから決める：log が `<base>/log/<計画ID>.md` なら `<base>/verdicts/<計画ID>/<id>.json`（archive の log も同じ規則）。log の親ディレクトリ名が `log` でない時、verdict が無い・JSON として読めない・`reasons` が無い／配列でない／空のタスクは、指摘なしとして数える（エラーにしない）。verdict の `task`・`attempt`・`result` は見ない

出力はタブ区切りで、1行目を見出し `model	tasks	first_pass_rate	avg_attempt	blocked_rate	noted_rate` とし、率は小数2桁で出す。verifier のモデル別の集計は出さない（記録だけ残す）。

実際に使われたモデルとトークン量の集計は `scripts/usage_stats.py` が行う。会話記録（JSONL）の Agent 呼び出し結果から agent×model の使用量を集計し、標準出力にタブ区切りで出す。会話記録の形式は公開仕様ではない（12節の扱いと同じ）ので、形式が変わっていないかは smoke のサンプルで検知する。`usage_stats.py` は会話記録・vault のどちらにも書かず、読むだけである。

- 使い方：`python3 scripts/usage_stats.py [--plan <計画ID>] [ファイルかディレクトリ ...]`。ファイルの引数はそのファイルを、ディレクトリの引数はその直下の `*.jsonl` を読む（下位のディレクトリは見ない）。`--plan` を付けると、`toolUseResult` の `prompt` から `P-\d{8}-[a-z0-9-]+/T-\d{2}` で最初に一致したものの `/` より前が計画 ID と一致する呼び出しだけを数える（一致が取れない呼び出しは数えない）
- 既定の読み込み先：引数が無ければ `~/.claude/projects/<プロジェクトの絶対パスの英数字以外をすべて - に置き換えたもの>/*.jsonl`。プロジェクトの絶対パスはスクリプトの2つ上のディレクトリ（realpath にしない）、`~` は `HOME` で決める。既定の読み込み先のディレクトリが無ければ見出し行だけを出して終了コード0
- 読む項目：各行を JSON として読み、`toolUseResult` が辞書で、`agentType`（文字列）・`resolvedModel`（文字列）・`totalTokens`（数）・`totalDurationMs`（数）・`totalToolUseCount`（数）がそろっているものを1回の呼び出しとして数える（bool は数として扱わない）。この5つが必須のキーで、`prompt`（文字列）は `--plan` の時だけ使う
- 読み飛ばす行：JSON でない行・空行・`toolUseResult` が無い／辞書でない行・必須のキーが欠けている／型が違う行は、黙って読み飛ばす
- `agentId` の重複：`toolUseResult` に文字列の `agentId` があれば、同じ `agentId` は全ファイルを通して最初の1回だけ数える。`agentId` が無い呼び出しは毎回数える
- `resolvedModel` は完全なモデル ID（例：`claude-sonnet-5`）で、変換せずそのまま出す。log の `creator=` の alias（例：`sonnet`）とは表記が違う

出力はタブ区切りで、1行目を見出し `agent	model	calls	tokens_total	tokens_avg	duration_avg_s	tool_uses_avg` とし、2行目以降は `agent`、次に `model` の昇順に並べる。数える呼び出しが0件なら見出し行だけを出す。各列の定義は次のとおり：

- `agent`：`agentType`
- `model`：`resolvedModel`
- `calls`：呼び出し回数
- `tokens_total`：`totalTokens` の合計（整数）
- `tokens_avg`：`tokens_total` ÷ `calls`（小数1桁）
- `duration_avg_s`：`totalDurationMs` の平均を秒にしたもの（小数1桁）
- `tool_uses_avg`：`totalToolUseCount` の平均（小数1桁）

終了コードは 0（出力した。0件を含む）・1（引数のパスが存在しない。標準エラーに `usage_stats.py: 見つかりません: <パス>` を出し、何も出力しない）・2（引数の誤り。argparse の既定）。

## 8. 粒度の基準（planner と人が共有する）

- 受け入れ基準が3〜7行で書ける
- 成果物が1つに特定できる（「〜を改善」は不可）
- 1コンテキストで終わる（目安：人手で1〜2時間相当）
- run で必ず変わるファイル（計画票のタスク表、`vault/log/<計画ID>.md`、タスク票の「進捗」）を「変更していない」と差分で検査する受け入れ基準は書かない。形式の不変を見たい時は見出し行・列構成に限定した確認コマンドにする（例：`git diff -- vault/plans/<計画ID>.md | grep -E '^[+-](## |\| id )'`）
- `vault/rules/`（common・planner）にルールがある場合は、その具体的な基準を受け入れ基準や決定済みに反映する。ただし受け入れ基準3〜7行の上限は優先し、超えそうな場合は要約に留める
- 「受け入れ基準が3〜7行」と「1計画は7タスク以下」は、計画が draft の間、plan_guard フックで機械検査される（詳細は10節）。各基準が「真偽で判定できる文か」は機械では検査されず、planner・verifier の運用に残る

## 9. Stop フックの判定

`.claude/hooks/stop_gate.py` は、自分のブランチの承認済み計画票のタスク表と verdict を読んで判定だけを行い、状態は書き換えない。判定は次の順に行う：1. worktree への委譲、2. `stop_hook_active`、3. approved な計画票の件数、4. done の行、5. doing/review の行。4 では、status が done の行それぞれについて、attempt が一致する正しい PASS の verdict があるかを検査する（doing/review の行の検査より前。条件と理由の順は10節の done の行の verdict の検査と同じ）。続いて 5 では、doing/review が複数件になりうる前提（2節）のため、doing/review の行それぞれについて下表の判定を行い、いずれか1行でもブロック対象なら停止をブロックする。ブランチ名は見ない：承認済みの計画票はその計画のブランチにしか無く、`main` では PR を作った時点で done になっているため、approved が0件であることが計画ブランチ以外（`main` など）を表す。無人実行（`scripts/run_unattended.py`）は `HARNESS_STRICT_STOP` が未設定なら `1` を入れて子プロセスに渡す（`stop_hook_active` が真でも判定を続ける）。`HARNESS_STRICT_STOP=0` を明示すれば従来の動きになる。

| 状況 | 判定 |
|---|---|
| `stop_hook_active` が真 | 許可（`HARNESS_STRICT_STOP=1` なら無視して判定を続ける） |
| approved な計画票が0件 | 許可（ブランチ名は見ない） |
| approved な計画票が2件以上 | ブロック：1つだけ approved にする |
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

承認（draft→approved）と blocked の解除は、plan_guard では検査しない（D-015 フェーズ2 で廃止）。承認は `/plan` が粒度の確認を通した後に自動で行う。

## 11. ルール（`vault/rules/`）

ハーネスは標準ルールを同梱しない。planner / creator / verifier の役割定義は `.claude/agents/creator.md`・`.claude/agents/verifier.md`・`.claude/agents/planner.md` にある（git 運用も `.claude/agents/creator.md` の `## git` 節）。「ルール」は作成エージェント・verifier・planner に渡す拡張ポイントで、コーディングルール・開発標準・方式設計・テスト標準・テスト観点などは置き場と読み込み口だけを用意し、導入先で `vault/rules/` に書く。エージェントも `vault/rules/` に書き込める（フックは止めない）。ルールの変更は PR の差分で人が見る（D-015）。creator のタスクでも「成果物」に宣言すれば変えられる（宣言の無い変更は差分ゲート `scripts/diff_gate.py` が差し戻す。5節）。

旧版の install で配った役割定義のルール6本は、`bash scripts/install.sh --update` がマニフェストのハッシュで未編集と判定したものだけ削除し（`remove <path>` と表示）、編集済みのものは残して `note` の行で案内する（役割定義は `.claude/agents/` にある）。

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

## 12. agent_write_guard フックの判定

`.claude/hooks/agent_write_guard.py` の判定は次の3つだけ（D-015）。`agent_type` を見るのは (c) だけで、(a)(b) は `agent_type` を問わず（メインセッション含む）適用する。

| 判定 | 対象 | 結果 |
|---|---|---|
| (a) done のタスクの保護 | Write・Edit・MultiEdit・NotebookEdit の書き込み先が `vault/tasks/<計画ID>/<id>.md` か `vault/verdicts/<計画ID>/<id>.json` で、計画票（`vault/plans/<計画ID>.md`）のタスク表でその id が `done` | 拒否。計画票が無い・読めない・該当 id の行が無い時は許可。Bash による書き換えは見ない（PR の差分と、plan_guard・stop_gate の verdict の検査で見える） |
| (b) main への直接コミット | Bash のコマンドを `&&`・`||`・`;`・`|`・改行で区切った各部分の先頭が `git commit`（`git -C <パス> commit` のように `git` のオプションを挟む形を含む）で、現在のブランチが `main` | 拒否。引用符の中の区切り文字では区切らず、引用符の中の文字列（`grep -n "git commit" …` など）は拒否しない。`env`・変数代入の前置き、`bash -c` やサブシェルの中は見ない。ブランチが取れない時（detached HEAD など）は素通り |
| (c) verifier の書き込み先 | `agent_type` が verifier の Write・Edit・MultiEdit・NotebookEdit で、書き込み先が `vault/verdicts/` の外 | 拒否。verifier の Bash は制限しない |

上記のどれにも当たらない呼び出しは許可する。

やめた判定（D-015 の決定事項。人が PR の差分で見る前提に寄せた）：
- `vault/rules/` の保護：エージェントも書けるようにし、変更は PR の差分で人が見る。別ファイルに下書きして人が反映する手順は要らない
- 会話記録への書き込みの拒否：守る対象だった blocked の解除の裏付けをやめたため、守る理由が無い
- GitHub の API を直接呼ぶリモート書き込みの検知：拒否リスト方式では未知の経路を列挙しきれず、PR の差分で見える
- Bash の書き込み解析：コマンドの字句解析と解析できない形の候補の和集合は複雑さに見合わず、誤検知と取りこぼしを生んでいた
- creator・planner の書き込み先の制限：役割ごとの書き込み先は PR の差分と各エージェント定義で足りる
- blocked の解除の裏付け（人の発言に `/plan unblock` があるかをフックで見る判定）：会話記録の形式への依存と誤拒否の費用が、エージェントの独断を防ぐ効果より大きい

**フックの共通モジュール**（`.claude/hooks/_hooklib.py`）：3フックで共通に使う関数（worktree 委譲・計画票の frontmatter（`frontmatter_value`）とタスク表（`parse_tasks`）とタスク票の受け入れ基準の行数（`count_criteria`）の読み取り）を置く。各フックは、自分のファイルと同じディレクトリ（`__file__` 起点）を `sys.path` の先頭に入れて import し、worktree への委譲先ではその worktree の版を読む。import する前に `sys.dont_write_bytecode = True` にして `__pycache__` を作らない。読み込みに失敗したら、標準エラーに理由を書いて終了コード2で終わる（PreToolUse ではブロック扱い。委譲先なら委譲元の判定にフォールバックする）。Stop フックだけは、`stop_hook_active` が真で `HARNESS_STRICT_STOP` が `1` でなければ0で終わる。

### worktree への委譲の範囲

目的：creator が worktree のフックを書き換えても、書き換えたフックが worktree の外への書き込みを判定しないようにする。worktree の中の作業は開発中のフックで判定する（D-008 の目的）は保つ。

- 判定は `agent_write_guard.py` の `writes_inside_worktree` が、`H.delegate_to_worktree` を呼ぶ前に行う。
- Write 系は書き込み先（`file_path`）が worktree の中の時だけ委譲する。外なら委譲せず、メインリポジトリの版が判定する。
- Bash とそのほかのツールは常に委譲する。Bash で残る判定は (b) だけで、payload の `cwd` のブランチを見るため。
- `plan_guard.py`・`stop_gate.py` の委譲は今どおり（書き込み対象を見ない）。

### サンドボックス（使っていない）

このリポジトリでは Claude Code のサンドボックスを使っていない（`.claude/settings.json` に `sandbox` キーは無い）。
- 理由：サンドボックスが守っていたのは `vault/rules/` と会話記録（`~/.claude/projects/`）への Bash の書き込みで、D-015 でどちらも守る対象から外した。一方で `.claude/` の保護パス・`.git`・`gh` の TLS・`mktemp` での詰まりと、サンドボックスの外で動かすコマンドの例外の積み増しを生んでいた
- 一時ファイル：スクリプトは今までどおり `mktemp [-d] "${TMPDIR:-/tmp}/<名前>.XXXXXX"` の形で作り、作れない時は中断する（D-013 の書き方を戻さない）
- 導入先：`merge_settings_json.py` は導入先の settings.json に `sandbox` を足さない。導入先で有効にする手順は `docs/install.md` の「サンドボックスを有効にする（任意）」

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
