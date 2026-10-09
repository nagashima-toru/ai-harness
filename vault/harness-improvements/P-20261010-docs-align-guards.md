# ハーネス改善提案（P-20261010-docs-align-guards）

`gh issue create` が HTTP 403（Claude Code の Web セッションでは GitHub GraphQL が使えない）で失敗したため、ここに残す。

## 1. vcs_finish.sh の代替経路が GraphQL 403 を拾わない
- 気づいたこと：Web セッションでは `gh` コマンドはあるが `gh pr create`・`gh issue create` が GraphQL の 403 で失敗する。run スキル手順7の代替（GitHub MCP で作る）は「コマンドが無い」時だけで、この失敗は対象外と書かれている。今回はオーケストレーターが判断で MCP の `create_pull_request` を使った
- 該当箇所：`.claude/skills/run/SKILL.md` 手順7・8、`scripts/vcs_finish.sh`
- 提案：GraphQL の 403 も代替の対象に足す（または `vcs_finish.sh` が REST の `gh api repos/{owner}/{repo}/pulls` で作る）。手順8の `gh issue create` も同様

## 2. vault/rules/ の扱いが差分ゲートと D-015 で食い違っている
- 気づいたこと：D-015 は `vault/rules/` の保護をやめたが、`scripts/diff_gate.py` は今も `vault/rules/` 配下の変更を宣言があっても違反にする。このため `vault/rules/README.md` をタスクで直せず、人の手作業が残った（PR #142）。`.claude/skills/run/SKILL.md` の注意「フックでも拒否される」も実態（差分ゲートが止める）とずれている
- 該当箇所：`scripts/diff_gate.py` の `FORBIDDEN_PREFIXES`、`.claude/skills/run/SKILL.md` の注意
- 提案：`vault/rules/` を残すか外すかを決め、外すなら宣言すれば許す形にする。run スキルの注意の文言も合わせる
