---
id: P-20261007-done-verdict-check
status: approved
---
# ゴール
done の行の verdict をフックで検査する（D-012 フェーズ1）

`.claude/hooks/plan_guard.py`（PostToolUse）と `.claude/hooks/stop_gate.py`（Stop）に検査を1つ足す。自分のブランチの承認済み計画票のタスク表で status が `done` の行それぞれについて、`vault/verdicts/<計画ID>/<id>.json` が次の条件をすべて満たすかを確かめる。
- ファイルがある
- `task` が `<計画ID>/<id>`
- `attempt` がタスク表の値と一致する
- `result` が `PASS`
- 形式が正しい（`stop_gate.py` の既存の形式検査と同じ）

満たさない done の行があればブロックし、その行を review に戻して verifier を実行するよう指示する。`stop_gate.py` の `validate_verdict` は `.claude/hooks/_hooklib.py` に移して両方のフックで使う。`stop_gate.py` の到達しない done の分岐は消す。`docs/vault-spec.md` の9節・10節をこの検査に合わせて更新する。正本は `vault/designs/D-012.md` の「フェーズ1 done の行の verdict をフックで検査する」。

## 分割方針
- 各タスクを単体でマージしても `bash scripts/smoke.sh` が `fail=0` で通る順にする。フックが done の行を検査し始めると、PASS の verdict を置かずに done の行を使っている既存の smoke ケースが落ちるため、先に T-02 でそれらのケースに PASS の verdict を置き（今のフックでも結果は変わらない）、その後で T-03・T-04 がフックを変える。新しいケースは、フックが変わった後の T-05 で足す
- T-01 は共通部品（`_hooklib.py` に `validate_verdict` の複製と `done_rows_without_pass` を足す）。`stop_gate.py` の `validate_verdict` は T-01 では残し、T-03 で消して `_hooklib.py` のものに切り替える（1タスク1ファイルにするため、T-01 と T-03 の間だけ定義が2つある）
- T-03（`stop_gate.py`）と T-04（`plan_guard.py`）は別ファイルなので、T-01・T-02 の後に並行で進められる。T-05（smoke の新ケース）と T-06（`docs/vault-spec.md`）も、T-03・T-04 の後に並行で進められる
- フックの動作確認は、planner が置いたフィクスチャ `vault/tasks/P-20261007-done-verdict-check/fixtures/{mixed,ok}/` を `CLAUDE_PROJECT_DIR` に渡して行う。`stop_gate.py` の未コミット変更の検査に当たらないよう、確認コマンドは `env GIT_DIR=/nonexistent` を付けて git を使えなくする（`has_uncommitted_changes` は git が使えない時 False を返す）
  - `mixed`：計画 `P-FIX`（approved）。T-01 done・正しい PASS／T-02 done・verdict 無し／T-03 done attempt=2・verdict は attempt=1／T-04 done・FAIL／T-05 done・criteria 2件 vs 受け入れ基準3行／T-06 done・task が `P-FIX/T-01`／T-07 review・verdict 無し
  - `ok`：計画 `P-FIX`（approved）。T-01 done・正しい PASS／T-02 todo
  - フィクスチャは計画作成時点の今のフックで、`mixed` は stop_gate が T-07（review・verdict 無し）でブロック、plan_guard は許可、`ok` は両フックとも許可になることを確かめてある
- T-02 で PASS の verdict を置く既存ケース（D-012 の決定済みにある「直したケースを PR 本文に列挙する」の対象。この計画票が PR 本文から辿れる）
  - `plan_guard.py` の「(a-5) doing の after が done なタスクを指す → 許可」
  - `plan_guard.py` の「正常な計画票（doing 1件・blocked に question あり）→ 許可」
  - `stop_gate.py` の「(delegate stop_gate) 呼び出し前に _HOOK_DELEGATED が既にセット済み → …（正常な計画票は許可）」
  - `plan_guard.py` の「(delegate plan_guard) 呼び出し前に _HOOK_DELEGATED が既にセット済み → …（正常な計画票は許可）」
- 次の既存ケースは done の行に verdict が無いまま残す。既存の検査（id の重複）が done の行の検査より先にブロックすることの確認になるため：plan_guard の「(d) id が重複」、「(ms-4) 補足付き log・plan_guard: id 重複」
- smoke の pass は計画作成時点で 519。T-01〜T-04 はケースを増やさない（519 のまま）、T-05 で10件足して 529 にする

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | _hooklib.py に validate_verdict と done_rows_without_pass を足す | |
| T-02 | todo | 0 | - | smoke.sh の done の行を含む既存ケースに PASS の verdict を置く | |
| T-03 | todo | 0 | T-01,T-02 | stop_gate.py で done の行の verdict を検査し validate_verdict を _hooklib.py に切り替える | |
| T-04 | todo | 0 | T-01,T-02 | plan_guard.py で done の行の verdict を検査する | |
| T-05 | todo | 0 | T-03,T-04 | smoke.sh に done の行の verdict 検査のケースを両フック5件ずつ足す | |
| T-06 | todo | 0 | T-03,T-04 | docs/vault-spec.md の9節・10節に done の行の verdict の検査を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わり、pass が 519 より多い
- `grep -l "^def validate_verdict(" .claude/hooks/*.py` の出力が `.claude/hooks/_hooklib.py` だけ

## 人への質問
1. D-012 の決定済みの「直したケースは PR 本文に列挙する」は、この計画票の「分割方針」に列挙したもの（PR 本文のタスク履歴から計画票を辿れる）で足りるとしてよいか。足りなければ、PR 作成時にオーケストレーターが本文へ追記する（どのタスクの成果物にもしない）。planner の前提は「足りる」
2. `docs/vault-spec.md` 9節の判定表の「PASS かつ done → 許可」の行は、stop_gate.py の到達しない done の分岐を消すのに合わせて消し、代わりに done の行の検査の行を足す前提にした（T-06 の決定済み）。残したい場合は指示してほしい
