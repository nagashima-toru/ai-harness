---
id: P-20261011-user-guide-entry
status: approved
---
# ゴール
D-20261011-user-guide フェーズ2：利用者がやりたいことから必要な手順・設定に辿り着ける入口を `docs/guide.md` に作る。各項目は「やりたいこと」「すること（コマンドや設定の最小例）」「詳しく（`docs/install.md`・`docs/runbook.md`・`docs/configuration.md` の節へのリンク）」の形にする。`README.md` からリンクする。

設計文書：`vault/designs/D-20261011-user-guide.md`（フェーズ2。最終フェーズではないので、設計文書の削除と `docs/decisions.md` への追記はこの計画に含めない）

## 分割方針
- T-01 で先に `scripts/smoke.sh` の検査を用意する。`docs/guide.md` を `(ref-1)` の対象に足し、guide の各項目の形（「すること：」「詳しく：」）と、「詳しく」で挙げた節名がリンク先の文書の見出しに実在することを確かめるケース（`guide-1`・`guide-2`）を足す。フェーズ3で runbook の節を変えた時に、guide のリンク切れを機械で止めるため（原則2）。guide.md がまだ無い時は検査は何も出さないので、T-01 を先に入れても smoke は通る
- T-02 で `docs/guide.md` 本体を書く。T-01 の検査で項目の形と節の実在を確かめる。載せる11項目・見出しの文言・各項目の最小例とリンク先の節は決定済みで固定する
- T-03 で `README.md` から `docs/guide.md` へリンクする。README のバッククォート内の `docs/guide.md` は `(ref-1)` が実在を確かめるので、guide.md ができた後（T-02 の後）に置く
- `scripts/install.sh` の配布対象は変えない（設計文書の決定事項）。runbook・install.md の本文は変えない（runbook の整理はフェーズ3）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | smoke に docs/guide.md の参照切れ・項目の形・節の実在の検査を足す | |
| T-02 | todo | 0 | T-01 | やりたいこと別の入口 docs/guide.md を書く | |
| T-03 | todo | 0 | T-02 | README.md から docs/guide.md へリンクする | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
