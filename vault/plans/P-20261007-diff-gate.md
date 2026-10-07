---
id: P-20261007-diff-gate
status: approved
---
# ゴール
差分ゲート diff_gate.py と「成果物」の記法（D-012 フェーズ3）

creator の作業ブランチの差分が、タスク票の「成果物」に宣言されたファイルの範囲に収まっているかを確かめる `scripts/diff_gate.py` を新設する。呼び出しの形は `python3 scripts/diff_gate.py <計画ID> <id> <base> <branch>`。

- `git diff --name-only --no-renames <base> <branch>` で変わったファイルを取り、`git show <base>:vault/tasks/<計画ID>/<id>.md`（base の版）の「成果物」節にあるバッククォートの文字列（末尾が `/` ならディレクトリ）と照らし合わせる
- 宣言外のファイルの変更・自分のタスク票の「進捗」以外の節の変更・`vault/plans/`・`vault/log/`・`vault/verdicts/`・`vault/rules/` 配下の変更（宣言があっても）を違反として `<パス>: <理由>` で1行ずつ出す。`.claude/hooks/`・`.claude/settings.json`・`.claude/agents/` は宣言があれば許す
- 終了コードは 0 違反なし／1 違反あり／2 引数の誤り・base にタスク票が無い・git の失敗。フェーズ4の `transition.py` から `check(root, plan_id, task_id, base, branch)` を import できるようにする

あわせて、タスク票の雛形（`vault/templates/task.md`）・planner の定義（`.claude/agents/planner.md`）・仕様書（`docs/vault-spec.md` の5節）に、「creator が変えるファイルはすべて『成果物』にバッククォートのパスで書く」という記法を足す。このフェーズでは run から呼ばない。`vault/rules/planner/planner.md` は変えない。正本は `vault/designs/D-012.md` の「フェーズ3 差分ゲート diff_gate.py と「成果物」の記法」。

## 分割方針
- T-01 で本体 `scripts/diff_gate.py` を作る。T-02（`scripts/smoke.sh` のケース）は T-01 の後。T-03（雛形）は `diff_gate.py` の名前を書かないので依存無しで、いつでも進められる。T-04（planner の定義）と T-05（仕様書）は `scripts/diff_gate.py` の字句を書くので、smoke の「参照される scripts の存在チェック」のために T-01 の後にする（`.claude/` 配下・`vault/templates/`・`docs/vault-spec.md` に実在しない `scripts/<名前>.py` を書くと fail する）
- 成果物はタスクごとに別ファイルなので、T-01 の後は T-02・T-04・T-05 を（T-03 は最初から）並行で進められる。D-012 の推奨どおり、フェーズ2（P-20261007-transition-basic）の後に進める
- どのタスクも単体でマージして `bash scripts/smoke.sh` が `fail=0` で通る。T-01・T-03・T-04・T-05 は smoke.sh を変えない（pass は計画作成時点の 559 のまま）。T-02 で20件以上足す
- T-01 の動作確認には、planner が置いたフィクスチャ `vault/tasks/P-20261007-diff-gate/fixtures/try.sh` を使う。一時 git リポジトリ（main にタスク票 `vault/tasks/P-TEST/T-01.md`・`T-02.md` とほかのファイル、そこから切ったブランチ `work/b` に preset の変更をコミット）を作って `scripts/diff_gate.py` を1回実行し、終了コード・差分のファイル・`check()` の戻り値のパス・実行前後でリポジトリが変わらないか・標準出力と標準エラーを出す（使い方・preset・宣言の中身はファイル先頭のコメント）。`diff_gate.py` が無い今の状態で、全 preset のセットアップと出力が動くことは確かめてある（`exit=2`、`check_error=ModuleNotFoundError`、`unchanged=yes`）
- smoke（T-02）はこのフィクスチャを使わない。install 先には `vault/tasks/` の計画のファイルが無いため、smoke.sh の中で同じ形の一時リポジトリを作る

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | scripts/diff_gate.py を新設し、作業ブランチの差分を base の版のタスク票の「成果物」と照らし合わせる | |
| T-02 | todo | 0 | T-01 | smoke.sh に diff_gate.py のケースを20件以上足す | |
| T-03 | review | 1 | - | vault/templates/task.md の「成果物」に、変えるファイルをすべてバッククォートのパスで書く記法を足す | |
| T-04 | todo | 0 | T-01 | .claude/agents/planner.md に「成果物」の書き方（変えるファイルをすべてバッククォートのパスで書く）を足す | |
| T-05 | todo | 0 | T-01 | docs/vault-spec.md の5節に「成果物」の記法と diff_gate.py の判定を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` を含み、pass が 579 以上
- `.claude/skills/run/SKILL.md` と `vault/rules/planner/planner.md` は変わっていない（このフェーズでは run から呼ばない。planner への指示は `.claude/agents/planner.md` に書く）

## 次フェーズの候補
- D-012 フェーズ4（`transition.py` に worktree の運用を足す。`diff_gate.check` を import して review・done の前に呼ぶ）。フェーズ5（run の手順の置き換え）はその後

## 人への質問
1. D-012 の決定済みは雛形の記法の例を `` - `scripts/foo.py`（1ファイル） `` としているが、`vault/templates/` 配下は smoke の「参照される scripts の存在チェック」の対象で、実在しない `scripts/foo.py` を書くと smoke が fail する。そこで例を `` - 例：`src/foo.py`（1ファイル） `` に変えた（T-03 の決定済み。`.claude/agents/planner.md` の例も同じ。T-04）。`scripts/` の例にこだわる場合は、存在チェックの側を変えるかどうかの判断が要る
2. `check()` の戻り値は `[(パス, 理由), ...]` のタプルのリスト、base にタスク票が無い・git の失敗の時は例外 `GateError` を送出する形にした（D-012 は「違反のリストを返す」とだけある。フェーズ4で違反のパスを log と「進捗」に書くため、パスを取り出せる形にした）。別の形がよければ指示してほしい
3. 自分のタスク票は、「成果物」に宣言があっても節の判定（「進捗」以外の変更は違反）を優先する前提にした。また、自分のタスク票を消した時も違反にする。D-012 に明記が無いので確認したい
4. 判定の対象は D-012 のとおり `git diff <base> <branch>`（2点の差分）にした。branch が base より後の計画ブランチの変更を含まない（base から切った直後の worktree のブランチ）前提で、フェーズ4では `--plan-head`（creator 起動時の計画ブランチの HEAD）を base に渡す想定
