---
id: P-20261007-stop-gate-scope
status: approved
---
# ゴール
Stop フックの適用範囲と無人実行での厳格化（D-013 フェーズ1）

`.claude/hooks/stop_gate.py` の判定順を変える。
- 承認済みの計画票が0件なら、未コミットの検査も含めて何もせずに許可する
- 2件以上なら、今どおりブロックする
- 1件の時だけ、未コミットの検査と既存の判定を行う

あわせて、`scripts/run_unattended.py` が子プロセスを起動する時、環境変数 `HARNESS_STRICT_STOP` が設定されていなければ `1` を入れて渡すようにする。`docs/vault-spec.md` 9節の判定表と、`docs/runbook.md` の無人実行の説明を合わせて更新する。

正本は `vault/designs/D-013.md` の「フェーズ1 Stop フックの適用範囲と無人実行での厳格化」（ゴール文・受け入れ基準の候補・決定済み）。

## 分割方針
- コードの変更2つ（stop_gate.py・run_unattended.py）と文書の変更2つ（vault-spec.md・runbook.md）に分け、1タスク1ファイル（smoke のケース追加は付随ファイル）にする
  - T-01：`stop_gate.py` の判定順の変更と smoke のケース（追加・既存の (f)・(g)・worktree のケースの前提の直し）
  - T-02：`run_unattended.py` の `HARNESS_STRICT_STOP` の既定と smoke のケース
  - T-03：`docs/vault-spec.md` 9節の判定表と本文（T-01 の実装に合わせる）
  - T-04：`docs/runbook.md` 3節の無人実行の説明（T-02 の実装に合わせる）
- T-01 と T-02 はどちらも `scripts/smoke.sh` を変えるので、衝突を避けて T-02 を T-01 の後にする（直列）
- T-03 は T-01 の後、T-04 は T-02 の後。T-03 と T-04 は別ファイルなので並行してよい
- smoke の件数は計画作成時点で `smoke: pass=654 fail=0`。T-01 で2件、T-02 で2件増える前提（決定済みに書いたケース数）。受け入れ基準は件数ではなく `fail=0` とケース名で見る
- `.claude/hooks/_hooklib.py` は変えない（`approved_plans`・`parse_tasks`・`done_rows_without_pass` をそのまま使う）。`vault/rules/` は触らない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | stop_gate.py の判定順を変え、承認済みの計画票が0件なら未コミットの検査もせずに許可する | |
| T-02 | done | 1 | T-01 | run_unattended.py で HARNESS_STRICT_STOP が未設定なら子プロセスに 1 を渡す | |
| T-03 | done | 1 | T-01 | docs/vault-spec.md 9節の判定表を新しい判定の順序に直す | |
| T-04 | doing | 1 | T-02 | docs/runbook.md の無人実行の説明に HARNESS_STRICT_STOP の既定を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む
- `vault/rules/` と `.claude/hooks/_hooklib.py` は変わっていない（`git status --porcelain -- vault/rules .claude/hooks/_hooklib.py` が空）

## 次フェーズの候補
- D-013 フェーズ2（verifier の指摘を見えるようにする）。フェーズ1の後に始める

## 人への質問
計画は次の前提で書いた。違う場合は承認前に指示してほしい。
1. `run_unattended.py` の「設定されていなければ」は、環境変数が存在しない時だけ `1` を入れる意味にした。空文字列で設定されている時はその値（空）のまま渡す（stop_gate.py では `1` でないので従来の動き）。空文字列も未設定とみなしたい場合は指示してほしい
2. 既存の smoke のケース名（(f)・(g)・`(stop_gate worktree) ...`）は変えず、フィクスチャに承認済みの計画票を置いてコミットする前提に直すだけにした。PR 本文への列挙は、PR を作る時（`vcs_finish.sh`）にオーケストレーターが T-01 の「進捗」から写す前提にした（creator は PR を作らないため）
