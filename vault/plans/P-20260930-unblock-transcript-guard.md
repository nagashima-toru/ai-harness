---
id: P-20260930-unblock-transcript-guard
status: approved
---
# ゴール
`.claude/skills/plan/SKILL.md` に C（解除）として `/plan unblock <計画ID> <id> [回答]` を追加する。対象行が blocked であることを確かめ、回答があればタスク票の「決定済み」に追記し、行の status を `todo`、attempt を `0`、question を空にする。log に `- <日時> <id> blocked→todo 人の指示: /plan unblock <計画ID> <id>` を追記し、すぐにコミットする。F4 で入れた agent_write_guard・plan_guard の判定を拡張する。計画票のタスク表で blocked の行を blocked 以外にする書き込みは、メインセッションであり、かつ会話記録の人の発言に `/plan unblock <計画ID> <id>` がある時だけ許可する（会話記録が読めない時は F4 と同じく警告）。`docs/runbook.md` 4節の解除手順を `/plan unblock` を使う形に書き換え、`.claude/ai-harness.md` と `docs/vault-spec.md` 2節の「`blocked→todo` は人のみ」に「`/plan unblock` で人が指示する」旨を追記する。`scripts/smoke.sh` にテストを足す（issue #75 のうち blocked の解除、`vault/designs/D-010.md` フェーズ5）。

PR 本文では `Closes #75` を使う。#75 は D-010 の決定事項どおり承認（F4、`Relates to #75` でマージ済み）と blocked の解除（F5、この計画）の2フェーズに分けており、この計画の PR で #75 を閉じる。

## 分割方針
- 依存の軸：会話記録の解析（`human_messages`）は F4 で agent_write_guard・plan_guard の両方に入っている。今回は「一致判定」（`unblock` コマンド）と「blocked の行が blocked 以外になったか」の判定を足す。フック間で import しない既存方針のため、新しい判定関数も両フックにコピーする。先に agent_write_guard 側で規則とテストを確定し、plan_guard 側はそれを流用する
- `scripts/smoke.sh`・`agent_write_guard.py`・`plan_guard.py` を複数タスクが触るので、全タスクを `after` で直列にする
- T-01：agent_write_guard の解除判定（PreToolUse。書き込み後のタスク表を組み立て、blocked の行が blocked 以外になるかを検出し、会話記録で裏付ける。本計画で最も重い）
- T-02：plan_guard の解除判定（PostToolUse。Bash による取りこぼしを、作業ツリーと HEAD のタスク表の比較で補う）
- T-03：`/plan` スキルに C（解除）を追加する（description・argument-hint も更新）
- T-04：`docs/runbook.md` 4節を `/plan unblock` を使う手順に書き換える
- T-05：`.claude/ai-harness.md` の「`blocked → todo` は人だけ」に `/plan unblock` を追記する
- T-06：`docs/vault-spec.md` の2・7・10・12節への追記（T-01〜T-03 の挙動を正確に書くため最後）
- 6タスクで7以内。次フェーズ候補は無い（D-010 の残りフェーズ6以降は別の計画）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | agent_write_guard.py で計画票の blocked→他 の書き込みを会話記録の /plan unblock で裏付け、無ければ拒否する（smoke.sh にテストを足す） | |
| T-02 | todo | 0 | T-01 | plan_guard.py で作業ツリーの計画票を HEAD と比べて blocked の解除の裏付けを検査し smoke.sh にテストを足す | |
| T-03 | todo | 0 | T-02 | /plan スキルに C（/plan unblock による解除）の手順を追加する | |
| T-04 | todo | 0 | T-03 | docs/runbook.md 4節の blocked 解除手順を /plan unblock を使う形に書き換える | |
| T-05 | todo | 0 | T-04 | .claude/ai-harness.md の「blocked → todo は人だけ」に /plan unblock の旨を追記する | |
| T-06 | todo | 0 | T-05 | vault-spec.md の2・7・10・12節に blocked の解除の裏付けを追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
