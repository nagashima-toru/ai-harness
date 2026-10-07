---
name: run
description: 自分のブランチの計画を進める。「タスクを進めて」「次のタスクをやって」「続きから」「続きをやって」「run」と言われたら必ずこのスキルを使う。承認済みの計画票（vault/plans/ の status: approved）のタスク表を読み、先頭タスクを doing にして実装し、verifier で検証し、verdict に従って done / doing / blocked に更新する。全タスクが done になったら PR を作る。
argument-hint: [task-id（省略時は先頭）]
---

自分のブランチの計画を1タスク処理する。状態の正本は承認済みの計画票（`vault/plans/<計画ID>.md` のタスク表）、仕様は `docs/vault-spec.md`。

## 0. 現在時刻
log の日時は transition.py が実時刻で書くので、run は書かない。`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'` は verifier が verdict の `checked_at` に使う。

## 0.5 実行モデルの記録
モデルの記録は transition.py が自動で付ける。`doing→review`・`doing→blocked` は `creator=<モデル>`、`review→done`・`review→doing`・`review→blocked` は `verifier=<モデル>` で、値は `.claude/agents/creator.md`・`.claude/agents/verifier.md` の frontmatter の `model` から transition.py が読む。ほかの遷移（`todo→doing`、再開・ハング・worktree が無い時の `doing→doing`・`review→doing`・blocked など）は `--no-model` を付けて呼ぶ。書式の正本は `docs/vault-spec.md` 7節で、ここでは重ねて定義しない。

## transition.py の呼び出し（早見表）
計画票のタスク表と `vault/log/<計画ID>.md` は transition.py で変える。log の日時・モデルの記録・コミットは transition.py が行う。

| 場面 | 呼び出し |
|---|---|
| 着手（手順2。todo→doing。複数 id をカンマでつないで1回） | `python3 scripts/transition.py <計画ID> <id>[,<id>...] doing` |
| creator の blocked の報告・分岐元の不一致（手順3。doing→blocked） | `python3 scripts/transition.py <計画ID> <id> blocked --question-file <質問ファイル> --worktree <worktree> --branch <branch> --plan-head <PLAN_HEAD>` |
| review にする（手順4。収集コミット・新規コミットの判定・差分ゲート・再開情報の記録行を含む） | `python3 scripts/transition.py <計画ID> <id> review --worktree <worktree> --branch <branch> --plan-head <PLAN_HEAD>` |
| PASS（手順6。マージ・done・後始末） | `python3 scripts/transition.py <計画ID> <id> done --worktree <worktree> --branch <branch> --plan-head <PLAN_HEAD>` |
| FAIL（手順6。再試行、上限なら blocked） | `python3 scripts/transition.py <計画ID> <id> doing --worktree <worktree> --branch <branch>` |
| 中断からの再開・ハング・worktree が無い時の再試行（doing→doing・review→doing） | `python3 scripts/transition.py <計画ID> <id> doing --no-model --note "<補足>"` |
| 中断・ハング・worktree が無い時の上限での blocked（doing→blocked・review→blocked） | `python3 scripts/transition.py <計画ID> <id> blocked --question-file <質問ファイル> --no-model --note "<補足>"` |

複数の id の review・done・blocked・doing（`--worktree` 付き）は1回に1 id ずつ、1つの Bash 呼び出しで1回だけ呼び、並行に呼ばない（transition.py がコミットするため）。todo→doing だけは複数 id を1回で呼ぶ。`blocked` の質問文は Write ツールで一時ファイル（例：`/tmp/<計画ID>-<id>-question.txt`）に書いて `--question-file` で渡す（言い換えずに書き写すため。引用符の問題とガードの誤検知を避けるため）。

終了コードごとの次の行動：

| 終了コード | 次の行動 |
|---|---|
| 0 | 遷移した。次の手順へ進む。`--worktree` 無しの呼び出し（着手・再開・ハング・上限での blocked）は成功すると blocked でも 0 |
| 1 | 前提を満たさず何も変えていない。標準エラーの `[transition] ` の理由を添えて人に報告し、そのタスクの処理を止める（計画票や log を Edit やシェルの書き込みで直さない） |
| 2 | 引数の誤り。早見表の形と見比べて呼び出しを直す |
| 3 | 差し戻した（creator を呼び直す）。標準出力の1行を完了報告に写し、手順3の1から `PLAN_HEAD` を取り直してその id の creator を呼び直す |
| 4 | blocked にした。標準出力の1行を完了報告に写し、その id を終えて次の対象タスクへ進む（worktree は残っている） |

## 1. 計画票を見つける
1. `bash scripts/current_plan.sh` を実行する（frontmatter の `status` が `approved` の計画票の計画 ID を1行1件で出力する）
2. 出力が0行なら「承認済みの計画が見つかりません。`/plan approve <計画ID>` を実行してください」と報告して終わる
3. 出力が2行以上なら「approved な計画票が複数あります（異常）。人に確認してください」と報告して終わる（`plan_guard.py` が書き込み時に検出しているはずだが、念のためここでも扱う。修復はしない）
4. 出力が1行なら、その行を計画 ID とし、`vault/plans/<計画ID>.md` をこの手順の計画票とする

## 2. 取り出す
1. 計画票の「タスク表」を読む
2. `review` または `doing` の行があれば、新規に取り出さず、中断からの再開として次のとおり扱う（複数あれば計画票の上から順に、行ごとに判断する）。再開に使う情報は `vault/log/<計画ID>.md` のその id の**最後の記録行**（`- <日時> <id> worktree path=<パス> branch=<ブランチ名> plan_head=<sha>` の形の行。書式の正本は `docs/vault-spec.md` 7節）だけとする。状態の変更は transition.py の呼び出しで行う（log の追記とコミットも transition.py が行う）。終了コードが0でなければ早見表の表のとおりにする。再試行か blocked かは run が決める：attempt が上限（`HARNESS_MAX_ATTEMPTS`、既定3）未満なら doing の呼び出し、達していれば blocked の呼び出し（`--worktree` 無しの transition.py は上限を超える doing を終了コード1で拒否するだけで、blocked には切り替えない）。blocked の質問文は Write ツールで一時ファイル（例：`/tmp/<計画ID>-<id>-question.txt`）に書いて `--question-file` で渡す
   - `review` の行：その id の最後の記録行から worktree のパス・ブランチ名・`plan_head`（手順6で `PLAN_HEAD` として使う）を復元し、`git worktree list` にそのパスがあることを確認する。あれば手順5へ進む（手順3・4は済んでいる）。無ければ、attempt が上限未満なら次を呼び（review→doing。attempt+1）、手順3から creator を呼び直す。記録行そのものが無い `review` の行も同じく worktree が無い場合として扱う
     - `python3 scripts/transition.py <計画ID> <id> doing --no-model --note "worktree が無いため作り直し"`
   - `review` の行で worktree が無く attempt が上限に達していれば、代わりに次を呼ぶ（質問文は「再開時に記録された worktree が無い（パス）」）
     - `python3 scripts/transition.py <計画ID> <id> blocked --question-file <質問ファイル> --no-model --note "worktree が無いため"`
   - `doing` の行：前回の呼び出しの中断を1回の試行として数える。attempt が上限未満なら次を呼び（doing→doing。attempt+1）、手順3から creator を呼び直す（`vault/tasks/<計画ID>/<id>.md` の「進捗」を読んで続けるのは creator 自身が行う）。その id に記録行があり、そのパスが `git worktree list` に残っていれば、呼び直す前に `bash scripts/discard_worktree.sh <パス> <ブランチ名>`（不採用の worktree の破棄と同じ方法）で破棄してよい
     - `python3 scripts/transition.py <計画ID> <id> doing --no-model --note "中断から再開"`
   - `doing` の行で attempt が上限に達していれば、代わりに次を呼ぶ（質問文は「中断が続き attempt が上限に達した」。worktree は破棄せず残す）
     - `python3 scripts/transition.py <計画ID> <id> blocked --question-file <質問ファイル> --no-model --note "中断が上限に達した"`
   - 記録行が無く場所が分からない worktree（`doing` の中断で残ったもの等）は自動で削除しない。完了報告に `git worktree list` の出力を添えて人に知らせる
3. 無ければ、`todo` かつ `after` に列挙された全タスクの `status` が `done`（`after` が `-` なら無条件）である行を、タスク表の上から順に並べたものを「着手可能集合」とする。引数 `$ARGUMENTS` に ID があれば、着手可能集合をその1行だけに絞る。着手可能集合の先頭から環境変数 `HARNESS_MAX_PARALLEL`（既定 3。未設定時は3を使う。`HARNESS_MAX_ATTEMPTS` と同じ環境変数パターン）件までを選ぶ
4. 選べる行が無ければ「取れるタスクがありません」と報告して終わる
5. 選んだ行の id をカンマでつないで早見表1の呼び出し `python3 scripts/transition.py <計画ID> <id>[,<id>...] doing` を1回行う（計画票・log の書き換えとコミットを transition.py が行う。コミットが要る理由：手順3の worktree はコミット済みの HEAD から分岐するため）。終了コード1なら人に報告して止める

## 3. 作る
1. 手順2で選んだタスク全部について、`git rev-parse HEAD`（このブランチ＝計画ブランチの現在の HEAD）を1回だけ控える（以下 `PLAN_HEAD`）。手順2の一括反映（doing への更新・ログ追記）が済んだ直後の値を使う
2. 選んだタスクそれぞれについて、Agent ツールで `creator` サブエージェントを呼ぶ。呼び出しには `isolation: "worktree"` オプションを付ける（計画ブランチ＝現在のブランチから分岐した隔離 worktree 上で creator を作業させる）。prompt は既存どおりタスク ID だけ（例：`<計画ID>/<id> の成果物を作ってください`）。作業の経緯・言い訳は渡さない。タスク票の読み込み・ルール読み込み・成果物作成・確認コマンドの実行・「進捗」への追記は creator が行う（creator は計画票のタスク表と `vault/log/<計画ID>.md` には書き込まない）。この呼び出しは `run_in_background: false` を指定し、完了を同期的に待つ（後続の手順4のreview化・手順6のverdict判定が呼び出し結果に依存するため）
3. 選んだタスクが複数件の場合、上記の呼び出しをタスクの数だけ**1メッセージの中で**行う（Agent ツールを複数回呼び、並行に実行させる）。選んだタスクが1件だけの場合も同じ経路を通し、呼び出しが1回になるだけとする（専用の逐次フォールバックは作らない）
4. 各呼び出しの完了時に返る worktree のパス・ブランチ名を、タスク ID に紐づけて run のセッション内で保持する。この対応は後続の review・verifier 呼び出しと、マージ処理で使う。再開に使う記録行は、手順3の8・手順4の呼び出しで transition.py が log に書く
5. 各 worktree について、分岐元がこの計画ブランチ（`PLAN_HEAD`）になっていることを次のコマンドで確認する：
   `git -C <worktree のパス> merge-base --is-ancestor <PLAN_HEAD> HEAD`
   終了コードが `0` なら、その worktree は計画ブランチ（`PLAN_HEAD`）から分岐している。`git worktree list` でパスとブランチ名の対応も確認できる
6. worktree の分岐元は `.claude/settings.json` の `worktree.baseRef: "head"` 設定により計画ブランチ（`PLAN_HEAD`）になる想定。直前の5.の確認で終了コードが非0（＝計画ブランチではなく `origin/main` 等から分岐してしまっている）場合、自己判断で起点を上書きして creator 呼び出しをやり直すことはしない。代わりに、質問文（「worktree の分岐元が計画ブランチと一致しない」と、手順5の確認コマンドの出力の要点）を Write ツールで一時ファイルに書き、手順3の8と同じ呼び出しで対象タスクを blocked にして人の判断を仰ぐ（`vault/rules/common/roles.md` の「creator → 人」節と同じ blocked 運用）
7. 各 creator の完了報告を受け取る。報告が「blocked: <質問文>」の形式のものと、そうでないものをタスクごとに分けて記録する
8. 報告が「blocked: <質問文>」のタスクについて、質問文を言い換えずに Write ツールで一時ファイル（例：`/tmp/<計画ID>-<id>-question.txt`）に書き、`python3 scripts/transition.py <計画ID> <id> blocked --question-file <質問ファイル> --worktree <worktree> --branch <branch> --plan-head <PLAN_HEAD>` を id ごとに1回呼ぶ。worktree は transition.py が残す。終了コードは4（blocked にした）が正常。選んだタスクの中に blocked 以外が無ければここで終わる

## 4. review にする
blocked ではない完了報告を受けたタスクについて、id ごとに1回ずつ、計画票のタスク表の上から順に次を呼ぶ（並行に呼ばない）：
`python3 scripts/transition.py <計画ID> <id> review --worktree <worktree> --branch <branch> --plan-head <PLAN_HEAD>`
この1回で、worktree の未コミット分の収集コミット・新規コミットの判定・差分ゲート・再開情報の記録行・doing→review とそのコミットが行われる。creator の成果物は worktree 側にコミット済みになり、verifier はそれを検証する。

終了コードごとの次の行動：
- 0：review になった。手順5で verifier を呼ぶ対象にする
- 3：差分ゲートの違反で差し戻した（doing のまま attempt+1。worktree は破棄済み）。標準出力の1行を完了報告に写し、手順3の1から `PLAN_HEAD` を取り直して、その id の creator を呼び直す（transition.py のコミットで計画ブランチの HEAD が進むため取り直す）
- 4：blocked にした（新規コミット無し、または差し戻しが上限）。標準出力の1行を完了報告に写し、その id を終える。worktree は残っている
- 1・2：早見表の終了コードの表のとおり（人に報告して止める／呼び出しを直す）

## 5. 検証する
1. review にした（＝blocked ではなかった）タスクそれぞれについて、Agent ツールで `verifier` サブエージェントを呼ぶ。`isolation` オプションは付けない通常の呼び出しにする。prompt はタスク ID と、手順3で保持した対象タスクの worktree のパスの2つだけ（例：`<計画ID>/<id> を検証して vault/verdicts/<計画ID>/<id>.json を書いてください。対象 worktree: <worktree のパス>`）。作業内容の説明や言い訳は渡さない。この呼び出しも `run_in_background: false` を指定し、完了を同期的に待つ（後続の手順6のverdict判定が呼び出し結果に依存するため）
2. verifier は `EnterWorktree` を使わない（verifier の tools に無く、権限も増やさない）。渡された worktree のパスに対して、git は `git -C <worktree のパス> ...`、ファイルは `<worktree のパス>/<相対パス>` の絶対パスで読む。作業ディレクトリが要るコマンド（スクリプトの実行など）は、同じ Bash 呼び出しの中で `cd <worktree のパス>` してから実行する。verdict はメインリポジトリ側の `vault/verdicts/<計画ID>/<id>.json` に書く（creator の呼び出しで作られた既存 worktree を再利用し、verifier 自身は新規に worktree を作らない）
3. 対象タスクが複数件の場合、上記の呼び出しをタスクの数だけ1メッセージの中で行う（並行実行）。1件だけの場合も同じ経路を通し、呼び出しが1回になるだけとする
4. 全ての verifier の完了を待ち、それぞれの `vault/verdicts/<計画ID>/<id>.json` を読む（verifier の返答文ではなくファイルを根拠にする）

## ハング時の復旧（手順3・5の Agent 呼び出しが応答しない場合）
手順3（creator 呼び出し）・手順5（verifier 呼び出し）の Agent ツール呼び出しは、コマンドが「即時拒否」される場合と異なり、応答が返らないまま止まる「ハング」を起こすことがある（issue #48）。Agent ツール呼び出しは同期的にブロックするため、呼び出し中のオーケストレーター自身が自分の呼び出しに自動でタイムアウトを設定する手段は前提にしない。ハングに気づいて TaskStop（またはそれに相当する強制終了の手段）で止めるのは、人またはオーケストレーターの運用者の役目とする。**応答なしとみなす目安は15分**とする（issue #48 で観測された「約17分以上応答が無い」事象を踏まえた保守的な値。正確な自動計測は前提にしない）。

強制終了で復旧した後、オーケストレーターは次のいずれかの手順を取る。

1. **creator 呼び出し（手順3）がハングした場合**：対象タスクの worktree を `bash scripts/discard_worktree.sh <worktree のパス> <ブランチ名>` で破棄する（FAIL の再試行で不採用の worktree を破棄するのと同じ方法）。その後、attempt が上限（`HARNESS_MAX_ATTEMPTS`、既定3）未満なら次の呼び出しをして手順3から creator を呼び直す。
   - `python3 scripts/transition.py <計画ID> <id> doing --no-model --note "creator呼び出しハングにより再試行"`

   attempt が上限に達していれば、代わりに次を呼ぶ（質問文は「creator 呼び出しがハングした（応答無し、強制終了で復旧）」。Write ツールで一時ファイルに書いて `--question-file` で渡す）。
   - `python3 scripts/transition.py <計画ID> <id> blocked --question-file <質問ファイル> --no-model --note "creator呼び出しハング"`
2. **verifier 呼び出し（手順5）がハングした場合**：creator の成果物が入っている worktree は破棄しない（維持する）。verifier を呼び直してよいが、同一タスクでのハング再試行が2回に達したら（タスクの attempt カウンタとは別に、ハング再試行回数として数える）次を呼ぶ（review→blocked。質問文は「verifier 呼び出しがハングした」ことと worktree のパス）。この場合も worktree は削除しない（人が調査に使えるようにする、既存の blocked 時の温存方針と同じ）。
   - `python3 scripts/transition.py <計画ID> <id> blocked --question-file <質問ファイル> --no-model --note "verifier呼び出しハング"`

いずれの場合も、状態の変更は transition.py の呼び出しで行い（log の追記とコミットも transition.py が行う）、補足（`--note`）に「ハング」の語を含める。

**無人実行（cron・CI）の場合**：`python3 scripts/run_unattended.py` を cron・CI から呼ぶ場合は、人が TaskStop で止めるのを待たない。ラッパーが `HARNESS_RUN_TIMEOUT`（既定 3600 秒）でプロセスグループごと止め、終了コード124で終わる。止められた後の復旧は、次回の `/run` が手順2.2（フェーズ6の再開手順：`doing` は中断を1回の試行として attempt+1、`review` は記録行から worktree を復元）で続きから行う。同じ地点で止まり続けても `HARNESS_MAX_ATTEMPTS` で `blocked` になる。ラッパーは vault のファイルに書かない（状態の変更は次回の `/run` が再開手順の中で transition.py で行う）。対話実行（人が `/run` を打つ場合）の運用は上記のとおり変わらない。

## 6. verdict に従う（逐次処理）
全 verifier の完了を待った上で、対象タスク（手順5で verifier を呼んだタスク）を1件ずつ、計画票のタスク表の上から並んだ順に**逐次**処理する。transition.py がコミット・マージを行うので、複数タスクが同時に PASS していても並行に呼ばず、1件ずつ完了させてから次のタスクに移る。

各タスクについて：
1. `vault/verdicts/<計画ID>/<id>.json` が存在しない場合、まず対象タスクの worktree のパス（手順3の4で保持したもの）配下の同じ相対パス（`<worktree のパス>/vault/verdicts/<計画ID>/<id>.json`）を確認する。存在すれば `cp <worktree のパス>/vault/verdicts/<計画ID>/<id>.json vault/verdicts/<計画ID>/<id>.json` でメインリポジトリ側へコピーし（log には書かない。コピーした verdict は done のコミットに含まれる）、手順2で通常どおり読む。worktree 側にも見つからない場合は検証未完了として扱い、そのタスクは次のタスクに進まず処理を止める（人に確認する）
2. `vault/verdicts/<計画ID>/<id>.json`（手順1でコピーした場合はコピー後のファイル）を読み、`result` と `attempt` を確認する。`attempt` が計画票のタスク表の値と一致しない verdict は「無い」ものとして扱い、そのタスクは検証未完了として次のタスクに進まず処理を止める（人に確認する）
3. `PASS` の場合：次を1回呼ぶ。`PLAN_HEAD` は手順3の1で控えた値（中断からの再開では log の記録行から復元した値。手順2の2）を使う。
   `python3 scripts/transition.py <計画ID> <id> done --worktree <worktree> --branch <branch> --plan-head <PLAN_HEAD>`
   この1回で、PASS の verdict の確認・未コミット分の収集・新規コミットの判定・差分ゲート・計画ブランチへの `--no-ff` マージ・done とそのコミット（verdict を含む）・worktree とブランチの後始末が行われる。コンフリクトは自己判断で解決しない（`vault/rules/common/git.md` の方針）。transition.py がマージを中止して blocked にする。

   終了コードごとの次の行動：
   - 0：done になった。次の対象タスクへ進む
   - 4：blocked にした（新規コミット無し・宣言外の変更・マージコンフリクトのいずれか。コンフリクトはマージを中止済み）。標準出力の1行を完了報告に写す。worktree は残っている。他の対象タスクの処理は止めず次へ進む
   - 1：何もしていない（PASS の verdict が無い・attempt 不一致など）か、マージ済みだが状態のコミットに失敗した。標準エラーの理由を添えて人に報告し、処理を止める
4. `FAIL` の場合：計画ブランチへはマージしない。次を1回呼ぶ。
   `python3 scripts/transition.py <計画ID> <id> doing --worktree <worktree> --branch <branch>`
   再試行するか blocked にするかの上限の判断（`HARNESS_MAX_ATTEMPTS`）は transition.py が行うので、run は attempt を比べない。

   終了コードごとの次の行動：
   - 3：再試行に回した（review→doing で試行回数を進め、worktree とブランチを破棄済み）。手順3の1から `PLAN_HEAD` を取り直して、その id の creator を呼び直す（verdict の `reasons` を読んで直すのは creator の役目）
   - 4：上限に達したので reasons を question にして blocked にした。worktree は残っている。標準出力の1行を完了報告に写して次へ進む
   - 1：verdict が FAIL でない・attempt 不一致など。人に報告して止める
5. 次の対象タスクがあれば同様に処理する。対象タスク全部の処理が終わったら手順7へ進む

## 7. 次へ・完了
- 計画票に取れる行が残っていれば手順2に戻る
- 全タスクが `done` になったら、次の順で PR を作る
  1. 計画票 frontmatter の `status` を `done` にする
  2. `python3 scripts/pr_body.py <計画ID>` と `python3 scripts/verdict_notes.py <計画ID>` を実行し、出力を読む
  3. 本文ファイルを Write ツールで一時ファイル（例：`/tmp/<計画ID>-pr-body.md`。手順3の質問ファイルと同じ書き方）に書く。中身は次の3つで、出力は言い換えずにそのまま写す：計画 ID の1行、タスク一覧（`python3 scripts/pr_body.py <計画ID>` の出力。計画 ID・id・title・commit・verdict の表）、`## verifier の指摘` の見出しと `verdict_notes.py` の出力。`verdict_notes.py` が終了コード0以外で終わった時も PR は作り、この節に標準エラーの内容を書く（指摘の一覧が無いことで PR 作成を止めない）
  4. `env HARNESS_PR_BODY_FILE=<本文ファイル> HARNESS_PR_TITLE="<計画ID>: <ゴールの1行目>" bash scripts/vcs_finish.sh` を実行する（`env` で始めるのは許可リストの `Bash(env *)` で通すため）。終了コード0で完了すれば（GitHub/GitLab で PR/MR が作られた場合も、ホスティング無し（`none`）で案内メッセージのみが出力された場合も）この手順は完了として扱う。`none` の場合、標準出力に出る現在のブランチ名とマージの案内をそのまま人への完了報告に含める（`gh pr merge`/`glab mr merge` は実行しない。マージは人が行う）。draft PR にするかは規定しない
  5. 完了報告に `verdict_notes.py` の出力をそのまま含める（「指摘なし」の時も1行で含める）
  - 引数なしの `bash scripts/vcs_finish.sh`（`HARNESS_PR_BODY_FILE` 無し）は `/design` などが使う経路として残る。現在のブランチが `work/<計画IDの英小文字>` で `vault/plans/` に計画票があれば、`scripts/pr_body.py` のタスク履歴表を本文にして `--title "<計画ID>: <ゴールの1行目>"` で PR/MR を作り、計画が見つからない時（`design/d-xxx` など）は `gh pr create --fill` / `glab mr create --fill --yes` を使う。引数がある時は既定を付けず、そのまま渡す
  - `bash scripts/vcs_finish.sh` が `gh`/`glab` コマンド自体が無いことによる失敗（`command not found` 相当の終了コード127、または本スクリプトが出す「`gh`/`glab` コマンドが見つかりません」という明示エラー）で終了した場合：GitHub であれば GitHub MCP ツール（例：実行環境で使える `mcp__github__create_pull_request` 等）で同内容の PR を作成してよい。`gh pr create "$@"` に渡すはずだったブランチ名・PR タイトル・本文は、そのまま MCP ツールの引数に引き継ぐ（本文には本文ファイルの中身、タイトルには `HARNESS_PR_TITLE` の値を使う）。GitLab（`glab`）が同様の理由で失敗した場合も、GitLab MCP 等の代替手段が使える環境ではそれを使ってよい。使える代替手段が無い環境では、人にブランチ名と状況を案内して止まる。いずれの代替経路を使った場合も `gh pr merge`/`glab mr merge` は実行しない（マージは人が行うという既存方針は変わらない）。認証エラー・ネットワークエラー等、コマンド自体は存在するが実行に失敗するケースはこの代替の対象外とする
- どちらでもなければ、処理した ID と結果を1行ずつ報告して終わる

## 8. ハーネス振り返り
全タスクが `done` になり `scripts/vcs_finish.sh` を実行した直後、**オーケストレーター（run のメインセッション）自身**が1回だけ行う（`creator`・`verifier` を呼ばない。`.claude/agents/creator.md`・`vault/rules/creator/`・`vault/rules/verifier/` は変更しない）。

1. 今回処理した計画のタスク群を振り返り、`.claude/`（スキル・エージェント定義・フック）や `vault/rules/` に対する**構造的な**改善点（スキル手順の分かりにくさ、フックの誤検知・見落とし、ルール文書の過不足など、繰り返し発生しうる問題）に気づいたかどうかを判断する。軽微な言い回し修正・タイポは対象外。頻度は「あれば書く」であり、毎回 must ではない
2. 気づきが無ければ、ここで何もしない（issue も作らず、ログにも残さない）。以下の3・4は行わない
3. 構造的な改善点に気づいた場合は、`gh issue create` で改善提案 issue を1件起票する。タイトル・本文フォーマットは自由（「気づいたこと」「該当箇所」「提案」が分かる程度でよい）。新しいテンプレートファイルは作らない。PR 本文には改善提案セクションを追加しない（`scripts/vcs_finish.sh` 呼び出し手順自体は変更しない）
4. `gh issue create` の実行が失敗した場合（権限不足・ネットワークポリシー等）は、提案内容をそのまま `vault/harness-improvements/<計画ID>.md` に書き残し、完了報告でその旨を人に伝える。issue 化に成功した場合はこのファイルを作らない。このファイルは5状態遷移の対象ではない
5. 起票した issue（またはフォールバックで書いたファイル）の自動トリアージ（ラベル付け・アサイン等）は行わない

## 回帰確認（着手可能集合が1件だけの場合）
着手可能集合が1件だけの計画でも手順2〜7は同じ経路（creator/verifier のサブエージェント呼び出し・worktree・transition.py による逐次の状態変更とマージ）を通す（専用の逐次フォールバックは作らない）。この経路を通しても、`P-20260924-creator-subagent` で実施したフェーズ2までの逐次フロー（worktree を使わず1タスクずつ creator→review→verifier→done/blocked を処理していた版）と最終結果が同じになることを、次の観点で確認する：
1. 計画票のタスク表：対象タスクの行が最終的に `done`（FAIL で上限到達、またはマージコンフリクトの場合は `blocked`）になっており、`attempt` の値が実際の処理回数と一致している。他の行の `status`・`after`・`question` は変化していない
2. `vault/log/<計画ID>.md`：対象タスクについて `todo→doing` → `doing→review` →（`review→done` または `review→doing`（再試行）または `review→blocked`）の各遷移が transition.py によって1行ずつ、他のタスクと同じ書式（`- <日時> <id> <遷移> attempt=<n> [補足]`）で記録されている。日時は transition.py の実時刻である。着手可能集合が1件だけなので、フェーズ2の版と行数・書式が一致する
3. 成果物：計画ブランチ上の対象ファイルの差分（`git diff <PLAN_HEAD>..HEAD -- <成果物のパス>`）が、creator が worktree 内で作った変更内容と一致し、マージコミット以外の余分な差分が無い（worktree 側に収集コミット `<計画ID>/<id>: creator 成果物をオーケストレーターが収集` がありうる）
4. `vault/verdicts/<計画ID>/<id>.json` の `attempt` が計画票のタスク表の値と一致している（Stop フックの整合性検査を通過する点もフェーズ2と同じ）
5. worktree・作業ブランチが最終状態で残っていない（PASS で `done` になれば transition.py の done が削除済み。`blocked`（新規コミット無し・宣言外の変更・コンフリクト・上限到達）の時だけ残っていてよい）

上記1〜5がいずれも成立すれば、着手可能集合が1件だけのケースの最終状態はフェーズ2までの逐次フローと同じ結果とみなす。差異があれば手順6・7の実装を見直す。

## 注意
- Stop フックが verdict と status を照合する。手順を飛ばして終わろうとするとブロックされ、理由が表示される
- `done` のタスク票は編集しない。計画票のタスク表の列順・見出しは変えない
- creator のコミットはタスク票の受け入れ基準に含まれている場合だけ行う（手順4の review の呼び出しで transition.py が worktree の未コミット分を収集コミットするのはこの対象外）
- タスク表と log は transition.py で変え、Edit やシェルの書き込みで直接書き換えない（frontmatter の approved→done だけは Edit）
- タスク中は `vault/rules/` を編集しない（verifier の判定基準を自分で変えないため。フックでも拒否される）
