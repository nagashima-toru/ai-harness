---
id: P-20260920-git-workflow
status: approved
---
# ゴール
`vault/rules/common/git.md` と `vault/rules/creator/git-workflow.md` を新設し、1セッション1計画1ブランチの前提で git 運用ルールを定める。作業ステップごとのコミット、`main` への直接コミットの拒否、未コミット差分の Stop 検査、`--force-with-lease` の deny、破棄手段を `git restore` に限ること、コンフリクト時は自己判断せず止まることを、ルール文書とフックの両方で強制する（`vault/designs/D-001.md` フェーズ5）。

## 分割方針
`vault/designs/D-001.md` の「## フェーズ5」の受け入れ基準の候補7行を、成果物ごとに7タスクへ1対1で割った。
- T-01・T-02：新設するルール文書2本（`vault/rules/` 配下、`doing`/`review` 中は書けないため `HARNESS_ALLOW_RULES_WRITE` か「todo のうちに編集」の回避策が要る）
- T-03・T-04：フック2本（`agent_write_guard.py`・`stop_gate.py`）への git 判定追加。それぞれ独立したロジックなので分けた
- T-05：`.claude/settings.json` への1行追加（`--force-with-lease` の deny）。他タスクと独立した小さな変更のため単独タスクにした
- T-06：`scripts/install.sh` の複製対象・マニフェストへ T-01・T-02 の成果物を追加する。ファイルが存在しないと編集内容を確認できないため `after: T-01,T-02`
- T-07：`README.md`・`docs/runbook.md` の「PR 後は人がマージする」手順の追記。ドキュメントのみで他タスクと独立
7タスクは計画の上限（5〜7）に収まっており、フェーズ5がこの計画の全範囲。次フェーズの候補は無い（`D-001.md` のフェーズはこれで最後）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | vault/rules/common/git.md を新設する | |
| T-02 | todo | 0 | - | vault/rules/creator/git-workflow.md を新設する | |
| T-03 | todo | 0 | - | agent_write_guard.py に main 直接コミット拒否を追加する | |
| T-04 | todo | 0 | - | stop_gate.py に未コミット差分の Stop 検査を追加する | |
| T-05 | todo | 0 | - | settings.json に --force-with-lease の deny を追加する | |
| T-06 | todo | 0 | T-01,T-02 | install.sh の複製対象とマニフェストに新規ルール2本を追加する | |
| T-07 | todo | 0 | - | README/runbook に PR 後の人によるマージ手順を追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
