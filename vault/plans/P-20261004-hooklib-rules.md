---
id: P-20261004-hooklib-rules
status: draft
---
# ゴール
設計文書 `vault/designs/D-011.md` の「フェーズ2 複製間でずれていた解析規則の統一」を行う。

3フックと2スクリプトで食い違っている計画票・タスク票の解析規則を、寛容な側に揃えて `_hooklib.py` に1本化する。
1. 受け入れ基準の行数は、「## 受け入れ基準」節で行頭が `- ` か `数字. ` の行を数える（`plan_guard.py` の `count_criteria` の規則）。`stop_gate.py` の verdict 形式検査もこれを使う
2. frontmatter の `id`・`status` の値は、前後の `"`・`'` を外して読む。`plan_id_and_status` と `frontmatter_status` を同じ規則にし、`scripts/current_plan.sh`・`scripts/archive_plans.sh` の awk も合わせる
3. タスク表の行は行頭の空白を許す（`stop_gate.py` の `parse_tasks` を `plan_guard.py` の規則に揃える）

揃えた関数は `_hooklib.py` に置き、各フックの複製を消す。`docs/vault-spec.md` の該当節に規則を明記する。

D-011 の決定事項の表、フェーズ2の「決定済み」、「今回やらないこと」を前提にする。Bash 判定の一本化（フェーズ3）は含めない。

## 分割方針
- 現状（planner が読み取り専用で確かめた事実。2026-10-04 時点の main = 18bf979）
  - フェーズ1は main にマージ済み。`.claude/hooks/_hooklib.py` があり、3フックが `import _hooklib as H` で使っている。smoke は `pass=507 fail=0`
  - 受け入れ基準の数え方がずれている
    - `stop_gate.py` の `count_acceptance_criteria(task_path)` は、行頭 `- ` だけを数える
    - `plan_guard.py` の `count_criteria(text)` は、行頭 `- ` と `数字. ` を数える
  - frontmatter の読み方がずれている
    - `_hooklib.plan_id_and_status` は `^---\n(.*?)\n---\n` の正規表現で frontmatter を探し、値の引用符を外さない（`status: "approved"` は `"approved"` になる）
    - `_hooklib.frontmatter_status` は1行目の `---` から次の `---` までを読み、引用符を外す
    - 前者は `approved_plans`（3フックの「自分の計画票」の検出）と plan_guard の粒度検査で使われ、後者は承認の裏付け検査で使われている
  - `scripts/current_plan.sh` と `scripts/archive_plans.sh` の `fm_status` の awk は、引用符を外さない。`current_plan.sh` の4行目のコメントは「plan_guard.py の plan_id_and_status と同じ」と書いてあり、フェーズ1以降は実態と合っていない
  - タスク表の行の読み方がずれている
    - `stop_gate.py` の `parse_tasks` は `line.startswith("|")` で、行頭の空白を許さない
    - `plan_guard.py` の `parse_tasks` は `H.raw_rows`（strip してから判定）を使い、行頭の空白を許す
    - `agent_write_guard.py` の `plan_task_status` は、plan_guard と同じ「raw_rows → 5列未満を捨てる → 6列に埋める」処理を自前で持っている（`PLAN_TASK_COLUMNS`）
  - smoke の `expect_eq` は1055行目で定義されていて、stop_gate 節（70行目）より後ろにある。新しいケースは末尾にまとめて置く
- 確認用のフィクスチャ（planner が作成済み）
  - verifier は repo の外に書けず、作業ツリーは未コミットのまま検証されるので、確認コマンドで使うフィクスチャを `vault/tasks/P-20261004-hooklib-rules/fixtures/` に置いた
    - `fixtures/vault/plans/P-FIXTURE-QUOTED.md`：`id: 'P-FIXTURE-QUOTED'`・`status: "approved"`、タスク表の2行を半角空白でインデント（T-01 は doing、T-02 は question が空の blocked）
    - `fixtures/numbered-criteria.md`：受け入れ基準が `1. `〜`3. ` と `- ` の4行（今の stop_gate は1行と数える）
  - 本物の計画票・タスク票ではない。フックは `vault/plans/*.md` と `vault/tasks/<計画ID>/<id>.md`（1階層）しか見ないので、ここに置いても判定に影響しない。どのタスクもこのフィクスチャを編集しない
  - `stop_gate.py` は最初に未コミット検査をするので、フィクスチャに対して `main()` をそのまま動かすと「未コミットの変更があります」で止まる。確認コマンドでは `runpy` で読み込み、`main.__globals__['has_uncommitted_changes']` を差し替えてから呼ぶ
- タスクの分け方
  - T-01 で `_hooklib.py` に、揃えた規則の関数（`parse_tasks`・`count_criteria`・`frontmatter_value`）を置き、`plan_id_and_status`・`frontmatter_status` を同じ規則にする。この時点で (2) の frontmatter の統一は3フックに効く
  - T-02〜T-04 で、フックごとに複製を消して `H.` の関数に置き換える。成果物のファイルが違うので、T-01 の後は並行してよい。(1)・(3) は T-02（stop_gate.py）で効く
  - T-05 は2スクリプトの awk。Python 側と独立しているので依存なし（T-01 と並行してよい）。2ファイルだが「同じ1行の処理を足す」1つの変更として1タスクにする
  - smoke.sh への追加は T-06、docs は T-07 にまとめる。smoke.sh と docs を触るタスクは1つずつにして、編集の競合を避ける。どちらも T-02〜T-05 の後
  - T-05 の archive_plans.sh の変更は、`fm_status` がスクリプト内の関数で単体では呼べないため、動作の確認は T-06 の smoke のケースで行う
- 確認コマンドで `_hooklib` を import する時は `python3 -B` を使う。構文の確認は `ast.parse` で行い、`py_compile` は使わない（`__pycache__` を作るため）
- 既存の smoke の期待値は変えない方針。ただし、寛容側に揃えた帰結で既存のケースが落ちた場合は、そのタスクを blocked にして question に書く（smoke.sh を直せるのは T-06 だけのため）。D-011 は「帰結を確かめた上で期待値を直してよい。直したケースは PR 本文に列挙する」としているので、人の判断で T-06 に回す

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | _hooklib.py に parse_tasks・count_criteria・frontmatter_value を置き frontmatter の読み方を揃える | |
| T-02 | todo | 0 | T-01 | stop_gate.py の parse_tasks・count_acceptance_criteria を _hooklib の関数に置き換える | |
| T-03 | todo | 0 | T-01 | plan_guard.py の parse_tasks・count_criteria を _hooklib の関数に置き換える | |
| T-04 | todo | 0 | T-01 | agent_write_guard.py の plan_task_status を _hooklib.parse_tasks で書き直す | |
| T-05 | todo | 0 | - | current_plan.sh と archive_plans.sh の frontmatter の awk で値の引用符を外す | |
| T-06 | todo | 0 | T-02,T-03,T-04,T-05 | smoke.sh に番号付き基準・引用符付き status・インデントした行のケースを足す | |
| T-07 | todo | 0 | T-02,T-03,T-04,T-05 | docs/vault-spec.md に統一した解析規則を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 揃えた関数が `_hooklib.py` にだけ定義されている：`grep -lE '^def (parse_tasks|count_criteria|count_acceptance_criteria|frontmatter_value|frontmatter_status|plan_id_and_status)\(' .claude/hooks/agent_write_guard.py .claude/hooks/plan_guard.py .claude/hooks/stop_gate.py .claude/hooks/_hooklib.py` の出力が `.claude/hooks/_hooklib.py` の1行だけ
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` を含み、pass が513以上

## 次フェーズの候補（票は起こさない）
- D-011 フェーズ3（agent_write_guard.py の Bash 書き込み判定の一本化）。フェーズ2と同じく `docs/vault-spec.md` を編集するので、フェーズ2のマージ後に始める

## 人への質問
- `scripts/archive_plans.sh` の `table_counts` の awk も、タスク表の行を `^\|` でしか拾わない（行頭の空白を許さない。「## タスク表」節にも限定していない）。D-011 の (3) は `stop_gate.py` の `parse_tasks` だけを対象にしているので、この計画では触らない。インデントした行が done でない計画は「全行 done」と数えられうるが、揃える必要はあるか（あれば T-05 に足すか、次の計画にする）
- awk 側は D-011 の決定どおり「引用符を外す処理を足すだけ」にするので、`status: approved # メモ` のように値の後ろに語が続く行は、awk では読まず、Python（先頭の語を読む）では `approved` と読む差が残る。このままでよいか
- 確認用のフィクスチャを `vault/tasks/P-20261004-hooklib-rules/fixtures/` に置いた（分割方針を参照）。計画票・タスク票と一緒にコミットされ、archive の時は計画のタスク票と一緒に移る。この置き方でよいか
