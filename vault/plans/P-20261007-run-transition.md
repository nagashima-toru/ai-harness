---
id: P-20261007-run-transition
status: approved
---
# ゴール
run の手順を transition.py に置き換える（D-012 フェーズ5）

`.claude/skills/run/SKILL.md` の状態変更を、`scripts/transition.py` の呼び出しに置き換える。次の各場面を、それぞれ transition.py の1コマンドにする。
- 手順2の todo→doing の一括反映
- 手順3〜4の blocked・review（creator の完了直後の収集コミットと差分ゲートを含む）
- 手順6の PASS（マージ・done・後始末）と FAIL（再試行、上限なら blocked）
- 中断からの再開と、ハングした時の復旧

あわせて、計画票のタスク表を Edit で書き換える指示と、log に printf で追記する指示を消す。verifier は、creator の成果物がコミット済みの worktree を検証することになる。`.claude/agents/verifier.md` と `docs/vault-spec.md` の記述をこの流れに合わせる。`vault/rules/` の記述は、このフェーズでは直さない（D-013 フェーズ4で扱う）。

正本は `vault/designs/D-012.md` の「フェーズ5 run の手順を transition.py に置き換える」（ゴール文・受け入れ基準の候補・決定済み）と「今回やらないこと」。

## 分割方針
- `.claude/skills/run/SKILL.md` は1ファイルの大きな書き換えなので、節ごとに5タスク（T-01〜T-05）に分け、直列の依存にする（同じファイルを触るので並行にしない）
  - T-01：呼び出しの早見表（7つの呼び出しの形と終了コード0〜4ごとの次の行動）を新設し、0・0.5節と手順2の着手（todo→doing）を置き換える
  - T-02：手順3（分岐元の不一致・creator の blocked 報告・再開情報の記録行）と手順4（review）を置き換える
  - T-03：手順6（PASS の done、FAIL の doing）を置き換える
  - T-04：手順2の中断からの再開と「ハング時の復旧」を置き換える
  - T-05：手順7・8・「回帰確認」・「注意」を直し、ファイル全体の grep（printf・`>>`・個別の git 操作・「status を」の言い回し）を空にする
- この順にしたのは、途中の版で run が矛盾しないため。transition.py は推奨の経路で、手動の Edit・printf も従来どおり動く。前から順に置き換えれば、置き換えた手順が後ろの手動の手順の前提を壊さない（T-02 で review の時に収集コミットを行うようになり、T-03 の done は収集しないので、T-02 を T-03 より先にする。T-02 の後・T-03 の前の版では、手順6.3.1 の収集が「残りが無ければ何もしない」で済む）
- 各タスクの受け入れ基準の grep は、そのタスクが受け持つ節だけを `sed -n '/^## 3\./,/^## 5\./p'` のように切り出して数える。ファイル全体の grep は最後の T-05 で空にする
- T-06（`.claude/agents/verifier.md`）は、「worktree の変更は verifier の前にコミット済み」が成り立つ T-02 の後に、T-03〜T-05 と並行で進められる（別ファイル）
- T-07（`docs/vault-spec.md`）は新しい流れ全体を書くので T-05 の後。1・2・7節に加え、置き換えで古くなる5節の「今の `/run` はまだどちらも呼ばない」と12節の「run/SKILL.md 手順6.3.4 のとおり」も文言だけ直す
- どのタスクも `scripts/smoke.sh` を変えない。単体でマージして `bash scripts/smoke.sh 2>&1 | tail -1` が `smoke: pass=654 fail=0`（計画作成時点）のまま通る。smoke の (ms-3) は `run/SKILL.md` に `creator=`・`verifier=` の文字列があることを見ているので、0.5節を書き換えても両方の語を残す。「参照される scripts の存在チェック」は、文書に書いた `scripts/*.sh|py` が install 先にあることを見る（transition.py・discard_worktree.sh・current_plan.sh・vcs_finish.sh などはある。無いスクリプト名を書かない）
- 呼び出しの形の確認には、前の計画のフィクスチャ `vault/tasks/P-20261007-transition-worktree/fixtures/try.sh` を使ってよい（成果物ではない。このフェーズでは新しいフィクスチャを置かない）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | run/SKILL.md に transition.py の早見表を足し、0・0.5節と手順2の着手を置き換える | |
| T-02 | todo | 0 | T-01 | run/SKILL.md の手順3（blocked・記録行）と手順4（review）を transition.py に置き換える | |
| T-03 | todo | 0 | T-02 | run/SKILL.md の手順6（PASS の done・FAIL の doing）を transition.py に置き換える | |
| T-04 | todo | 0 | T-03 | run/SKILL.md の中断からの再開とハング時の復旧を transition.py に置き換える | |
| T-05 | todo | 0 | T-04 | run/SKILL.md の手順7・8・回帰確認・注意を直し、全体から printf と個別の git 操作を消す | |
| T-06 | todo | 0 | T-02 | verifier.md の手順10を「worktree の変更は verifier の前にコミット済み」の前提に直す | |
| T-07 | todo | 0 | T-05 | docs/vault-spec.md の1・2・7節（と5・12節の古い参照）を transition.py を使う run の流れに合わせる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `grep -nE '>>|printf' .claude/skills/run/SKILL.md` と `grep -nE 'git merge --no-ff|git worktree remove|git branch -d' .claude/skills/run/SKILL.md` が空
- `bash scripts/smoke.sh 2>&1 | tail -1` が `smoke: pass=654 fail=0`
- `vault/rules/` と `scripts/` は変わっていない（`git status --porcelain -- vault/rules scripts` が空）

## 次フェーズの候補
- D-013（D-012 を全フェーズ終えてから。`vault/rules/` の「未コミット分は PASS の後にコミットする」の記述の修正は D-013 フェーズ4）
- フェーズ5のマージ後の最初の計画の `/run` で、人が通しの動作（着手→review→done、差し戻し、FAIL の再試行）を確かめる

## 人への質問
計画は次の前提で書いた。違う場合は承認前に指示してほしい。
1. 手順3.6（worktree の分岐元が計画ブランチと一致しない）は、creator の blocked 報告と同じ `blocked --question-file <質問ファイル> --worktree <worktree> --branch <branch> --plan-head <PLAN_HEAD>` で呼ぶ前提にした（再開情報の記録行が残り、worktree も残るため）。この呼び出しでは log の行に `creator=<モデル>` が自動で付く。D-012 にこの場面の明記は無い
2. 手順6.1 の「verdict を worktree 側からコピーした」log の行（今は printf で追記）は、書かないことにした。`cp` でメインリポジトリ側へコピーすることは残す。コピーした verdict は done のコミットに含まれるので、証跡は git に残る。log に残したい場合は transition.py に機能を足す別の計画が要る
3. `--worktree` 無しの blocked・doing（再開・ハング・worktree が無い時）の終了コードは、transition.py の実装どおり 0 になる（3・4 になるのは `--worktree` 付きの時だけ）。早見表の終了コードの表には「`--worktree` 無しの呼び出しは成功すると 0」と書く前提にした
4. 再試行の上限の判断（attempt が `HARNESS_MAX_ATTEMPTS` 未満なら doing、達していれば blocked）は、`--worktree` 無しの呼び出しでは今までどおり run が行う（transition.py は上限を超える doing を終了コード1で拒否するだけで、blocked には切り替えない）前提にした。`--worktree` 付きの review・doing は transition.py が自分で判断する
5. verifier.md の手順10の宣言外の検査は、変更ファイルの一覧を `git diff --name-only <起点コミット>..HEAD` だけで取り、`git status --porcelain` の未コミットのファイルは合わせない前提にした（未コミット分は transition.py の done でマージされないため。verifier が確認コマンドの実行で作ったファイルを宣言外として拾わないため）。検査そのものの廃止は D-012 の「今回やらないこと」なので残す
6. `docs/vault-spec.md` は D-012 の指定（1・2・7節）に加え、置き換えで誤りになる5節の「今の `/run` … はまだどちらも呼ばない」と12節の「run/SKILL.md 手順6.3.4 のとおり」も T-07 で文言だけ直す前提にした
7. creator の差し戻し（終了コード3）や FAIL の再試行で creator を呼び直す時は、手順3.1 から `PLAN_HEAD` を取り直す（transition.py のコミットで計画ブランチの HEAD が進むため）前提にした
