---
id: P-20261011-task-headings
status: approved
---
# ゴール
planner が作るタスク票に「## 進捗」の見出しが無いと、creator が見出し無しで末尾に足した追記が「決定済み」節の変更と判定され、差分ゲートで差し戻される（GitHub Issue #166）。これを直す。
- (1) `.claude/hooks/plan_guard.py` で、draft の計画のタスク票に `vault/templates/task.md` の6見出し（目的・入力・成果物・受け入れ基準・決定済み・進捗）がそろっていることを確かめ、欠けていれば止める
- (2) `.claude/agents/planner.md` の「『進捗』は空のまま」を、「『## 進捗』の見出しだけを書き、本文は空にする」の意味が明確な文に直す
- (3) `.claude/agents/creator.md` に「タスク票に『## 進捗』見出しが無ければ見出しごと末尾に足してから追記する」を書く
- `docs/vault-spec.md` の該当説明と `scripts/smoke.sh` のケース（見出しの欠落を検出する・6見出しがそろえば通す）もそろえる

## 分割方針
- 機械的な確認は `.claude/skills/plan/SKILL.md` の手順5ではなく `plan_guard.py`（フック）に置く。planner がタスク票を Write/Edit した時点で止まり、プロンプトに頼らず仕組みで強制できるため（vision の原則2）。既存の粒度検査（受け入れ基準の行数）と同じ契機・同じ fail-open の扱いにそろえる
- T-01 はフックの実装と smoke のケースを1つにまとめる。smoke の `make_task` は今は2見出ししか書かないので、見出し検査を入れると既存の粒度ケースが同時に壊れる。同じタスクで直さないと計画ブランチの smoke が途中で落ちる。creator が見出しを足す手順で差分ゲートを通ることも、同じ smoke（diff_gate のケース）で確かめる
- T-02 は仕様書（正本）を、T-01 で実装した判定（契機・理由の文言）に合わせて書くので T-01 の後にする
- T-03（planner.md）と T-04（creator.md）は文言の修正だけで、互いにも T-01 にも依存しない。別ファイルなので並行に進められる
- `.claude/skills/plan/SKILL.md` と `vault/templates/task.md` は変えない（理由は各タスク票の「決定済み」）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | plan_guard.py にタスク票の6見出しの検査を足し、smoke にケースを足す | |
| T-02 | review | 1 | T-01 | docs/vault-spec.md の5節・10節に6見出しの検査と「## 進捗」の扱いを書く | |
| T-03 | done | 1 | - | planner.md の「『進捗』は空のまま」を見出しだけ書く意味の文に直す | |
| T-04 | done | 1 | - | creator.md に「## 進捗」見出しが無い時の追記の手順を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
