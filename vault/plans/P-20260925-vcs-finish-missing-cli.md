---
id: P-20260925-vcs-finish-missing-cli
status: approved
---
# ゴール
GitHub issue #37 の対応。`scripts/vcs_finish.sh` は `HARNESS_VCS_HOST=auto`（既定）で
`git remote get-url origin` の値から `github`/`gitlab`/`none` を自動判定し、`github` と判定
されたら無条件に `gh pr create "$@"` を、`gitlab` なら `glab mr create "$@"` を呼ぶ。しかし
`gh`/`glab` コマンド自体がインストールされていない環境（GitHub MCP 経由のアクセスのみの環境
など）では、これが `command not found`（exit 127）で失敗し、`run`/`design` 両スキルの最終手
順（PR作成）が完了できない。この代替経路（GitHub MCP ツールでの直接PR作成）はスキル手順に明
文化されておらず、毎回オーケストレーターが独自に判断し直している。

`scripts/vcs_finish.sh` の `github`/`gitlab` 分岐に `command -v gh`/`command -v glab` による
存在チェックを追加し、無い場合は分かりやすいエラーメッセージを標準エラーに出して0以外の終了
コードで終わるようにする（`none` 判定時の案内文とは文面・意味を区別する）。あわせて
`.claude/skills/run/SKILL.md` と `.claude/skills/design/SKILL.md` の両方に、この失敗時に
GitHub MCP ツール（例: `mcp__github__create_pull_request`）で同内容の PR を代わりに作成して
よい旨と、`gh pr create` に渡すはずだった情報（ブランチ名・タイトル・本文）を MCP ツール呼び出
しに引き継ぐ旨を明記する。GitLab（`glab`）についても同様に MCP 等の代替手段があれば使ってよい
旨、無ければ人に案内して止まる旨を明記する。`gh pr merge`/`glab mr merge` の実行は今回も一切追
加しない（マージは人が行うという既存の安全境界を維持する）。

Bitbucket 等それ以外のホスティング対応、`agent_write_guard.py` の GitHub 固有改ざん検知の拡張、
PR/MR タイトル・本文の自動生成ロジックの追加はスコープ外（D-005 で対象外と明記済みの範囲を今回
も維持する）。

## 分割方針
D-005 フェーズ1（`P-20260924-vcs-finish`、完了済み）が意図的に対象外とした「`gh`/`glab` 未イ
ンストール時のエラーハンドリング」を今回埋める。成果物は独立した2種類（スクリプト本体1・スキ
ル手順2ファイル）に分かれるが、スキル手順側は「T-01 で確定したエラーメッセージ・終了コードを
前提に、GitHub MCP 代替手順を明記する」という同じ性質の追記なので、ファイル単位で3タスクに割
る。

- T-01（`scripts/vcs_finish.sh`）：`gh`/`glab` の存在チェックとエラーメッセージ・終了コードを
  確定する「契約」タスク。T-02・T-03 が参照するメッセージ文言・終了コードをここで先に決める
- T-02（`.claude/skills/run/SKILL.md`）・T-03（`.claude/skills/design/SKILL.md`）：T-01 の結
  果を前提に、GitHub MCP／GitLab 代替手順を追記する独立作業。成果物ファイルが重ならず、T-02・
  T-03 間に依存は無いため、T-01 完了後は並行して着手できる
- `docs/vault-spec.md`・`docs/runbook.md` は確認した結果、`gh pr create` 前提の記述はすでに
  `scripts/vcs_finish.sh` 経由の表現に統一済み（`P-20260924-vcs-finish` で対応済み）で、かつ
  「エラー時の挙動」を断定する記述も無いため、今回の変更と矛盾しない。追記・修正タスクは起こさ
  ない
- 次フェーズの候補は無い（issue #37 はこの3タスクで完結する）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | vcs_finish.sh に gh/glab の存在チェックとエラーメッセージを追加する | |
| T-02 | todo | 0 | T-01 | run スキルに GitHub/GitLab MCP 代替手順を明記する | |
| T-03 | todo | 0 | T-01 | design スキルに GitHub/GitLab MCP 代替手順を明記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
