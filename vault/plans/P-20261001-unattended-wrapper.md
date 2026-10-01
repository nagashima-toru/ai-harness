---
id: P-20261001-unattended-wrapper
status: approved
---
# ゴール
`scripts/run_unattended.py` を新規作成する。環境変数 `HARNESS_RUN_CMD`（既定 `claude -p "/run"`）で指定したコマンドを、新しいプロセスグループで起動する。環境変数 `HARNESS_RUN_TIMEOUT`（秒、既定 3600）を過ぎたら、プロセスグループに SIGTERM を送り、10秒待っても終わらなければ SIGKILL を送り、終了コード124で終わる。時間内に終われば、子プロセスの終了コードをそのまま返す。`docs/runbook.md` の無人実行の手順を、このラッパーを cron・CI から呼ぶ形に書き換え、`.claude/skills/run/SKILL.md` の「ハング時の復旧」節に、無人実行ではラッパーが止め、次回の `/run` がフェーズ6の再開手順で続きから再開する旨を追記する。`scripts/smoke.sh` にテストを足す（issue #79、`vault/designs/D-010.md` フェーズ7）。

PR 本文では `Closes #79` を使う。

## 分割方針
- 依存の軸：ラッパー本体（T-01）を先に作り、その動作を固定するテスト（T-02）、それを呼ぶ運用文書（T-03）、run スキルの復旧節（T-04）が本体を参照する。実際の `claude` はどのタスクでも呼ばない
- `scripts/smoke.sh` を触るのは T-02 だけ。ファイルの衝突は無いので T-03・T-04 は T-01 の後に並行で着手できる（`after` は T-01 のみ）
- T-01：`scripts/run_unattended.py`（実装。標準ライブラリだけ）
- T-02：`scripts/smoke.sh` にラッパーのテスト（124、終了コード透過、孫プロセス終了、標準エラー行）を足す
- T-03：`docs/runbook.md` 3節の無人実行の手順をラッパー経由に書き換える
- T-04：`.claude/skills/run/SKILL.md`「ハング時の復旧」節に無人実行の記述を追記する
- 4タスクで7以内。`bash scripts/smoke.sh` の `fail=0` は各タスクの受け入れ基準に含める。次フェーズ候補は無い（D-010 のフェーズ8以降は別の計画）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | scripts/run_unattended.py を新規作成する（タイムアウト付きで HARNESS_RUN_CMD を実行） | |
| T-02 | todo | 0 | T-01 | scripts/smoke.sh に run_unattended.py のテストを足す | |
| T-03 | todo | 0 | T-01 | docs/runbook.md 3節の無人実行の手順を run_unattended.py 経由に書き換える | |
| T-04 | todo | 0 | T-01 | run SKILL.md「ハング時の復旧」節に無人実行時のラッパーの記述を追記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
