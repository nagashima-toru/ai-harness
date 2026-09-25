---
id: P-20260925-sandbox-hang-timeout
status: approved
---
# ゴール
GitHub issue #48（トリアージ済み）に対応する。`P-20260925-acceptance-test-sandbox-fp`（issue #46対応）の run 実行中、T-02 タスクの creator・verifier がパイプ・コマンド置換等の複合コマンドを実行しようとした際、issue #46で報告された「即時拒否」ではなく、Bash ツール呼び出しが無応答のままハングする事象を複数回（creator側2回、verifier側1回）観測した。orchestrator 側で都度 TaskStop による強制終了 → worktree の状態確認 → 再試行という手動介入が必要になり、1タスクの処理に実時間で1時間以上を要した。

トリアージ結果（人が確認済み、この計画の前提）：
- 分類は bug（プラットフォーム側の挙動不良）。原因は Claude Code のツール実行時サンドボックス（worktree 隔離のための git 検出）側にあり、`.claude/` 側のコードでは直接修正できないことは issue #46 対応（T-02）で確認済み
- Anthropic への報告は人が別途判断・実施するものであり、このリポジトリのタスクには含めない
- このリポジトリで実装可能な対応範囲は次の2方向に限る：
  1. `run` スキルに、creator/verifier 呼び出しがハングした場合の復旧手順（TaskStop 相当の強制終了後、worktree を破棄して再試行する／attempt 上限で blocked にする）を追加し、無応答のまま処理が止まり続ける事態を防ぐ
  2. `vault/rules/planner/planner.md`（提案ファイル方式）に、受け入れ基準の確認コマンドでパイプ・`&&`・コマンド置換等の複合コマンドを避ける指針を追記する（issue #46 対応の T-03 で追記済みの「rm -rf 前提にしない」指針と同じ節に、対象を複合コマンド全般に広げる形で追加する）

## 分割方針
- 対応可能な2方向はそれぞれ触るファイルが独立している（`.claude/skills/run/SKILL.md` と `vault/rules/planner/planner.md` への提案ファイル）ため、`after` 依存の無い2タスクに分ける
- T-01（planner.md への追記提案）：`vault/rules/planner/planner.md` はルールファイルのため、`docs/vault-spec.md` 12節の提案ファイル方式に従い `vault/tasks/<計画ID>/T-01-proposal.md` を成果物にする。issue #46 対応の T-03 で追記済みの「rm -rf 前提にしない」項目の直後に、複合コマンドを避ける指針を追加する内容
- T-02（run スキルへのハング復旧手順追加）：`.claude/skills/run/SKILL.md` に新しい見出しを追加し、creator/verifier の Agent 呼び出しが長時間応答しない場合の復旧手順（worktree の破棄・再試行、attempt 上限での blocked 化）を定める。「自動検出」まではこの計画の範囲に含めない（Agent ツール呼び出しは同期的にブロックするため、呼び出し中のエージェント自身が自分の呼び出しにタイムアウトを自動設定する手段は前提にしない。人またはオーケストレーターの運用者が気づいて止める前提の、停止後の復旧手順に絞る）
- 2タスクとも成果物ファイルが異なり、互いを前提にしないため `after` はすべて `-`
- issue の「Anthropic への報告」項目はこの計画に含めない（人が別途判断・実施する）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | planner.md に確認コマンドで複合コマンドを避ける指針を追記する提案を書く（issue #48） | |
| T-02 | done | 1 | - | run スキルに creator/verifier 呼び出しハング時の復旧手順を追加する（issue #48） | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01・T-02 とも `after` は `-`）
- 1タスクが1コンテキストで終わる粒度である
- T-01・T-02 のいずれも `vault/rules/` 配下の実体・`.claude/settings.json`・`.claude/hooks/` は変更しない（T-01 は提案ファイルのみ、T-02 は `.claude/skills/run/SKILL.md` のみを変更する）
