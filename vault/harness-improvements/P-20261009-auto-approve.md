# P-20261009-auto-approve の振り返り（gh issue create が GraphQL の HTTP 403 で失敗したためのフォールバック）

1. `scripts/vcs_finish.sh` の `gh pr create` は、Claude Code のクラウドセッションでは GraphQL の HTTP 403 で失敗する。run スキル手順7の代替経路（MCP で PR を作る）は command not found の時だけが対象で、この失敗は対象外と読める（今回は MCP で PR #137 を作った）。提案：403（GraphQL 不可）も代替の対象に含めるか、`vcs_finish.sh` を REST（`gh api`）で PR を作る形にする。また `vcs_finish.sh` は計画票の `status: done` をコミットしないので、手順7の1の後にコミットする手順を明記する。手順8の `gh issue create` も同じ理由で失敗する
2. T-05・T-07・T-08 で、creator がタスク票の「進捗」に起点コミットを書かなかった。そのため verifier は変更ファイル一覧の検査を省いた。提案：`creator.md` で起点コミットの記録を必須にするか、verifier が log の `plan_head` を使う
3. verifier・creator が Bash で実行した `grep -c` を、フックが拒否した（引数に `git add` などの文字列を含む場合）。D-015 フェーズ3 で Bash の書き込み解析を削れば解消する見込み
