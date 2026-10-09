# P-20261010-stop-gate-verdict-only のハーネス振り返り

## 1. 計画票の status: done がコミットされない
- 気づいたこと：run の手順7.1で計画票の frontmatter を done にした後、`scripts/vcs_finish.sh` は push して PR を作るが、この変更をコミットしない。今回は未コミットのまま push され、手でコミットして push し直した
- 該当箇所：`.claude/skills/run/SKILL.md` 手順7、`scripts/vcs_finish.sh`
- 提案：手順7.1の後に計画票を名前で add してコミットする手順を足すか、vcs_finish.sh が push の前に計画票の変更をコミットする

## 2. Claude Code の Web セッションで gh の PR 作成が 403 になり、代替の条件に当たらない
- 気づいたこと：`gh pr create` が `HTTP 403: GitHub GraphQL is not available from Claude Code sessions` で失敗した（終了コード1）。手順7の代替は「gh/glab コマンドが無い時」だけが対象で、この失敗は文言上は対象外。今回は GitHub MCP の create_pull_request で作った
- 該当箇所：`.claude/skills/run/SKILL.md` 手順7の代替の段落、`scripts/vcs_finish.sh`
- 提案：GraphQL が使えない旨の 403 も、MCP で代替してよい場合に足す（または vcs_finish.sh が REST の `gh api` で PR を作る）。手順8の `gh issue create` も同じ理由で失敗するので同様に扱う
