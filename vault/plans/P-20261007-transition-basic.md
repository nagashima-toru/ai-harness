---
id: P-20261007-transition-basic
status: approved
---
# ゴール
状態遷移スクリプト transition.py の基本（D-012 フェーズ2）

計画票のタスク表の状態遷移を1コマンドで行う `scripts/transition.py` を新設する。呼び出しの形は `python3 scripts/transition.py <計画ID> <id>[,<id>...] <遷移先> [--question <文> | --question-file <パス>] [--note <補足>] [--no-model]`。

- 許す遷移は todo→doing、doing→doing、doing→review、doing→blocked、review→done、review→doing、review→blocked だけ
- タスク表の status・attempt・question を書き換え、`vault/log/<計画ID>.md` に実際の JST の時刻で遷移行を追記する
- 計画票と log（done の時は verdict も）だけを `git commit -m "<計画ID>/<id,...>: <旧>→<新>" -- <パス...>` でコミットする
- review→done は、`.claude/hooks/_hooklib.py` の `done_rows_without_pass` と同じ条件の PASS の verdict が無ければ拒否する
- 遷移行のモデルの記録（`creator=`・`verifier=`）は `.claude/agents/<name>.md` の frontmatter から自動で付ける

このフェーズでは run の手順（`.claude/skills/run/SKILL.md`）は変えない。承認（draft→approved）と blocked の解除は扱わない。正本は `vault/designs/D-012.md` の「フェーズ2 状態遷移スクリプト transition.py の基本」。

## 分割方針
- T-01 で本体（引数・遷移表・attempt・拒否条件・表と log の書き換え・コミット・all-or-nothing・終了コード）を作り、T-02 で review→done の verdict 検査と `creator=`・`verifier=` の自動付与を足す。T-01 の時点では review→done を終了コード1で拒否しておき、T-02 でその拒否を verdict 検査に置き換える（PASS の確認無しに done にできる版を一度も作らない）
- T-03（`scripts/smoke.sh` のケース）と T-04（`docs/vault-spec.md`）は別ファイルなので、T-02 の後に並行で進められる
- どのタスクも単体でマージして `bash scripts/smoke.sh` が `fail=0` で通る。T-01・T-02 は smoke.sh を変えない（pass は計画作成時点の 529 のまま）。T-03 で22件以上足す。T-04 は `docs/vault-spec.md` に `scripts/transition.py` を書くので、smoke の「参照される scripts の存在チェック」のために T-01 より後にする（T-02 の後）
- T-01・T-02 の動作確認には、planner が置いたフィクスチャ `vault/tasks/P-20261007-transition-basic/fixtures/try.sh` を使う。一時 git リポジトリ（ブランチ `work/p-test`、承認済み計画票 `P-TEST`、11行のタスク表、未追跡の verdict、モデル `fx-creator-model`・`fx-verifier-model` の agents）を作って `scripts/transition.py` を1回実行し、終了コード・増えたコミット・コミットのファイル・計画票と log の変化・表・log・plan_guard の判定を出す（使い方とタスク表の初期状態はファイル先頭のコメント）。`transition.py` が無い今の状態で、セットアップと出力が動くことは確かめてある（`exit=2`、`plan_guard=allow`）
- smoke（T-03）はこのフィクスチャを使わない。install 先には `vault/tasks/` の計画のファイルが無いため、smoke.sh の中で同じ形の一時リポジトリを作る

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | scripts/transition.py を新設し遷移・attempt・拒否条件・表と log の書き換え・コミットを実装する | |
| T-02 | review | 1 | T-01 | transition.py に review→done の verdict 検査と creator=/verifier= の自動付与を足す | |
| T-03 | todo | 0 | T-02 | smoke.sh に transition.py のケースを22件以上足す | |
| T-04 | todo | 0 | T-02 | docs/vault-spec.md の2節・7節に transition.py の使い方と推奨の経路であることを書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` を含み、pass が 551 以上
- `.claude/skills/run/SKILL.md` は変わっていない（このフェーズでは run の手順を変えない）

## 次フェーズの候補
- D-012 フェーズ3（`scripts/diff_gate.py` と「成果物」の記法）。フェーズ4（worktree の運用）・フェーズ5（run の手順の置き換え）はその後

## 人への質問
1. 遷移先が blocked でないのに `--question`／`--question-file` を渡した時は「引数の誤り」（終了コード2）とし、blocked 以外への遷移では question 列を空にする前提にした（`/plan unblock` が question を空にするのと揃える。T-01 の決定済み）。question 列を変えずに残したい場合は指示してほしい
2. 複数の id を渡した時、現在の status がそろっていなければ終了コード1で拒否する前提にした（コミットのメッセージが `<旧>→<新>` の1組だけのため）。D-012 には明記が無いので確認したい
3. `_hooklib.py` を import できない時の終了コードは、hooks の2ではなく1（前提を満たさず何も変えていない）にした。2は引数の誤りに限る。違う扱いがよければ指示してほしい
4. 遷移先の値が遷移表に無い時（`todo`・`approved` のほか、`foo` のような未知の語も）は、D-012 の拒否条件に合わせてすべて終了コード1にした（argparse の choices で2にはしない）
