---
id: P-20261004-hooklib-extract
status: approved
---
# ゴール
設計文書 `vault/designs/D-011.md` の「フェーズ1 共通モジュール `_hooklib.py` の導入と .git 判定の修正」を行う。

`.claude/hooks/_hooklib.py` を新しく作る。3フック（`agent_write_guard.py`・`plan_guard.py`・`stop_gate.py`）に、中身が同じまま複製されている関数（`existing_ancestor`・`git_toplevel`・`delegate_to_worktree`（委譲先のスクリプト名を引数にする）・`plan_id_and_status`・`approved_plans`・`raw_rows`（`agent_write_guard.py` の `plan_raw_rows` を含む）・`frontmatter_status`・`human_messages`・`is_approve_command`・`is_unblock_command`）をそこへ移し、各フックは import して使う。`_hooklib` の import に失敗した時は、各フックが終了コード2で終わる（Stop フックは `stop_hook_active` の時だけ exit 0）。あわせて、`stop_gate.py` の `has_uncommitted_changes` は `.git` がディレクトリかどうかで git リポジトリかを判定している。これを `git rev-parse --is-inside-work-tree` に直し、worktree（`.git` がファイル）でも未コミット検査が効くようにする。「フック間で import しない」と書いている `docs/vault-spec.md` の記述と各フックの docstring を更新する。

D-011 の決定事項の表と「今回やらないこと」を前提にする。規則のずれの統一（フェーズ2）と Bash 判定の一本化（フェーズ3）は含めない。

## 分割方針
- 現状（planner が読み取り専用で確かめた事実。2026-10-04 時点）
  - 移す10関数は、複製の間で本体が完全に同じ。違うのは docstring（「コピー」「import しない」の注記）と、`delegate_to_worktree` の委譲先スクリプト名だけ。`plan_raw_rows`（agent_write_guard.py）と `raw_rows`（plan_guard.py）は本体が同じ
  - フックごとの複製の内訳
    - agent_write_guard.py に8つ：existing_ancestor・git_toplevel・delegate_to_worktree・plan_raw_rows・frontmatter_status・human_messages・is_approve_command・is_unblock_command
    - plan_guard.py に10個すべて
    - stop_gate.py に5つ：existing_ancestor・git_toplevel・delegate_to_worktree・plan_id_and_status・approved_plans
  - smoke.sh は今 `pass=499 fail=0`（約90秒）。リポジトリ外から3フックの関数を import しているスクリプトは無い
  - `.claude/hooks/__pycache__/` は、過去に手で import した時の残骸が既にある（gitignore 対象）。D-011 の候補にある「smoke 前に削除して `test ! -e`」は verifier が削除できないので使わない。代わりに、一時ディレクトリへ複製したフックを実行して `__pycache__` ができないことを smoke のケースで確かめる（T-05）。各フックのタスクでは、`_hooklib` のキャッシュ（`.claude/hooks/__pycache__/_hooklib*`）ができないことを確かめる
  - `docs/vault-spec.md` で「import しない」と書いているのは12節の1か所（承認の裏付けに使う会話記録の段落）だけ。9節の Stop フックの表には、未コミット検査の行がまだ無い
- タスクの分け方
  - T-01 で `_hooklib.py` だけを作る（フックはまだ変えない）
  - T-02〜T-04 で、フックを1本ずつ置き換える。成果物のファイルが互いに違うので、T-01 の後は並行して進めてよい。`.git` 判定の修正は、同じファイル（stop_gate.py）なので T-04 に含める
  - smoke.sh への追加は T-05 にまとめる。docs は T-06 にまとめる。smoke.sh と docs を触るタスクは1つずつにして、編集の競合を避ける
  - T-05・T-06 は、3フックの置き換えが終わってから行う（after に T-02,T-03,T-04）
- import の書き方・失敗時の挙動・エラーメッセージの文言は、T-02〜T-04 の「決定済み」で同じ形に固定する。T-05・T-06 はそれを前提にする
- 確認コマンドで `_hooklib` を import する時は `python3 -B` を使う。`py_compile` は `__pycache__` を作るので、構文の確認は `ast.parse` で行う

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | .claude/hooks/_hooklib.py を新設し3フックに複製されている10関数を置く | |
| T-02 | review | 1 | T-01 | agent_write_guard.py の複製関数を _hooklib の import に置き換える | |
| T-03 | review | 1 | T-01 | plan_guard.py の複製関数を _hooklib の import に置き換える | |
| T-04 | review | 1 | T-01 | stop_gate.py の複製関数を _hooklib に置き換え .git 判定を rev-parse に直す | |
| T-05 | todo | 0 | T-02,T-03,T-04 | smoke.sh に _hooklib の読み込み失敗・worktree の未コミット・__pycache__ のケースを足す | |
| T-06 | todo | 0 | T-02,T-03,T-04 | docs/vault-spec.md と docs/decisions.md を _hooklib の導入に合わせて更新する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 移した10関数が `_hooklib.py` にだけ定義されている：`grep -lE '^def (existing_ancestor|git_toplevel|delegate_to_worktree|plan_id_and_status|approved_plans|raw_rows|plan_raw_rows|frontmatter_status|human_messages|is_approve_command|is_unblock_command)\(' .claude/hooks/agent_write_guard.py .claude/hooks/plan_guard.py .claude/hooks/stop_gate.py .claude/hooks/_hooklib.py` の出力が `.claude/hooks/_hooklib.py` の1行だけ
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わる

## 次フェーズの候補（票は起こさない）
- D-011 フェーズ2（解析規則のずれの統一）
  - `scripts/current_plan.sh` の4行目のコメントに「plan_guard.py の plan_id_and_status と同じ」と書いてある。このコメントは、フェーズ2で awk を直す時に `_hooklib.py` を指すように直す（フェーズ1では触らない）
- D-011 フェーズ3（Bash 判定の一本化）
