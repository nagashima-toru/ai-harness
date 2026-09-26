---
id: P-20260926-run-creator-verifier-sync
status: approved
---
# ゴール
issue #63（本文＋統合コメント #65）に基づき、`/run` スキルの Agent ツール呼び出しまわりの2つの不具合を修正する。

1. `.claude/skills/run/SKILL.md` 手順3（creator 呼び出し）・手順5（verifier 呼び出し）に `run_in_background: false` を明記する。既定（バックグラウンド実行）のまま呼ぶと、creator/verifier の完了前にオーケストレーターの応答が終わろうとし、Stop フックにブロックされる「ブロック→原因調査→待機」の往復が再発する（実セッションで実際に再現済み）。
2. `.claude/skills/run/SKILL.md` 手順6（PASS 時の `review→done` 遷移）に、verifier が書いた `vault/verdicts/<計画ID>/<id>.json` を計画票・log と合わせてその場で `git add`・コミットする指示を追記する。これが無いと、最後のタスクの done 遷移がコミットされないまま `vcs_finish.sh` まで進み、verdict がリモートに反映されない PR が作られうる（実際に発生し、`gh pr create` の警告で偶然気づいた事例あり）。
3. `.claude/skills/plan/SKILL.md` の planner 呼び出し（手順A.4）にも同様の観点が抜けていることを確認したため、同じ修正を行う。

`.claude/hooks/stop_gate.py` のエラーメッセージ改善（「未完了」か「呼び忘れ」かを区別する）は元 issue の提案1のオプションであり、今回のスコープには含めない（末尾「次フェーズの候補」参照）。

## 分割方針
- 3箇所の修正はすべて Markdown（SKILL.md）のテキスト追記であり、コードの契約タスク・実装タスクという分割は不要。代わりに「どのファイルのどの箇所を触るか」で分割した
- T-01（run/SKILL.md 手順3・5）と T-02（run/SKILL.md 手順6）は同じファイルを触るため、`after` で T-02 を T-01 に依存させ、逐次処理にする（同一計画ブランチへの並行 worktree マージでの意図しない競合を避ける。`vault/rules/planner/planner.md` は具体的な粒度基準を扱うが、同一ファイルの複数タスク編集リスクの回避は本計画固有の判断として `after` で解決した）
- T-03（plan/SKILL.md）は別ファイルのため独立して着手可能（`after: -`）
- 各タスクの受け入れ基準は、該当節をいったん `sed` で一時ファイルに抜き出してから `grep` で判定する形にした。パイプ・`&&` を含む複合コマンドによるサンドボックスのハング（issue #46, #48）を避けるための書き方（`vault/rules/planner/planner.md` の既知の失敗パターン反映）
- 「成果物ファイルのみで他ファイル不変」の確認は `git status --porcelain` を一時ファイルへ書き出す形にし、除外対象にタスク票自身（`vault/tasks/<計画ID>/<id>.md`）を含めた（`vault/rules/planner/planner.md` の反映）
- `.claude/hooks/stop_gate.py` のエラーメッセージ改善は、フックのロジック変更（doing/review の集合判定に「未完了か呼び忘れか」の区別を追加する）を伴い、テキスト追記のみの本計画の他タスクより難度・リスクが高いため、次フェーズの候補として計画票末尾に残すのみとし、本計画のタスクにはしない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | run/SKILL.md 手順3・5に run_in_background: false を明記する | |
| T-02 | todo | 0 | T-01 | run/SKILL.md 手順6の review→done 遷移に verdict の git add・コミットを明記する | |
| T-03 | review | 1 | - | plan/SKILL.md 手順A.4に run_in_background: false を明記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-02 は T-01 にのみ依存、T-03 は独立）
- 1タスクが1コンテキストで終わる粒度である（いずれも1ファイル・数行のテキスト追記）
- 全タスク完了後、`.claude/skills/run/SKILL.md` の手順3・5・6と `.claude/skills/plan/SKILL.md` の手順A.4に、それぞれ `run_in_background: false`（run 側2箇所・plan 側1箇所）または verdict の git add・コミット指示が反映されている

## 次フェーズの候補
- `.claude/hooks/stop_gate.py` のエラーメッセージ改善：doing/review のタスクについて verdict が無い場合に、「creator/verifier がまだ完了していないだけ」なのか「呼び出し自体を忘れている」のかを区別する情報を出す（元 issue #63 の提案1のオプション部分）。区別には、例えば対象タスクの worktree の有無・直近ログの有無などを判定材料に使える可能性があるが、フックのロジック変更を伴うため別計画として起票するのが望ましい

## 人への質問
（なし）
