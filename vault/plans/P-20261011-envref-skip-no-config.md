---
id: P-20261011-envref-skip-no-config
status: done
---
# ゴール
GitHub Issue #176 に対応する。導入先（`docs/configuration.md` が配布されないルート）で `bash scripts/smoke.sh` を走らせると `(envref-1)` が全 HARNESS_* を「表に無い」として NG にし `fail=1` になる問題を、対応案 A（`docs/configuration.md` が無い時は `scripts/smoke.sh` の `envcheck` が何も出さずに終わり、`(envref-1)` が実質スキップされる）で直す。対応案 B（install.sh で `docs/configuration.md` を配る）は採らない。

## 分割方針
- 変更は `scripts/smoke.sh` の `envcheck()` への早期終了の追加と、導入先相当の状態を再現する smoke 検査 `(envref-3)` の追加だけで、1コンテキストで終わるため T-01 の1件にする。
- `scripts/install.sh`・`docs/install.md`・`docs/configuration.md` は変えない（対応案 A のため）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | smoke.sh の envcheck を docs/configuration.md が無い時にスキップし (envref-3) を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
