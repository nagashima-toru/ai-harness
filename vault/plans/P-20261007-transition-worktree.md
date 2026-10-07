---
id: P-20261007-transition-worktree
status: draft
---
# ゴール
transition.py に worktree の運用を足す（D-012 フェーズ4）

`scripts/transition.py` に、run の worktree の運用を1コマンドで行う機能を足す。サブコマンド（遷移先）は review / done / doing / blocked の4つで、いずれも `--worktree <パス> --branch <ブランチ> [--plan-head <sha>]` を付けて呼ぶ。

- review：worktree の未コミット分を収集コミットし、新規コミットが無ければ doing→blocked。あれば `scripts/diff_gate.py` の `check` で検査し、違反が無ければ再開情報の記録行と doing→review を書いてコミット。違反があれば「進捗」と log に書いて doing のまま attempt+1 にし worktree を破棄（上限なら blocked にして worktree を残す）
- done：PASS の verdict と差分ゲートを確かめてから計画ブランチへ `git merge --no-ff` し、done にしてコミットし、worktree とブランチを消す。衝突したらマージを中止して review→blocked
- doing（FAIL の再試行）：attempt+1 して worktree を破棄。上限なら verdict の reasons を question にして review→blocked
- blocked（creator が blocked を報告した時）：記録行を書いて blocked にし、worktree は残す
- 終了コードは 0 review/done にした／1 前提を満たさず何もしていない／2 引数の誤り／3 差し戻した／4 blocked にした。3・4 の時は標準出力に1行
- `--worktree` を渡さない呼び出しはフェーズ2の動きのまま。このフェーズでは run の手順（`.claude/skills/run/SKILL.md`）は変えない

正本は `vault/designs/D-012.md` の「フェーズ4 transition.py に worktree の運用を足す」。

## 分割方針
- 同じ `scripts/transition.py` を T-01（共通部品と review）→ T-02（done）→ T-03（doing と blocked）の順に直列で編集する。T-01 の時点では `--worktree` を review だけで受け付け、done・doing・blocked に付けたら終了コード2にしておく。T-02 で done を、T-03 で doing・blocked を受け付けるようにする（各タスクの時点で、受け付けた遷移はすべて決定済みどおりに動く）
- T-04（`scripts/smoke.sh` のケース）と T-05（`docs/vault-spec.md`）は別ファイルなので、T-03 の後に並行で進められる。T-05 は 2節・7節のほか、5節の「今の `/run` はまだ `diff_gate.py` を呼ばない」の行を、transition.py が `check` を使うことに合わせて直す
- どのタスクも単体でマージして `bash scripts/smoke.sh` が `fail=0` で通る。T-01〜T-03・T-05 は smoke.sh を変えない（pass は計画作成時点の 594 のまま）。T-04 で25件以上足す
- T-01〜T-03 の動作確認には、planner が置いたフィクスチャ `vault/tasks/P-20261007-transition-worktree/fixtures/try.sh` を使う。一時 git リポジトリ（ブランチ `work/p-test`、承認済み計画票 `P-TEST`、タスク票 `T-01`（「成果物」は `src/ok.txt`）、`plan_head` から切った worktree（ブランチ `worktree-agent-fx`））を作って `scripts/transition.py P-TEST T-01 <引数>` を1回実行し、終了コード・計画ブランチに増えたコミット（親の数・件名・ファイル）・worktree とブランチの有無・worktree 側のコミット・表・増えた log・タスク票の末尾・標準出力と標準エラーを出す（使い方・preset・置き換え記号 `@WT`・`@BR`・`@PH`・`@WORK`・`@QFILE` はファイル先頭のコメント）。今の `transition.py` で、全 preset のセットアップと出力が動くことは確かめてある（`--worktree` を付けると `exit=2`、付けない `rev review`・`pass done`・`fail doing` は `exit=0`）
- smoke（T-04）はこのフィクスチャを使わない。install 先には `vault/tasks/` の計画のファイルが無いため、smoke.sh の中で同じ形の一時リポジトリと worktree を作る

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | transition.py に --worktree の共通部品（引数・worktree の検証・収集コミット・新規コミット判定）と review を足す | |
| T-02 | todo | 0 | T-01 | transition.py の done に --worktree（差分ゲート・--no-ff マージ・衝突時の blocked・後始末）を足す | |
| T-03 | todo | 0 | T-02 | transition.py の doing（FAIL の再試行）と blocked に --worktree を足す | |
| T-04 | todo | 0 | T-03 | smoke.sh に transition.py の worktree 運用のケースを25件以上足す | |
| T-05 | todo | 0 | T-03 | docs/vault-spec.md の2節・7節に worktree 運用のサブコマンドの動きと終了コードを書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` を含み、pass が 619 以上
- `.claude/skills/run/SKILL.md` は変わっていない（このフェーズでは run の手順を変えない）

## 次フェーズの候補
- D-012 フェーズ5（`.claude/skills/run/SKILL.md` の状態変更を `transition.py` の呼び出しに置き換える。`.claude/agents/verifier.md` と `docs/vault-spec.md` の1節・2節・7節を新しい流れに合わせる）

## 人への質問
1. 収集コミットの文面：D-012 の決定済みは `<計画ID>/<id>: creator 成果物をオーケストレーターが収集` で「今の run の手順6.3.1と同じ文面」としているが、今の手順6.3.1の文面は `<計画ID>/<id>: creator 成果物の未コミット分をオーケストレーターが収集` で一致しない。D-012 の字句（`creator 成果物をオーケストレーターが収集`）を採った（T-01 の決定済み・受け入れ基準）。run の文面に合わせる場合は指示してほしい
2. `scripts/pr_body.py` は done のコミットを件名 `^<計画ID>/<id>: done$` で探すが、フェーズ2の `transition.py` の done のコミットの件名は `<計画ID>/<id>: review→done` で、PR 本文のタスク履歴表から辿れなくなる。このフェーズでは件名をフェーズ2のまま変えない前提にした（フェーズ5で run が transition.py を使い始める前に、どちらかを直す必要がある）。このフェーズで直すかを決めてほしい
3. `--worktree` を受け付ける遷移を、review は doing から、done は review から、doing は review から（FAIL の再試行）、blocked は doing から（creator の blocked 報告）に限った。中断からの再開やハング時の doing→doing、verifier のハングの review→blocked は `--worktree` 無しのフェーズ2の呼び出しのまま（D-012 フェーズ5の決定済みの「`--no-model` と `--note` で呼ぶ」に合わせた）。worktree の破棄までまとめたい場合は指示してほしい
4. doing（FAIL の再試行）は、verdict の `task`・`attempt` が一致する FAIL の時だけ行い、それ以外（無い・PASS・attempt 不一致）は終了コード1にした。D-012 に明記が無いので確認したい
5. done でも新規コミットの判定を行い、0件なら review→blocked（question は review と同じ文面）にした（`--no-ff` でマージコミットができない状態で done にしないため。今の run の手順6.3.2と同じ位置づけ）。done では収集コミットをしない（D-012 の決定事項の「verifier がコマンドを実行して生じたファイルがマージに紛れ込まない」に従った）
6. review の差分ゲートの違反が上限に達して blocked にする時も、差し戻しと同じ1行をタスク票の「進捗」に書く前提にした（D-012 は差し戻しの時の書き方だけを決めている）。done の前の差分ゲートの違反は差し戻しではないので「進捗」には書かない
7. 状態のコミットの後で worktree の破棄・後始末（worktree・ブランチの削除）に失敗した時は、標準エラーに警告を出し、終了コードは状態に合わせて 0・3 のままにした（終了コード1は「何もしていない」の意味のため）。別の扱いがよければ指示してほしい
