---
id: P-20260924-creator-subagent
status: approved
---
# ゴール
D-003（`vault/designs/D-003.md`）フェーズ2「creator のサブエージェント化」を実施する。`run` スキルの「3. 作る」「4. review にする」に相当するロジックを `.claude/agents/creator.md` という新しいサブエージェント定義に切り出す。creator はタスク ID だけを受け取り、タスク票を読み、`bash scripts/rules.sh creator` が列挙するルールを読み、成果物を作り、確認コマンドを実行し、タスク票の「進捗」に記録して完了を報告する。計画票のタスク表（`vault/plans/<計画ID>.md`）と `vault/log/<計画ID>.md` への書き込みは行わない（状態更新とログ追記はオーケストレーター側の役目にする）。`.claude/hooks/agent_write_guard.py` に `agent_type == "creator"` 向けの拒否リスト方式のハード制限（`vault/plans/`・`vault/log/` への書き込みを常に拒否）を追加し、`.claude/skills/run/SKILL.md` をオーケストレーターが状態・ログを扱い成果物作成だけを creator に委譲する形に書き換え、`vault/rules/creator/creator.md` の記述を新しい役割分担と矛盾しないよう更新する（提案ファイル方式）。並行実行（フェーズ3）はこの計画では扱わない。

## 分割方針
成果物が重ならないよう4種類の変更（サブエージェント定義の新設／フックのハード制限／smoke.sh のケース追加／SKILL.md の書き換え／ルール文書の整合性更新）を5タスクに分ける。
- T-01（契約タスク）：`.claude/agents/creator.md` を新設する。creator の入出力仕様（タスク ID のみを受け取る、成果物と進捗だけを書く、blocked 判断は自分で確定させず報告する）をここで固定し、後続タスクはこれを参照する。
- T-02：`agent_write_guard.py` に creator 向けの拒否ルールを追加する（実装のみ）。T-01 の内容に依存せず独立して進められる。
- T-03：T-02 の変更を検証する smoke.sh ケースを追加する。T-02 の実装が無いとテストが書けないため `after: T-02`。
- T-04：`run/SKILL.md` を新しい役割分担に書き換える。creator の入出力仕様（T-01）を正しく参照する必要があるため `after: T-01`。T-02/T-03（フック実装）はテキストの正しさに必須ではないため依存させない。
- T-05：`vault/rules/creator/creator.md` の整合性を取る（提案ファイル方式。実体には書き込めないため `vault/tasks/<計画ID>/T-05-proposal.md` を成果物にする）。T-01 の役割定義と T-04 の最終的な SKILL.md 記述の両方と矛盾しないことを確認する必要があるため `after: T-01,T-04`。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | .claude/agents/creator.md の新設 | |
| T-02 | todo | 0 | - | agent_write_guard.py に creator 向け拒否ルールを追加 | |
| T-03 | todo | 0 | T-02 | smoke.sh に creator 向け expect_guard ケースを追加 | |
| T-04 | todo | 0 | T-01 | run/SKILL.md を creator 呼び出し形に書き換える | |
| T-05 | todo | 0 | T-01,T-04 | vault/rules/creator/creator.md の整合性更新（提案ファイル） | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補（参考、今回は起こさない）
- D-003 フェーズ3「並行実行オーケストレーション」：`HARNESS_MAX_PARALLEL` の導入、`run/SKILL.md` への着手可能集合の並行処理、verifier の `EnterWorktree` 対応。フェーズ1・2完了後に別計画として起こす。
</content>
