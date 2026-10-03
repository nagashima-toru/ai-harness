---
id: P-20261003-archive-old-logs
status: draft
---
# ゴール
古い計画（計画票が `status: done` で、PR がマージ済みのもの）の一式を `vault/archive/<年-月>/` に移すための安全な手順（スクリプト `scripts/archive_plans.sh`）を作り、それを使って古い形式の log（`creator=` が無い遷移行の log）を `scripts/model_stats.py` の既定の集計から外す。

人の発言（変えない）：「古い形式（`creator=` が無い遷移行）のものって残ってるの？ アーカイブしちゃえば？」

## 分割方針
- 現状（planner が読み取り専用で確認した事実。2026-10-03 時点）
  - `vault/log/` は54ファイル。`creator=` が1つも無い log は43ファイル（`grep -L 'creator=' vault/log/*.md | grep -c .` が 43）。`creator=` の無い `doing→review`・`doing→blocked` 行は151行で、すべてこの43ファイルにある。ゴール文の「44ファイル」は実測では43ファイルだった
  - 43ファイルの内訳：`P-20260920-*` 3件・`P-20260924-*` 13件・`P-20260925-*` 10件・`P-20260926-*` 9件・`P-20260927-*` 2件・`P-20260929-*` 1件・`P-20260930-*` 4件・`P-20261001-unattended-wrapper` 1件。どれも計画票が `status: done`・タスク表が全行 `done` で、`main` にも `status: done` の計画票がある（マージ済み）
  - `python3 scripts/model_stats.py`（既定）の現在の出力は `sonnet 44`・`unknown 131`。新しい形式の11ファイル（`P-20261001-generic-rules` 以降）だけを渡すと `sonnet 44` だけになる
- 既存の archive と runbook の照合で分かったこと
  - `docs/runbook.md` 5節の手動手順は、計画票と log がどちらも `<計画ID>.md`、タスク票と verdict のディレクトリがどちらも `<計画ID>` で、同じ `vault/archive/<年-月>/` 直下に移すと名前が衝突する（2つ目の `git mv` が失敗する）
  - 既存の `vault/archive/2026-09/` は種別ごとのサブディレクトリ（`plans/`・`tasks/`・`verdicts/`・`log/`）になっている
  - そこで配置は `vault/` と同じ形の `vault/archive/<年-月>/plans/<計画ID>.md`・`tasks/<計画ID>/`・`verdicts/<計画ID>/`・`log/<計画ID>.md` に決める。log のファイル名が `<計画ID>.md` のまま残るので、`python3 scripts/model_stats.py vault/archive/*/log/*.md` で計画 ID を取った集計がそのまま行える
  - `<年-月>` は計画 ID の日付部分（`P-20260924-...` なら `2026-09`）から決める。移した日付に依らず、何度実行しても同じ場所になる。日付部分の無い旧形式の ID（`P-019` など）は対象外として拒否する
- フックとの関係（コードを読んで確かめたこと。`.claude/hooks/` と `.claude/settings.json` は触らない：issue #85）
  - `agent_write_guard.py` は creator の `vault/plans/`・`vault/log/` への書き込みを拒否する。アーカイブはこの2か所からファイルを移すので、creator がスクリプトを実行すると、フックが見えない経路（`bash` 経由のスクリプト内の `git mv`）でこの禁止を回避することになる。done のタスク票・verdict の編集禁止も同じ（直接の `git mv vault/tasks/<計画ID>/T-01.md ...` は拒否されるが、ディレクトリ単位やスクリプト内では検知されない）
  - そのため、実際の移動（`--apply`）は**人が手元で PR ブランチ上で実行する**。エージェント（creator を含む）は `--dry-run` だけを実行する。`vault/rules/` の提案ファイル方式と同じ発想
  - `stop_gate.py`・`plan_guard.py`・`scripts/current_plan.sh` は `vault/plans/*.md`（approved の計画票と、HEAD との比較）しか見ないので、done の計画票が `vault/plans/` から消えても判定は変わらない
  - `agent_write_guard.py` の done 判定は `^vault/tasks/`・`^vault/verdicts/` と `vault/plans/<計画ID>.md` を前提にしているので、アーカイブ後のファイルは done 判定の対象外になる（保護が外れる）。これは仕様に明記する（T-04）
- 安全装置（スクリプトの条件。詳細は T-01 の「決定済み」）：計画票が `status: done`・タスク表が全行 `done`・基準ブランチ（既定 `main`）にも `status: done` の計画票がある（＝ PR がマージ済み）・現在のブランチの計画ではない・移動元に未コミットの変更が無い・移動先が無い。1件でも満たさなければ何も移さない。`--dry-run` と `--apply` のどちらかを必ず指定する
- 「PR がマージ済み」はスクリプトからは直接分からないので、人が計画 ID を引数（またはファイル）で渡し、スクリプトは `git show main:vault/plans/<計画ID>.md` が `status: done` であることで確認する。計画票は PR のマージでしか `main` に入らないため、これで「マージ済み」とみなせる。`git branch --merged main` はブランチを消した後の計画を判定できないので使わない
- タスクの分け方：T-01 でスクリプト本体、T-02 で smoke.sh のテスト、T-03〜T-05 で文書（runbook・vault-spec・decisions）、T-06 で移す対象の一覧を確定して `--dry-run` で検査する。データの移動はタスクにしない（上記のとおり人が行う）
- 移動後に人が行うこと（タスク外。この計画の PR ブランチ上で、run が終わって PR ができた後に行う）
  1. `bash scripts/archive_plans.sh --dry-run --from-file vault/tasks/P-20261003-archive-old-logs/T-06-targets.txt` で内容を確かめる
  2. `bash scripts/archive_plans.sh --apply --from-file vault/tasks/P-20261003-archive-old-logs/T-06-targets.txt` で移す
  3. `git commit` して PR ブランチに push する
- 移動後の `model_stats.py` の既定の集計（人への質問1で A を選んだ場合）：`unknown` の行が消える（131 → 0）。`sonnet` は44件のまま減らず、この計画のタスク（`creator=sonnet` で終わったもの）の分だけ増える。`1回目 PASS 率` などの率は `sonnet` の行は変わらない。B を選んだ場合は `sonnet` の44件も archive に移り、既定の集計はこの計画の分だけになる
- smoke.sh の model_stats 節への影響：(ms-1)・(ms-5) はフィクスチャ、(ms-2) の後半は一時ディレクトリを使うので影響しない。(ms-2) の「引数なしの実行が現在の vault/log に対して終了コード0」は、log が0件でも見出し行だけを出して終了コード0なので、A・B どちらでも通る

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | 計画一式を archive に移す scripts/archive_plans.sh を作る | |
| T-02 | todo | 0 | T-01 | smoke.sh に archive_plans.sh の節を足す | |
| T-03 | todo | 0 | T-01 | runbook 5節の手動手順を archive_plans.sh の手順に置き換える | |
| T-04 | todo | 0 | T-01 | vault-spec の archive の説明を配置とスクリプトに合わせる | |
| T-05 | todo | 0 | T-01 | decisions.md に archive をスクリプト化した判断の行を足す | |
| T-06 | todo | 0 | T-01,T-02 | 移す対象の計画 ID 一覧を確定し dry-run で検査する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わる
- `bash scripts/archive_plans.sh --dry-run --from-file vault/tasks/P-20261003-archive-old-logs/T-06-targets.txt` が `NG` の行を出さない（実際の移動は人が行う）

## 人への質問
1. アーカイブの対象をどちらにするか（T-06 の一覧と件数がこれで決まる）。おすすめは A
   - A：古い形式の log を持つ計画だけ（43件。`creator=` が1つも無い log の計画）
     - 利点：人の発言（「古い形式のものってアーカイブしちゃえば？」）とゴール（古い形式の log を既定の集計から外す）にそのまま合う。`unknown` が0になり、`sonnet` の44件は既定の集計に残るので、`model_stats.py` で creator のモデルを見直す材料が減らない
     - 欠点：`vault/` を軽くする効果は43件分だけで、新しい形式の11件（2026-10-01 以降）は `vault/plans/` などに残る。次からは月次で B の形に移る運用を runbook に書く必要がある（T-03 で「月次で done かつマージ済みを移す」と書く）
   - B：done かつマージ済みの全部（現在の計画を除く。日付部分の無い `P-019`〜`P-021` はスクリプトが受け付けないので対象外）
     - 利点：`vault/` が一番軽くなり、runbook 5節の「月次で done を移す」運用と一致する
     - 欠点：`sonnet` の44件も既定の集計から外れ、既定の `model_stats.py` は当面この計画の分しか出さない（`vault/archive/*/log/*.md` を引数で渡せば集計はできる）。集計の目的（creator のモデルの見直し）にはサンプルが減って不利
2. アーカイブ後のファイル（`vault/archive/` 配下）は、`agent_write_guard.py` の done 判定（done のタスク票・verdict の編集禁止）の対象外になる。フックは触らない制約（issue #85）があるので、この計画では仕様（T-04）に明記するだけにし、フック側の保護は別の計画に回してよいか。おすすめは「明記だけにして別の計画に回す」（archive は人が移した後に誰も書かない運用で、移動自体も人が行うため）

## 次フェーズの候補
- `agent_write_guard.py` の done 判定を `vault/archive/<年-月>/{tasks,verdicts}/` にも広げる（issue #85 の制約が外れた後）
