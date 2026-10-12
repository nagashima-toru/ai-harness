---
id: P-20261012-verifier-wait-stop-gate
status: done
---
# ゴール
GitHub Issue #193「verifier の完了待ち（review・verdict なし）でも stop_gate が「verifier を実行せよ」で止める」を解決する。
review で verdict が無い（または古い）時の stop_gate の理由文にも、creator 待ちと同じく「待機中なら問題ありません」と完了通知を待つ案内を入れ（判定は変えず文言だけ。D-20261010-async-agent-wait・2026-10-12 の人の選択と同じ方針）、run の手順5の verifier の起動通知の扱いを、手順3の creator と同じく「起動通知で返るのが普通」を主にした書き方にそろえる。

## 分割方針
- T-01：コード（`.claude/hooks/stop_gate.py` の review の理由文）と、その振る舞いを確かめる smoke の async-wait 系テストを1タスクにまとめる（テストとコードを分けると、片方だけでは smoke が通らないため）
- T-02：文書（`.claude/skills/run/SKILL.md` 手順5、`docs/vault-spec.md` 9節の stop_gate の表、`docs/decisions.md`）。T-01 の実際の文言を見て書けるよう `after` を T-01 にする
- 小さな変更なので2タスクに留める

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | stop_gate の review・verdict なしの理由文に verifier の完了通知を待つ案内を入れる | |
| T-02 | done | 1 | T-01 | run 手順5の verifier の起動通知の扱いと vault-spec 9節・decisions を新しい文言にそろえる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
