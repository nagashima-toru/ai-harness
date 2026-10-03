---
id: P-20261003-archive-old-logs
status: approved
---
# ゴール
古い計画（計画票が `status: done` で、PR がマージ済みのもの）の一式を `vault/archive/<年-月>/` に移すための安全な手順（スクリプト `scripts/archive_plans.sh`）を作り、それを使って古い形式の log（`creator=` が無い遷移行の log）を `scripts/model_stats.py` の既定の集計から外す。

人の発言（変えない）：「古い形式（`creator=` が無い遷移行）のものって残ってるの？ アーカイブしちゃえば？」

人の回答（対象の選び方。変えない）：「B の変形」。done かつ main でもマージ済みの計画のうち、新しい順に5件を残し、それより古い全部を移す。現在のブランチの計画は常に残す。「新しい」の基準は一意に決めて決定済みに書く。残す件数は引数（`--keep <N>`、既定5）にしてよい。

## 分割方針
- 現状（planner が読み取り専用で確認した事実。2026-10-03 時点）
  - `vault/log/` は54ファイル（この計画の log はまだ無い）。`creator=` が1つも無い log は43ファイル（`grep -L 'creator=' vault/log/*.md | grep -c .` が 43）。`creator=` の無い `doing→review`・`doing→blocked` 行は151行で、すべてこの43ファイルにある。ゴール文の「44ファイル」は実測では43ファイルだった
  - `vault/plans/` の計画 ID が日付形式（`P-YYYYMMDD-...`）の計画票は55件。このうちこの計画以外の54件は、作業ツリーでも `main` でも `status: done`、タスク表は全行 `done`、log がある
  - `python3 scripts/model_stats.py`（既定）の現在の出力は `sonnet 44`・`unknown 131`
- 「新しい」の基準：`vault/log/<計画ID>.md` の最初の日時行（`- YYYY-MM-DD HH:MM ` で始まる最初の行）の日時。新しい log は `draft→approved` の行、古い log は `todo→doing` の行が最初になる。日時が同じなら計画 ID の文字列順で後ろのものを新しいとみなす（一意に決まる）。54件の最初の日時行に重複は無い（`grep -m1 -oh '^- [0-9-]* [0-9:]*' vault/log/*.md | sort | uniq -d` が空）。main への取り込み順（git の履歴）は、マージの形（squash・merge commit）で取り方が変わり、一時リポジトリで再現しにくいので採らない
- 現在のブランチの計画は「残す5件」に数えない。候補（移すか残すかを決める母集団）から最初に外す。通常は main に無いので自然に外れるが、マージ後にブランチが残っている場合も外す
- この基準での新しい5件（残す）：`P-20261003-guard-rules-path-text`（10-03 11:12）・`P-20261003-planner-no-tmp-redirect`（10-03 10:46）・`P-20261003-model-stats-blocked-creator`（10-03 08:11）・`P-20261003-run-finish-verifier-worktree`（10-03 01:04）・`P-20261002-verify-cmd-guard-align`（10-02 17:36）。6件目は `P-20261002-smoke-tmp-unique`（10-02 15:07）で、ここから下を移す
- 移す対象：54件 − 5件 = 49件。移動は計画票49・タスク票のディレクトリ49・verdict のディレクトリ48（`P-20260924-worktree-isolation-guard` は verdict が無い）・log 49 の計195件
- 移動後の `model_stats.py` の既定の集計（planner が残す5件の log を引数に渡して実際に数えた値）：`sonnet 14 1.00 1.00 0.00` の1行だけになる。`unknown` は 131 → 0（残す5件の log の `doing→review`・`doing→blocked` 行はすべて `creator=` 付きで、付いていない行は0行）。`sonnet` は 44 → 14 に減り、この計画のタスク（`creator=sonnet` で終わったもの）の分だけ増える。archive 分も含めて見る時は `vault/archive/*/log/*.md` を引数で渡す
- 既存の archive と runbook の照合で分かったこと
  - `docs/runbook.md` 5節の手動手順は、計画票と log がどちらも `<計画ID>.md`、タスク票と verdict のディレクトリがどちらも `<計画ID>` で、同じ `vault/archive/<年-月>/` 直下に移すと名前が衝突する（2つ目の `git mv` が失敗する）
  - 既存の `vault/archive/2026-09/` は種別ごとのサブディレクトリ（`plans/`・`tasks/`・`verdicts/`・`log/`）になっている
  - そこで配置は `vault/` と同じ形の `vault/archive/<年-月>/plans/<計画ID>.md`・`tasks/<計画ID>/`・`verdicts/<計画ID>/`・`log/<計画ID>.md` に決める。log のファイル名が `<計画ID>.md` のまま残るので、`python3 scripts/model_stats.py vault/archive/*/log/*.md` で計画 ID を取った集計がそのまま行える
  - `<年-月>` は計画 ID の日付部分（`P-20260924-...` なら `2026-09`）から決める。移した日付に依らず、何度実行しても同じ場所になる。日付部分の無い旧形式の ID（`P-019`〜`P-021`）は候補に入れない（残る）
- フックとの関係（コードを読んで確かめたこと。`.claude/hooks/` と `.claude/settings.json` は触らない：issue #85）
  - `agent_write_guard.py` は creator の `vault/plans/`・`vault/log/` への書き込みを拒否する。アーカイブはこの2か所からファイルを移すので、creator がスクリプトを実行すると、フックが見えない経路（`bash` 経由のスクリプト内の `git mv`）でこの禁止を回避することになる。done のタスク票・verdict の編集禁止も同じ（直接の `git mv vault/tasks/<計画ID>/T-01.md ...` は拒否されるが、ディレクトリ単位やスクリプト内では検知されない）
  - そのため、実際の移動（`--apply`）は**人が手元で PR ブランチ上で実行する**。エージェント（creator を含む）は `--list` と `--dry-run` だけを実行する。`vault/rules/` の提案ファイル方式と同じ発想
  - `stop_gate.py`・`plan_guard.py`・`scripts/current_plan.sh` は `vault/plans/*.md`（approved の計画票と、HEAD との比較）しか見ないので、done の計画票が `vault/plans/` から消えても判定は変わらない
  - `agent_write_guard.py` の done 判定は `^vault/tasks/`・`^vault/verdicts/` と `vault/plans/<計画ID>.md` を前提にしているので、アーカイブ後のファイルは done 判定の対象外になる（保護が外れる）。これは仕様に明記する（T-04）。`vault/archive/` は参照用で消してよいので、フック側の対応は行わない（人への質問2の回答）
- 安全装置（詳細は T-01 の「決定済み」）：候補は「計画票が `status: done`・タスク表が全行 `done`・基準ブランチ（既定 `main`）にも `status: done` の計画票がある（＝ PR がマージ済み）・log に日時行がある・現在のブランチの計画ではない」の全部を満たすものだけ。候補を新しい順に並べて `--keep`（既定5）件を残し、残りを移す。候補が `--keep` 件以下なら何も移さない。移すものに未コミットの変更がある・移動先が既にある、のどれか1件でもあれば何も移さない。`--list`・`--dry-run`・`--apply` のどれか1つを必ず指定する
- 「PR がマージ済み」はスクリプトからは直接分からないので、`git show main:vault/plans/<計画ID>.md` が `status: done` であることで確認する。計画票は PR のマージでしか `main` に入らないため、これで「マージ済み」とみなせる。`git branch --merged main` はブランチを消した後の計画を判定できないので使わない
- タスクの分け方：T-01 でスクリプト本体、T-02 で smoke.sh のテスト、T-03〜T-05 で文書（runbook・vault-spec・decisions）、T-06 で移す対象の一覧を確定して `--dry-run` で検査する。データの移動はタスクにしない（上記のとおり人が行う）
- 移動後に人が行うこと（タスク外。この計画の PR ブランチ上で、run が終わって PR ができた後に行う）
  1. `bash scripts/archive_plans.sh --dry-run --from-file vault/tasks/P-20261003-archive-old-logs/T-06-targets.txt` で内容を確かめる
  2. `bash scripts/archive_plans.sh --apply --from-file vault/tasks/P-20261003-archive-old-logs/T-06-targets.txt` で移す
  3. `git commit` して PR ブランチに push する
- smoke.sh の model_stats 節への影響：(ms-1)・(ms-5) はフィクスチャ、(ms-2) の後半は一時ディレクトリを使うので影響しない。(ms-2) の「引数なしの実行が現在の vault/log に対して終了コード0」は、log が何件でも（0件でも見出し行だけを出して）終了コード0なので通る

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | 計画一式を archive に移す scripts/archive_plans.sh を作る | |
| T-02 | review | 1 | T-01 | smoke.sh に archive_plans.sh の節を足す | |
| T-03 | review | 1 | T-01 | runbook 5節の手動手順を archive_plans.sh の手順に置き換える | |
| T-04 | review | 1 | T-01 | vault-spec の archive の説明を配置とスクリプトに合わせる | |
| T-05 | todo | 0 | T-01 | decisions.md に archive をスクリプト化した判断の行を足す | |
| T-06 | todo | 0 | T-01,T-02 | 移す対象の計画 ID 一覧を確定し dry-run で検査する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わる
- `bash scripts/archive_plans.sh --dry-run --from-file vault/tasks/P-20261003-archive-old-logs/T-06-targets.txt` が `NG` の行を出さず、移動行を195行出す（実際の移動は人が行う）

## 人への質問
1. （回答済み）アーカイブの対象：人の回答は「B の変形」。done かつ main でもマージ済みの計画のうち、新しい順に5件を残し、それより古い全部を移す。基準と件数は「分割方針」と T-01・T-06 の「決定済み」に反映した
2. （回答済み）アーカイブ後のファイル（`vault/archive/` 配下）の保護：人の回答は「`vault/archive/` 配下はいざという時の参照用で、消しても問題ない。編集のチェックは不要」。フック側の対応は行わない（別の計画も作らない）。仕様（T-04）には、done 判定の対象外であることに加えて、参照用で消してよい旨を書く
