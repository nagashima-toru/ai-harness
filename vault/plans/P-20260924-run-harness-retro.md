---
id: P-20260924-run-harness-retro
status: approved
---
# ゴール
`vault/designs/D-004.md`（単一フェーズ）の内容を実装する。`run` スキルが計画のタスクを全部 `done` にして PR を作った後、その計画実行を通して気づいたハーネス自体（`.claude/` のスキル・エージェント定義・フック、`vault/rules/`）への構造的な改善点があれば、オーケストレーターが1回だけ振り返り、`gh issue create` で起票する仕組みを `.claude/skills/run/SKILL.md` に追加する（issue #16）。

## 分割方針
D-004 は単一フェーズかつ `.claude/skills/run/SKILL.md` への手順追記1本に閉じる変更のため、成果物1つ（`.claude/skills/run/SKILL.md`）のタスク T-01 のみで完結させる。実装対象ファイルが1つで、依存させる別タスク（契約タスク等）を切る必要が無いため2タスク目は作らない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | run スキルにハーネス振り返り手順を追加する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
