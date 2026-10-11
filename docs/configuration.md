# 環境変数リファレンス

ai-harness の動作は `HARNESS_` で始まる環境変数で調整できる。このファイルは、利用者が指定できる変数の意味・既定値・読むもの・使う場面・詳しい説明へのリンクを一覧にする。どの変数も未設定のままで動く。

## 設定のしかた

- シェルで `export HARNESS_…=…` する。そのシェルから起動するセッションと、その子プロセスに効く。
- 1回だけ変えたい時は `env HARNESS_…=値 <コマンド>` の形で実行する。
- 恒久的に変えたい時は `.claude/settings.json` の `env` に書く。例は `docs/install.md` の「main 以外のブランチをベースにする（任意）」にある。
- セッションの起動後に変えても、run の Bash に効かない場合がある。変えたら起動し直す（`docs/runbook.md` 8節と同じ注意）。

## 利用者が設定する変数

| 変数 | 意味 | 既定値 | 読むもの | 使う場面 | 詳しく |
|---|---|---|---|---|---|
| `HARNESS_BASE_BRANCH` | ベースブランチ名。PR の base、`/plan`・`/design` が切る元、直接コミットの禁止の対象になる。 | `main`（前後の空白を除いて空なら `main`） | `scripts/vcs_finish.sh`・`scripts/purge_plan.sh`・`.claude/hooks/agent_write_guard.py`・`.claude/skills/plan/SKILL.md`・`.claude/skills/design/SKILL.md` | develop など main 以外のブランチをベースにする導入先。 | [docs/install.md の「main 以外のブランチをベースにする（任意）」](install.md)・[docs/vault-spec.md の 1節](vault-spec.md) |
| `HARNESS_PUSH_BRANCH` | push 先のブランチ名。指定すると PR の head もそのブランチになる。 | 未設定（現在のブランチに push し、PR の head も現在のブランチ） | `scripts/vcs_finish.sh`・`.claude/skills/plan/SKILL.md`・`.claude/skills/design/SKILL.md` | push 先が指定されるクラウドセッション。 | [docs/runbook.md の 10節](runbook.md)・[docs/vault-spec.md の 1節](vault-spec.md) |
| `HARNESS_MAX_ATTEMPTS` | 1タスクの試行回数の上限。超えると blocked になる。 | `3` | `scripts/transition.py`・`.claude/hooks/stop_gate.py` | 差し戻しを許す回数を増減したい時。 | [docs/vault-spec.md の 2節](vault-spec.md) |
| `HARNESS_MAX_PARALLEL` | 同時に着手するタスクの最大数。 | `3`（スクリプトは読まず、run スキル（オーケストレーター）が読む） | `.claude/skills/run/SKILL.md` | 並列数を絞りたい、または増やしたい時。 | [docs/vault-spec.md の 2節](vault-spec.md) |
| `HARNESS_CREATOR_MODEL` | creator のモデルを上書きする。log の `creator=` にも記録される。 | 未設定（`.claude/agents/creator.md` の frontmatter の `model` を使う） | `.claude/skills/run/SKILL.md`・`scripts/transition.py` | creator に使うモデルを比べる時や、frontmatter を変えずに切り替えたい時。 | [docs/runbook.md の 8節](runbook.md)・[docs/vault-spec.md の 7節](vault-spec.md) |
| `HARNESS_STRICT_STOP` | `1` で Stop フックが stop_hook_active を無視して厳格に判定する。 | Stop フック単体では `0`。`scripts/run_unattended.py` 経由では、未設定（キーが無い）なら `1` を入れて子に渡す | `.claude/hooks/stop_gate.py`・`scripts/run_unattended.py` | 放置して回す無人実行で、未完了のまま止まらせたくない時。 | [docs/runbook.md の 3節](runbook.md)・[docs/vault-spec.md の 9節](vault-spec.md)・[docs/vault-spec.md の 14節](vault-spec.md) |
| `HARNESS_VCS_HOST` | PR/MR を作るホスティングの種類。github・gitlab・none・auto のいずれか。 | `auto`（origin の URL から github / gitlab / none を判定） | `scripts/vcs_finish.sh` | origin の URL から判定できない時や、PR を作らず案内だけにしたい時。 | [docs/vault-spec.md の 1節](vault-spec.md)・`scripts/vcs_finish.sh` の冒頭のコメント（docs に専用の説明が無いため） |
| `HARNESS_RUN_CMD` | 無人実行ラッパーが走らせるコマンド。シェルを経由せず分割して実行される。 | `claude -p "/run"` | `scripts/run_unattended.py` | cron・CI から実行するコマンドを変えたい時。 | [docs/runbook.md の 3節](runbook.md)・[docs/vault-spec.md の 14節](vault-spec.md) |
| `HARNESS_RUN_TIMEOUT` | 無人実行ラッパーのタイムアウト（秒、整数）。超えると止めて終了コード124で終わる。 | `3600`（秒） | `scripts/run_unattended.py` | 無人実行の最大時間を変えたい時。 | [docs/runbook.md の 3節](runbook.md)・[docs/vault-spec.md の 14節](vault-spec.md) |

## run が内部で渡す変数

run が `scripts/vcs_finish.sh` に渡す内部用で、利用者は通常設定しない。

| 変数 | 意味 | 既定値 | 読むもの | 使う場面 | 詳しく |
|---|---|---|---|---|---|
| `HARNESS_PR_BODY_FILE` | PR の本文にするファイルのパス。 | 未設定（引数なしの `vcs_finish.sh` は「タスク履歴」表を本文にする） | `scripts/vcs_finish.sh`（`.claude/skills/run/SKILL.md` の手順7が渡す） | 全タスクが done になった後の PR 作成。run が自動で渡す。 | [docs/vault-spec.md の 1節](vault-spec.md)・`.claude/skills/run/SKILL.md` の手順7 |
| `HARNESS_PR_TITLE` | PR のタイトル。`HARNESS_PR_BODY_FILE` の経路でだけ使う。 | 未設定（`HARNESS_PR_BODY_FILE` の経路で、計画ID、無ければ現在のブランチ名） | `scripts/vcs_finish.sh`（`.claude/skills/run/SKILL.md` の手順7が渡す） | 全タスクが done になった後の PR 作成。run が自動で渡す。 | [docs/vault-spec.md の 1節](vault-spec.md)・`.claude/skills/run/SKILL.md` の手順7 |
