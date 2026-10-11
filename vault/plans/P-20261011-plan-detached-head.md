---
id: P-20261011-plan-detached-head
status: approved
---
# ゴール
GitHub Issue #178（/plan・/design: detached HEAD で開始すると開始条件で止まる）に対応する。`.claude/skills/plan/SKILL.md` の手順A-2 と `.claude/skills/design/SKILL.md` の手順1 に、detached HEAD（`git branch --show-current` の出力が空）で `git rev-parse HEAD` がローカルのベースブランチの ref と一致する時は `git checkout <ベースブランチ>` してからベース上とみなす手順を加える。

## 分割方針
- T-01：手順そのもの（2つの SKILL.md）。2ファイルとも同じ文言を、既存の1行の段落の同じ位置に挿入する。文言は T-01 の「決定済み」で一字一句固定する
- T-02：開始条件を説明する docs（`docs/vault-spec.md` の `HARNESS_PUSH_BRANCH` 段落）への同趣旨の追記と、`docs/decisions.md` への1行追記。T-01 とファイルが重ならないので依存させない
- 既存の smoke・hooks・tests は開始条件の文言を検査していない（`scripts/smoke.sh` が `plan`・`design` の SKILL.md を見るのは `(ref-1)` の参照切れ検査だけ）ので、検査の変更は不要
- `docs/runbook.md`・`docs/guide.md`・`docs/install.md` は開始条件の詳細を持たず SKILL.md へリンクする（または `HARNESS_PUSH_BRANCH` の運用だけを書く）ので変えない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | /plan 手順A-2・/design 手順1 に detached HEAD でベースと一致する時の checkout を加える | |
| T-02 | review | 1 | - | vault-spec の開始条件の記述に detached HEAD の扱いを足し、decisions に記録する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
