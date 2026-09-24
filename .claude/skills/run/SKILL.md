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
3. 無ければ、`todo` かつ `after` に列挙された全タスクの `status` が `done`（`after` が `-` なら無条件）である行を、タスク表の上から順に並べたものを「着手可能集合」とする。引数 `$ARGUMENTS` に ID があれば、着手可能集合をその1行だけに絞る。着手可能集合の先頭から環境変数 `HARNESS_MAX_PARALLEL`（既定 3。未設定時は3を使う。`HARNESS_MAX_ATTEMPTS` と同じ環境変数パターン）件までを選ぶ
4. 選べる行が無ければ「取れるタスクがありません」と報告して終わる
5. 選んだ行**全部**について、status を `doing`、attempt を `1` にする。この計画票への書き込みは、選んだタスクごとに分けず、他の処理を挟まず本手順の中でまとめて（一括で）行う。`vault/log/<計画ID>.md` への追記も同様に、選んだタスク全部について `- <日時> <id> todo→doing attempt=1` を本手順の中で連続してまとめて行う

## 3. 作る
1. 手順2で選んだタスク全部について、`git rev-parse HEAD`（このブランチ＝計画ブランチの現在の HEAD）を1回だけ控える（以下 `PLAN_HEAD`）。手順2の一括反映（doing への更新・ログ追記）が済んだ直後の値を使う
2. 選んだタスクそれぞれについて、Agent ツールで `creator` サブエージェントを呼ぶ。呼び出しには `isolation: "worktree"` オプションを付ける（計画ブランチ＝現在のブランチから分岐した隔離 worktree 上で creator を作業させる）。prompt は既存どおりタスク ID だけ（例：`<計画ID>/<id> の成果物を作ってください`）。作業の経緯・言い訳は渡さない。タスク票の読み込み・ルール読み込み・成果物作成・確認コマンドの実行・「進捗」への追記は creator が行う（creator は計画票のタスク表と `vault/log/<計画ID>.md` には書き込まない）
3. 選んだタスクが複数件の場合、上記の呼び出しをタスクの数だけ**1メッセージの中で**行う（Agent ツールを複数回呼び、並行に実行させる）。選んだタスクが1件だけの場合も同じ経路を通し、呼び出しが1回になるだけとする（専用の逐次フォールバックは作らない）
4. 各呼び出しの完了時に返る worktree のパス・ブランチ名を、タスク ID に紐づけて run のセッション内で保持する（`vault/tasks/` 等ファイルへの永続化は不要）。この対応は後続の verifier 呼び出しと、T-03 で扱うマージ処理で使う
5. 各 worktree について、分岐元がこの計画ブランチ（`PLAN_HEAD`）になっていることを次のコマンドで確認する：
   `git -C <worktree のパス> merge-base --is-ancestor <PLAN_HEAD> HEAD`
   終了コードが `0` なら、その worktree は計画ブランチ（`PLAN_HEAD`）から分岐している。`git worktree list` でパスとブランチ名の対応も確認できる
6. worktree の分岐元は `.claude/settings.json` の `worktree.baseRef: "head"` 設定により計画ブランチ（`PLAN_HEAD`）になる想定。直前の5.の確認で終了コードが非0（＝計画ブランチではなく `origin/main` 等から分岐してしまっている）場合、自己判断で起点を上書きして creator 呼び出しをやり直すことはしない。代わりに対象タスクの計画票の該当行を `blocked` にし、question に「worktree の分岐元が計画ブランチと一致しない（手順5の確認コマンドの出力要点）」のように状況を書き、人の判断を仰ぐ（`vault/rules/common/roles.md` の「creator → 人」節と同じ blocked 運用）
7. 各 creator の完了報告を受け取る。報告が「blocked: <質問文>」の形式のものと、そうでないものをタスクごとに分けて記録する
8. blocked のタスクが1件以上あれば、それら全部について計画票の該当行の status を `blocked` にし、question 列に creator の質問文をそのまま書き写す（言い換えない）。この書き込みは対象タスクごとに分けず本手順の中でまとめて行う。`vault/log/<計画ID>.md` にも対象タスク分をまとめて `- <日時> <id> doing→blocked attempt=<n> 理由要約` の形で追記する。選んだタスクの中に blocked 以外が無ければここで終わる

## 4. review にする
blocked ではない完了報告を受けたタスク全部について、status を `review` にする。この計画票への書き込みは、手順2の一括反映と同様に、対象タスクごとに分けず本手順の中でまとめて行う。`vault/log/<計画ID>.md` にも対象タスク分をまとめて `- <日時> <id> doing→review attempt=<n>` の形で追記する。

## 5. 検証する
1. review にした（＝blocked ではなかった）タスクそれぞれについて、Agent ツールで `verifier` サブエージェントを呼ぶ。`isolation` オプションは付けない通常の呼び出しにする。prompt はタスク ID と、手順3で保持した対象タスクの worktree のパスの2つだけ（例：`<計画ID>/<id> を検証して vault/verdicts/<計画ID>/<id>.json を書いてください。対象 worktree: <worktree のパス>`）。作業内容の説明や言い訳は渡さない
2. verifier は渡された worktree のパスに対して `EnterWorktree(path=<渡されたパス>)` を実行し、その worktree に入ってから検証する（creator の呼び出しで作られた既存 worktree を再利用し、verifier 自身は新規に worktree を作らない）
3. 対象タスクが複数件の場合、上記の呼び出しをタスクの数だけ1メッセージの中で行う（並行実行）。1件だけの場合も同じ経路を通し、呼び出しが1回になるだけとする
4. 全ての verifier の完了を待ち、それぞれの `vault/verdicts/<計画ID>/<id>.json` を読む（verifier の返答文ではなくファイルを根拠にする）

## 6. verdict に従う（逐次処理）
全 verifier の完了を待った上で、対象タスク（手順5で verifier を呼んだタスク）を1件ずつ、計画票のタスク表の上から並んだ順に**逐次**処理する。複数タスクが同時に PASS していても、マージや状態遷移の書き込みは同時に行わず1件ずつ完了させてから次のタスクに移る。

各タスクについて：
1. `vault/verdicts/<計画ID>/<id>.json` を読み、`result` と `attempt` を確認する。`attempt` が計画票のタスク表の値と一致しない verdict は「無い」ものとして扱い、そのタスクは検証未完了として次のタスクに進まず処理を止める（人に確認する）
2. `PASS` の場合：
   1. 計画ブランチ（現在のブランチ）上で `git merge --no-ff <対象タスクの worktree のブランチ名>` を実行し、worktree 上の変更を計画ブランチへ取り込む
   2. マージが衝突なく成功したら、status を `review` から `done` にし、`vault/log/<計画ID>.md` に `- <日時> <id> review→done attempt=<n>` を追記する。続けて `git worktree remove <worktree のパス>` で worktree を削除し、不要になった作業ブランチも `git branch -d <ブランチ名>`（計画ブランチへ取り込み済みなので安全に削除できる）で削除する
   3. マージでコンフリクトが起きた場合：自己判断で解決しない（`vault/rules/common/git.md` の既存方針）。`git merge --abort` でマージを中断し、status を `blocked` にし question 列にコンフリクトの状況（コンフリクトしたファイル一覧、実行したコマンドとエラーの要点。例：`git status` の該当部分の要約）を書く。`vault/log/<計画ID>.md` に `- <日時> <id> review→blocked attempt=<n> マージコンフリクト` を追記する。この worktree は削除せず残す（人がコンフリクト解消の調査に使えるようにする）。他の対象タスクの処理は止めず、次のタスクへ進む
3. `FAIL` の場合：
   1. 計画ブランチへはマージしない
   2. attempt < 上限（`HARNESS_MAX_ATTEMPTS`、既定 3）なら、status を `doing`、attempt を +1 にし、`vault/log/<計画ID>.md` に `- <日時> <id> review→doing attempt=<n+1> 理由要約` を追記する。手順3の1から繰り返す（creator を再度呼ぶ。verdict の `reasons` を読んで直すのは creator の役目）。この時、対象タスクの worktree は**破棄して作り直す**方針を採る：`git worktree remove <worktree のパス> --force` と `git branch -D <ブランチ名>` で削除する（計画ブランチへ取り込んでいない不採用の変更なので破棄してよい）。次回手順3で creator を呼ぶ際に、その呼び出しが新しい worktree を作る
   3. attempt ≥ 上限なら、status を `blocked`、question 列に reasons の要約を書き、`vault/log/<計画ID>.md` に `- <日時> <id> review→blocked attempt=<n> 理由要約` を追記する。この場合 worktree は削除しなくてよい（人が blocked を解消する調査に使える可能性があるため、コンフリクト時の温存方針と揃える）
4. 次の対象タスクがあれば同様に処理する。対象タスク全部の処理が終わったら手順7へ進む

## 7. 次へ・完了
- 計画票に取れる行が残っていれば手順2に戻る
- 全タスクが `done` になったら、計画票 frontmatter の `status` を `done` にし、`gh pr create` を実行して PR を作る（`gh pr merge` は実行しない。マージは人が行う）。draft PR にするかは規定しない
- どちらでもなければ、処理した ID と結果を1行ずつ報告して終わる

## 8. ハーネス振り返り
全タスクが `done` になり `gh pr create` で PR を作成した直後、**オーケストレーター（run のメインセッション）自身**が1回だけ行う（`creator`・`verifier` を呼ばない。`.claude/agents/creator.md`・`vault/rules/creator/`・`vault/rules/verifier/` は変更しない）。

1. 今回処理した計画のタスク群を振り返り、`.claude/`（スキル・エージェント定義・フック）や `vault/rules/` に対する**構造的な**改善点（スキル手順の分かりにくさ、フックの誤検知・見落とし、ルール文書の過不足など、繰り返し発生しうる問題）に気づいたかどうかを判断する。軽微な言い回し修正・タイポは対象外。頻度は「あれば書く」であり、毎回 must ではない
2. 気づきが無ければ、ここで何もしない（issue も作らず、ログにも残さない）。以下の3・4は行わない
3. 構造的な改善点に気づいた場合は、`gh issue create` で改善提案 issue を1件起票する。タイトル・本文フォーマットは自由（「気づいたこと」「該当箇所」「提案」が分かる程度でよい）。新しいテンプレートファイルは作らない。PR 本文には改善提案セクションを追加しない（`gh pr create` 呼び出し手順自体は変更しない）
4. `gh issue create` の実行が失敗した場合（権限不足・ネットワークポリシー等）は、提案内容をそのまま `vault/harness-improvements/<計画ID>.md` に書き残し、完了報告でその旨を人に伝える。issue 化に成功した場合はこのファイルを作らない。このファイルは5状態遷移の対象ではない
5. 起票した issue（またはフォールバックで書いたファイル）の自動トリアージ（ラベル付け・アサイン等）は行わない

## 回帰確認（着手可能集合が1件だけの場合）
着手可能集合が1件だけの計画でも手順2〜7は同じ経路（creator/verifier のサブエージェント呼び出し・worktree・逐次マージ）を通す（専用の逐次フォールバックは作らない）。この経路を通しても、`P-20260924-creator-subagent` で実施したフェーズ2までの逐次フロー（worktree を使わず1タスクずつ creator→review→verifier→done/blocked を処理していた版）と最終結果が同じになることを、次の観点で確認する：
1. 計画票のタスク表：対象タスクの行が最終的に `done`（FAIL で上限到達、またはマージコンフリクトの場合は `blocked`）になっており、`attempt` の値が実際の処理回数と一致している。他の行の `status`・`after`・`question` は変化していない
2. `vault/log/<計画ID>.md`：対象タスクについて `todo→doing` → `doing→review` →（`review→done` または `review→doing`（再試行）または `review→blocked`）の各遷移が1行ずつ、他のタスクと同じ書式（`- <日時> <id> <遷移> attempt=<n> [補足]`）で記録されている。着手可能集合が1件だけなので「まとめて」書く手順を通っても実際には1行ずつになり、フェーズ2の版と行数・書式が一致する
3. 成果物：計画ブランチ上の対象ファイルの差分（`git diff <PLAN_HEAD>..HEAD -- <成果物のパス>`）が、creator が worktree 内で作った変更内容と一致し、マージコミット以外の余分な差分が無い
4. `vault/verdicts/<計画ID>/<id>.json` の `attempt` が計画票のタスク表の値と一致している（Stop フックの整合性検査を通過する点もフェーズ2と同じ）
5. worktree・作業ブランチが最終状態で残っていない（PASS で `done` になった場合は削除済み。`blocked`（コンフリクトまたは上限到達）の場合のみ残っていてよい）

上記1〜5がいずれも成立すれば、着手可能集合が1件だけのケースの最終状態はフェーズ2までの逐次フローと同じ結果とみなす。差異があれば手順6・7の実装を見直す。

## 注意
- Stop フックが verdict と status を照合する。手順を飛ばして終わろうとするとブロックされ、理由が表示される
- `done` のタスク票は編集しない。計画票のタスク表の列順・見出しは変えない
- git のコミットはタスク票の受け入れ基準に含まれている場合だけ行う
- タスク中は `vault/rules/` を編集しない（verifier の判定基準を自分で変えないため。フックでも拒否される）
