---
id: P-20261012-smoke-install-gi-manifest
status: approved
---
# ゴール
GitHub Issue #198「導入先で smoke を実行すると (install-gi) 03 が NG になる（manifest の gitignore キーが一時導入先へ引き継がれる）」を解決する。`scripts/install.sh` の `.claude/` 複製ループが導入元の `.claude/harness-manifest.json` を導入先へ持ち込まないようにし、`scripts/smoke.sh` に回帰テストを足す。

## 分割方針
- 修正は `scripts/install.sh` の find の除外1か所、回帰テストは `scripts/smoke.sh` の「== install.sh の .gitignore ==」節への1ケース追加で、合わせて1コンテキストで終わる。修正とテストを別タスクに分けると、テスト側のタスクが修正前のコードで NG になる（あるいは修正側に回帰の確認手段が無い）ため、1タスクにまとめる。主な成果物は `scripts/install.sh`（修正）で、`scripts/smoke.sh` は付随する回帰テスト。
- `docs/vault-spec.md` には manifest の記述が無く、`docs/install.md` の manifest の説明（「作られる」「照合する」）も今回の修正と矛盾しないため、文書は変えない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | install.sh が導入元の harness-manifest.json を複製しないようにし smoke に回帰テスト (install-gi) 07 を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
