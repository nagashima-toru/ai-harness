---
id: P-20261017-second-plan-start
status: approved
---
# ゴール
GitHub Issue #205 と #206 を解決し、同じセッションで2つ目の /plan を始められるようにする。

- #205：`scripts/purge_plan.sh` が最後の `vault/log/<計画ID>.md` を `git rm` すると `vault/log/` ごと消え、次の `/plan` の A 手順9（承認ログの追記）が No such file or directory で失敗する。原因は `scripts/install.sh` の複製リストに `log/.gitkeep` が無く、導入先に `vault/log/.gitkeep` が配られないこと
- #206：クラウドセッション（push 先ブランチが1本に決められている）で、1つ目の計画の PR がマージされた後、現在のブランチは `work/<計画ID>` のまま、push 先ブランチはマージ前の履歴を指したままで、2つ目の `/plan` が A 手順2の開始条件を満たさず止まる

## 分割方針
- T-01（#205 の本修正）：`scripts/install.sh` の vault の複製リストに `log/.gitkeep` を足し、smoke に新規導入・再導入・`--update`・マニフェストの4点の検査を足す。既存の `.gitkeep` と同じく `copy_if_absent` で配り、マニフェストには載せない
- T-02（#205 の保険）：`.claude/skills/plan/SKILL.md` の A 手順9・B 手順8 に「`vault/log/` が無ければ `mkdir -p vault/log` で作る」を足す
- T-03（#206）：同じ SKILL.md の A 手順2に、push 先ブランチをベースブランチから切り直す分岐を足す。T-02 と同じファイルなので、マージの衝突を避けるため T-02 の後にする
- T-04（#206 の文書）：仕様の正本 `docs/vault-spec.md` 1節と、運用手順 `docs/runbook.md` 10節に、切り直しの条件とスカッシュマージ時の人の作業（リモートの push 先ブランチの削除）を書く。SKILL.md の書きぶりに合わせるため T-03 の後にする

スカッシュマージの扱い（T-03 の決定済みに詳細）：このリポジトリの PR はスカッシュマージされる（runbook 3節も推奨）。スカッシュ後は push 先のコミットがベースの祖先にならないので、`git merge-base --is-ancestor` だけで判定すると切り直しが一度も起きない。そこで「内容が取り込み済みか」は `git merge-tree --write-tree <ベース> <対象>` の結果のツリーがベースのツリーと同じかで判定する（git 2.38 以降。手元の git 2.43 で、スカッシュ済みなら一致し、未マージのコミットがあれば一致しないことを planner が一時リポジトリで確かめた）。ただし、リモートの push 先ブランチがスカッシュ前の履歴のまま残っていると、切り直した後の push が non-fast-forward で必ず失敗する（force はしない）。このため、リモートの push 先ブランチが残っていてベースの祖先でない時は、切り直さずに止まり、リモートの push 先ブランチを削除するよう人に案内する（安全側）。

対象外：`/design` 手順1の同じ開始条件（ゴールが `/plan` のため。T-03・T-04 の決定済み）、`HARNESS_PUSH_BRANCH` が設定されていない時の `work/…` からの開始（ベースブランチに checkout し直せば従来どおり始められるため）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | install.sh で vault/log/.gitkeep を配り smoke で検査する | |
| T-02 | done | 1 | - | plan SKILL の承認・解除のログ追記で vault/log/ を作る | |
| T-03 | done | 1 | T-02 | plan SKILL A 手順2に push 先ブランチの切り直しを足す | |
| T-04 | review | 1 | T-03 | vault-spec と runbook に push 先ブランチの切り直しを書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
