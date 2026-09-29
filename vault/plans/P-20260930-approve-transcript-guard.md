---
id: P-20260930-approve-transcript-guard
status: approved
---
# ゴール
`.claude/settings.json` の `permissions.deny` に `Bash(gh pr merge*)`・`Bash(glab mr merge*)`・`Bash(claude *)` を追加する。計画票の承認（frontmatter の status を approved にすること）は、人が `/plan approve <計画ID>` で指示した時だけ許可する。`.claude/hooks/agent_write_guard.py`（PreToolUse）は、Write/Edit/MultiEdit で `vault/plans/<計画ID>.md` の status を approved 以外（ファイルが無い場合を含む）から approved にする書き込みを検出する。その時、メインセッション（`agent_type` が空）であり、かつフックに渡される会話記録（`transcript_path`）の人の発言に `/plan approve <計画ID>` がある場合だけ許可し、それ以外は拒否する。`.claude/hooks/plan_guard.py`（PostToolUse）は、Bash による書き込みの取りこぼしを補う。作業ツリーの計画票を `git show HEAD:<path>` と比べて同じ判定を行い、裏付けが無ければブロックして元に戻すよう指示する。会話記録が読めない時は、どちらのフックもブロックせず、plan_guard が `additionalContext` で警告を出す。あわせて、会話記録（`~/.claude/projects/` 配下）への書き込みを agent_write_guard で拒否する。`.claude/skills/plan/SKILL.md` の B（承認）を、承認後すぐに log へ根拠を1行追記してコミットする手順に改める。`docs/vault-spec.md` の7・10・12節に追記し、`scripts/smoke.sh` にテストを足す（issue #75 のうち承認とマージ、`vault/designs/D-010.md` フェーズ4）。

PR 本文では `Relates to #75` を使う（`Closes #75` は使わない）。#75 は D-010 の決定事項どおり承認（F4、この計画）と blocked の解除（F5）の2フェーズに分けており、`Closes #75` はF5 の PR で使う。blocked の解除（`/plan unblock`）は今回扱わず、blocked→他 を検査しない。

## 分割方針
- 依存の軸：会話記録の解析（人の発言の判定）は agent_write_guard と plan_guard の2フックが同じ規則で使う。フック間で import しない既存方針のため、解析関数は両方にコピーする。先に agent_write_guard 側で規則とテスト用フィクスチャ（会話記録のサンプルを作る smoke.sh ヘルパー）を確定し、plan_guard 側はそれを流用する
- `scripts/smoke.sh`・`agent_write_guard.py` を複数タスクが触るので、全タスクを `after` で直列にする
- T-01：settings.json の deny 3件（設定ファイルだけで独立し最も小さい）
- T-02：会話記録（`~/.claude/projects/`）への書き込み拒否（agent_write_guard。承認判定の前提となる「会話記録を偽造できない」ことを先に固める）
- T-03：agent_write_guard の承認判定（会話記録の読み取り・コマンド一致・書き込み後の内容の組み立て。本計画で最も重い。smoke.sh の会話記録ヘルパーもここで作る）
- T-04：plan_guard の承認判定（Bash 取りこぼしの補完・HEAD 比較・警告）
- T-05：`/plan` スキル B（承認）の手順を、根拠 log 追記とコミットを含む形に改める
- T-06：`docs/vault-spec.md` 7・10・12節への追記（T-02〜T-05 の挙動を正確に書くため最後）
- 6タスクで7以内。次フェーズ（blocked の解除 `/plan unblock`）は D-010 フェーズ5 で扱い、今回は票を起こさない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | settings.json の deny に gh pr merge・glab mr merge・claude を追加し smoke.sh に確認を足す | |
| T-02 | todo | 0 | T-01 | agent_write_guard.py で会話記録（~/.claude/projects/ 配下）への書き込みを拒否し smoke.sh にテストを足す | |
| T-03 | todo | 0 | T-02 | agent_write_guard.py で計画票の draft→approved を会話記録の人の発言で裏付け、無ければ拒否する（smoke.sh にテストを足す） | |
| T-04 | todo | 0 | T-03 | plan_guard.py で作業ツリーの計画票を HEAD と比べて承認の裏付けを検査し smoke.sh にテストを足す | |
| T-05 | todo | 0 | T-04 | /plan スキルの B（承認）を、人のコマンド確認・log への根拠追記・コミットの手順に改める | |
| T-06 | todo | 0 | T-05 | vault-spec.md の7・10・12節に承認の裏付けと会話記録の保護を追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- D-010 フェーズ5：blocked の解除を `/plan unblock <計画ID> <id>` に一本化し、人の指示（会話記録）で裏付ける（#75 その2、`Closes #75`）。F4 で作る会話記録の解析を再利用する
