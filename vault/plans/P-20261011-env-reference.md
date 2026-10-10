---
id: P-20261011-env-reference
status: approved
---
# ゴール
D-20261011-user-guide フェーズ1：利用者が指定できる環境変数（`HARNESS_*`）を `docs/configuration.md` に1つの表で一覧化する。各変数について、意味・既定値（未設定の時に実際に使われる値。経路で違う時はその旨）・読むもの（スクリプト・フック・スキル）・使う場面・詳しい説明へのリンクを書く。run が内部で渡すだけの変数（`HARNESS_PR_BODY_FILE`・`HARNESS_PR_TITLE`）は利用者が設定するものと分けて載せる。`README.md` からリンクし、`scripts/smoke.sh` に表とコードの変数の一致を確かめるケースを足す。

設計文書：`vault/designs/D-20261011-user-guide.md`（フェーズ1。最終フェーズではないので、設計文書の削除と `docs/decisions.md` への追記はこの計画に含めない）

## 分割方針
- T-01 で `docs/configuration.md` 本体を書く。既定値・読むものは設計文書の「決定済み」とコードの照合結果をタスク票の「決定済み」にそのまま書き、creator はコードで再確認する
- T-02 で `scripts/smoke.sh` に、表とコードの `HARNESS_*` の一致を見るケース（実リポジトリ・フィクスチャの2件）と、`docs/configuration.md` を `(ref-1)` の対象に加える変更を入れる。対象の一覧を本文に持つ `.claude/agents/planner.md` の記述も同時に直す。表が先に無いと一致ケースが落ちるので T-01 の後
- T-03 で `README.md` からリンクする。T-01 の後（T-02 とは独立）
- 「1つの表」と「内部用は分けて載せる」の両立は、同じ6列の表を見出し2つ（利用者が設定する変数／run が内部で渡す変数）に分けて置く形にした（T-01 の決定済み）
- 既存文書（`docs/runbook.md`・`docs/vault-spec.md`・`docs/install.md`）と `scripts/install.sh` はどのタスクの成果物にもしない（説明を消さない・配布対象を変えない。差分ゲートが変更を止める）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | 環境変数リファレンス docs/configuration.md を書く | |
| T-02 | todo | 0 | T-01 | smoke に表とコードの HARNESS_* の一致検査を足し、configuration.md を ref-1 の対象にする | |
| T-03 | todo | 0 | T-01 | README.md から docs/configuration.md へリンクする | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- D-20261011-user-guide フェーズ2（`docs/guide.md`）・フェーズ3（runbook 整理）は別計画で起こす
