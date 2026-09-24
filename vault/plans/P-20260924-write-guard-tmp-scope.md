---
id: P-20260924-write-guard-tmp-scope
status: draft
---
# ゴール

`.claude/hooks/agent_write_guard.py` の verifier 向け Bash 書き込み制限（`BASH_WRITE_PATTERNS` に一致するコマンドを `vault/verdicts/` 以外一律で拒否する判定）が、`/tmp` のようなリポジトリと無関係な一時ディレクトリへの `mkdir`/`cp`/`touch` 等まで巻き込んで拒否してしまう不具合（GitHub Issue #27）を直す。

`P-20260924-uninstall-harness`（PR #26）の T-03・T-04 検証で、`scripts/uninstall.sh`・`scripts/install.sh` の受け入れ基準が要求する「一時ディレクトリにインストールして動作確認する」を verifier が実行できず、静的レビューだけで PASS 判定した経緯がある。verifier の書き込み先制限を、対象パスが `root`（リポジトリ）配下かどうかで判定するように直し、リポジトリ内は引き続き `vault/verdicts/` のみに制限しつつ、リポジトリ外の一時作業を許可する。

## 分割方針
バグ修正1本（`.claude/hooks/agent_write_guard.py` の判定ロジック修正 + `scripts/smoke.sh` への回帰テスト追加）で完結するスコープであり、成果物も同一 PR に閉じるため、契約タスクと実装タスクに分ける必要が無い。1タスク（T-01）のみで構成する。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | agent_write_guard: verifier の Bash 書き込み制限をリポジトリ外の一時作業に限り許可する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
（なし）
