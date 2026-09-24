---
id: P-20260924-worktree-isolation-guard
status: approved
---
# ゴール

GitHub Issue #20（nagashima-toru/ai-harness）の不具合を修正する。`P-20260924-license`（Issue #17, #18）の `/run` 実行中、`isolation: "worktree"` で creator/verifier サブエージェントを並行実行した際に見つかった、worktree 隔離まわりの2つの独立した問題を直す。

1. `.claude/hooks/agent_write_guard.py` が worktree 内の正当な書き込み（例：`vault/verdicts/<計画ID>/<id>.json`）を誤って拒否する。原因はフックの書き込み先の root 解決が `CLAUDE_PROJECT_DIR`（常にメインチェックアウトを指す）に偏っていること。加えて、`2>&1` のような fd 複製がリダイレクト（書き込み）と誤検知され拒否される問題もある
2. `isolation: "worktree"` で作られる worktree の起点が、既定の `worktree.baseRef: "fresh"` のため計画ブランチではなく `origin/main` になってしまい、計画票・タスク票が無い状態で creator/verifier が動くことがある。`run/SKILL.md` 手順3.6が前提にしている「Agent ツールの起点指定フィールド」は実際には見当たらなかった

## 分割方針

問題1と問題2は原因も直す場所も独立しているため、別タスクに分ける。

- T-01：問題1（`agent_write_guard.py` の root 解決と `2>&1` 誤検知）を直す。成果物は同一ファイル内の関連する2つの不具合修正なので1タスクにまとめ、`scripts/smoke.sh` に回帰テストを追加する
- T-02：問題2（worktree の起点を計画ブランチにする既定設定）を直す。`.claude/settings.json` に `worktree.baseRef: "head"` を追加し、それを前提に `run/SKILL.md` 手順3.6（起点がずれた場合の対処）の記述を実態に合わせて書き直す

両タスクは依存関係が無く、`after` は張らない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | agent_write_guard.py の worktree root 解決と 2>&1 誤検知を修正する | |
| T-02 | review | 1 | - | worktree.baseRef を head にし run/SKILL.md 手順3.6を実態に合わせる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01・T-02 とも `after: -`）
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh` が全タスク完了後もPASSする

## 人への質問
- `scripts/merge_settings_json.py` は現状 `hooks`・`permissions.deny` しかマージ対象にしておらず、T-02 で追加する `worktree.baseRef` はこの計画のインストール先（他リポジトリ）には自動反映されない。他リポジトリへの伝播が必要であれば別途計画してほしい（今回はこのリポジトリ自身の `/run` 実行を直すことが目的のため対象外とした）
