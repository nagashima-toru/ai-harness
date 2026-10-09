---
id: P-20261010-harness-improvements-followup
status: approved
---
# ゴール
`vault/harness-improvements/` の4ファイル（D-015 の各フェーズの振り返り）の提案に対応し、対応が済んだ提案ファイルをこの計画の中で削除する

対応する項目（人の回答で確定済み）：
1. GitHub の PR・issue の作成を REST（`gh api`）に切り替える。`scripts/vcs_finish.sh` の GitHub の経路は `gh api` の `repos/<owner>/<repo>/pulls` で PR を作り（owner/repo は remote の URL から取る。タイトル・本文・`HARNESS_PR_BODY_FILE`・`HARNESS_PR_TITLE` の扱いは今と同じ。作った PR の URL を標準出力に出す）、run スキル手順8の issue の起票も `gh api repos/{owner}/{repo}/issues` にする。run・design スキルの「`gh` が無い時だけ MCP で代替」の段落は REST に合わせて直す。GitLab の経路は変えない
2. run スキル手順7で計画票の frontmatter を done にした後、`vcs_finish.sh` の前に計画票を名前で `git add` してコミットする手順を足す
3. verifier の変更ファイル一覧の検査（起点コミットを使う手順）と、creator の「起点コミットを記録する」手順を削る（`transition.py` の差分ゲートと重複しているため）
4. `scripts/diff_gate.py` の `FORBIDDEN_PREFIXES` から `vault/rules/` を外し、run スキルの注意の「フックでも拒否される」の文言を実態に合わせる
5. `.claude/hooks/agent_write_guard.py` の `main` 上の `git commit` の拒否を、コマンドを `&&`・`||`・`;`・`|`・改行で区切った各部分の先頭が `git commit`（`git` のオプションを挟む形を含む）の時だけにする

今後も「提案に対応した計画がそのファイルを消す」運用にすることを run スキル手順8に書き、`docs/vault-spec.md`・`docs/runbook.md` の該当記述も合わせる。各変更は `scripts/smoke.sh` にケースを足して確かめ、`bash scripts/smoke.sh | tail -1` が `fail=0` を含むこと。

## 分割方針
- 成果物のファイルごとに1タスク（コードは変更と smoke のケースを同じタスクに入れる）
  - T-01：項目1のうち `scripts/vcs_finish.sh`（REST での PR 作成）と smoke のケース
  - T-02：項目5 `.claude/hooks/agent_write_guard.py` と smoke のケース
  - T-03：項目4 `scripts/diff_gate.py` と smoke のケース
  - T-04：項目1のスキル側・項目2・項目4の注意の文言・提案ファイルの運用（`.claude/skills/run/SKILL.md`・`.claude/skills/design/SKILL.md`）と smoke のケース
  - T-05：項目3（`.claude/agents/verifier.md`・`.claude/agents/creator.md`）と、項目3・4で古くなるエージェント定義の記述（`.claude/agents/planner.md`・`creator.md` の `vault/rules/` の記述）と smoke のケース
  - T-06：文書（`docs/vault-spec.md`・`docs/runbook.md`・`README.md`・`vault/rules/README.md`）を T-01〜T-05 の後の実際の状態に揃え、古い記述がリポジトリ全体に残っていないことを確かめる
  - T-07：提案ファイル4つの削除と、計画全体の smoke のケースの確認（最後）
- T-01〜T-05 はどれも `scripts/smoke.sh` を変えるので、`after` で T-01→T-02→T-03→T-04→T-05 と直列にする。T-06 は全部の変更の後の姿を書くので T-05 の後、T-07 は対応タスクが全部済んだ後（T-06 の後）
- 項目4の結果として古くなる記述（`README.md`・`vault/rules/README.md`・`.claude/agents/planner.md`・`.claude/agents/creator.md` の「`vault/rules/` は宣言があっても差分ゲートが違反にする」）は、ゴールの「該当記述も合わせる」の範囲として直す。ゴールの対象を増やすのではなく、変更で事実と食い違う記述を残さないため
- `vault/rules/README.md` は T-03（差分ゲートから `vault/rules/` を外す）が done になって計画ブランチに入った後なら、宣言すれば creator のタスクで変えられる（`transition.py` は計画ブランチの `scripts/diff_gate.py` を import する）。そのため T-06 の成果物に入れ、T-06 は T-03 より後にする
- `docs/decisions.md` は判断の記録なので過去の行を書き換えない（各タスクの確認の範囲から外す）。`vault/archive/`・`vault/plans/`・`vault/tasks/`・`vault/log/`・`vault/verdicts/`・`vault/designs/` は履歴・状態なので確認の範囲から外す
- `.claude/settings.json` の `permissions.allow` には `Bash(gh api *)` を足さない（`gh api` は任意の API を呼べ、`gh pr merge` の拒否を迂回できるため。ゴールにも無い）。run スキル手順8の `gh api` が権限で通らない時は、既存の手順8の4（失敗したらファイルに書き残す）で扱う

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | vcs_finish.sh の GitHub の PR 作成を REST（gh api）にし smoke にケースを足す | |
| T-02 | todo | 0 | T-01 | agent_write_guard の main 上の git commit の拒否を各部分の先頭だけにし smoke にケースを足す | |
| T-03 | todo | 0 | T-02 | diff_gate の FORBIDDEN_PREFIXES から vault/rules/ を外し smoke のケースを直す | |
| T-04 | todo | 0 | T-03 | run・design スキルを REST の起票・計画票のコミット・提案ファイルの運用・vault/rules の注意に合わせる | |
| T-05 | todo | 0 | T-04 | creator・verifier の起点コミットの手順を削り、エージェント定義の vault/rules の記述を差分ゲートに合わせる | |
| T-06 | todo | 0 | T-05 | vault-spec・runbook・README・rules/README を今回の変更に揃え、古い記述が残っていないことを確かめる | |
| T-07 | todo | 0 | T-06 | 対応済みの提案ファイル（vault/harness-improvements/ の4ファイル）を削除する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
