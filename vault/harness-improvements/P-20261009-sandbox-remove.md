# P-20261009-sandbox-remove の振り返り

## 気づいたこと
Claude Code の Web セッションでは、`scripts/vcs_finish.sh` の `gh pr create` が `HTTP 403: GitHub GraphQL is not available from Claude Code sessions` で失敗する（終了コード1）。`gh` コマンドはあるが GraphQL が使えない。run スキル手順7の代替経路（GitHub MCP で PR を作る）は「`gh` が無い（終了コード127）」場合だけが対象で、この失敗は対象外になっている。今回は環境の指示に従い MCP で PR を作った。`gh issue create`（手順8）も同じ理由で失敗する見込み。

## 該当箇所
- `.claude/skills/run/SKILL.md` 手順7・手順8
- `scripts/vcs_finish.sh`

## 提案
- 代替経路の対象に「`gh` の GraphQL が 403 で拒否された」場合を足す
- または `vcs_finish.sh` で、`gh pr create` の失敗が GraphQL の 403 の時は REST（`gh api repos/{owner}/{repo}/pulls`）で作り直す
