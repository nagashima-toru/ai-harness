---
id: P-20260925-acceptance-test-sandbox-fp
status: approved
---
# ゴール
GitHub issue #46 に対応する。`P-20260925-vcs-finish-push-and-diff-criteria`（issue #44, #42、PR #45）の run 実行で、creator・verifier が受け入れ基準の確認コマンドをそのまま実行できず、その場で代替コマンドに書き換えて回避した2件について、原因の特定と対応案（実際の反映方針は人が判断する）をまとめる。

1. verifier が `scripts/vcs_finish.sh` の自動push機能テスト（`mktemp -d` で用意した一時ディレクトリの後片付け）で `.claude/settings.json` の `permissions.deny` にある `Bash(rm -rf *)` 系パターンに阻まれ、固定パス（`/tmp/vftest_a` 等）へ書き換えて回避した（後片付け不能・並行実行時の衝突リスクが残る）。
2. creator が `grep -c "git diff main" T-02-proposal.md` 相当の単純な文字列検索を実行しようとしたところ、コマンド文字列に `git` という語が含まれることを理由に拒否された。`Bash(grep *)` は無条件許可されているため、原因が `.claude/hooks/agent_write_guard.py` かプラットフォーム側のサンドボックスかは未確認。

issue は「原因切り分けは未実施」「対応方針は人の判断に委ねる」と明記している。この計画は各項目について実装まで踏み込まず、`.claude/settings.json` を書き換えずに済む「提案」または「調査結果」を成果物とし、人が方針を決めた後の実装は別計画に回す。

## 分割方針
- issue の「該当箇所」に挙がる3点（`.claude/settings.json` の `rm -rf` deny・`vault/rules/planner/planner.md` の指針欠如・grep誤検知の原因未特定）は、触るファイル・調査対象が独立しているため、`after` 依存の無い3タスクに分ける。
- T-01（`.claude/settings.json` の rm -rf deny 見直し）：direction を人に委ねるため、実体を書き換えず `vault/tasks/<計画ID>/T-01-proposal.md` に複数案（diff付き）を書く提案タスクにする。`.claude/settings.json` は `vault/rules/` の外で `agent_write_guard.py` の改ざん防止対象ではないが、方針選択を人に委ねる指示があるため、実体変更ではなく提案ファイルを成果物にする。
- T-02（grep 誤検知の原因切り分け）：`.claude/hooks/agent_write_guard.py` を模擬実行して deny するかどうかを直接確認できる（planner が事前に確認済み：`BASH_WRITE_PATTERNS` はいずれも `grep -c "git diff main" ...` に一致しないため hook は deny しない）。creator は同じ手順を再現して記録し、結論（hook由来か否か）と対応候補の列挙までに留め、対応の実装は行わない独立タスクにする。
- T-03（planner.md への機能テスト指針の追記提案）：`vault/rules/planner/planner.md` はルールファイルのため、`docs/vault-spec.md` 12節の提案ファイル方式に従い `vault/tasks/<計画ID>/T-03-proposal.md` を成果物にする。rm -rf 前提にしない受け入れ基準の書き方を追記する内容で、T-01 の結論（rm -rf deny パターンをどう変えるか）を待たずに、現状の制約を前提に独立して書ける。
- grep誤検知（T-02）への対応そのもの（planner.md への追記や別ガードの追加）はこの計画に含めない。T-02 の結論を見てから人が次の計画を起こす。
- 3タスクとも成果物ファイルが異なり、互いを前提にしないため `after` はすべて `-`。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | settings.json の rm -rf deny パターン見直しの提案を書く（issue #46） | |
| T-02 | done | 3 | - | grep 誤検知（issue #42 時の事象）の原因が hook かサンドボックスかを切り分ける（issue #46） | |
| T-03 | done | 1 | - | planner ルールに rm -rf 前提にしない機能テスト指針を追記する提案を書く（issue #46） | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01・T-02・T-03 とも `after` は `-`）
- 1タスクが1コンテキストで終わる粒度である
- T-01・T-02・T-03 のいずれも `.claude/settings.json`・`.claude/hooks/agent_write_guard.py`・`vault/rules/` 配下の実体は変更しない（各タスクの提案・調査結果ファイルのみを変更する）
