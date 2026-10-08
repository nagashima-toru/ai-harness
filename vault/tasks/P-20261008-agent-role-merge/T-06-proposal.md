# T-06 提案：vault/rules/README.md の書き換えと旧ルール6本の削除

## 提案：vault/rules/README.md の全文

````markdown
# vault/rules/ の書き方

ハーネスは標準ルールを同梱しない。planner / creator / verifier の役割定義は `.claude/agents/creator.md`・`.claude/agents/verifier.md`・`.claude/agents/planner.md` にある（git 運用も `.claude/agents/creator.md` にある）。`vault/rules/` は導入先のルール専用の置き場で、作成エージェント・verifier・planner に渡すコーディングルール・開発標準・方式設計・テスト観点などをインストール先で書く。旧版の install で配った役割定義のルールは、`bash scripts/install.sh --update` が未編集なら削除し、編集済みなら残して note で案内する。

## 振り分け（ディレクトリだけで決める）
- `common/`：作成エージェント・verifier・planner の全員に渡す
- `creator/`：作成エージェントだけに渡す
- `verifier/`：verifier だけに渡す
- `planner/`：planner だけに渡す

## 書き方
- ファイルは `*.md`、小文字ケバブケース。雛形は `vault/templates/rule.md`
- 読み込み順は `common/` → 役割ディレクトリ、各ディレクトリ内はファイル名順
- 1ファイルは100行以内を目安に、話題ごとに分ける

## verifier との関係
ルールは受け入れ基準を増やすものではなく、基準の判定方法を与えるもの。受け入れ基準が「`vault/rules/` のコーディングルールに従っている」のようにルールを参照した時だけ、verifier はルールを根拠に判定する。

## 注意
エージェントは `vault/rules/` に書けない（タスクの状態を問わず、フックが常に拒否する）。ルールの追加・変更は人が直接編集する。ルールの変更をタスクにする時は `vault/tasks/<計画ID>/<id>-proposal.md` に下書きし、人が反映する。
````

## 人が行う作業

PR のマージ前に、この計画のブランチ（`work/p-20261008-agent-role-merge`）上で行う。

1. 旧ルール6本を削除する。

```
git rm vault/rules/common/roles.md
git rm vault/rules/common/git.md
git rm vault/rules/creator/creator.md
git rm vault/rules/creator/git-workflow.md
git rm vault/rules/verifier/verifier.md
git rm vault/rules/planner/planner.md
```

2. 上の `## 提案：vault/rules/README.md の全文` のコードブロックの中身を `vault/rules/README.md` に貼って全文を置き換える（`# vault/rules/ の書き方` の行から）。
3. コミットする。
4. `bash scripts/smoke.sh 2>&1 | tail -1` を実行し、出力に `fail=0` を含むことを確かめる。
5. T-07 の提案ファイル（`vault/tasks/P-20261008-agent-role-merge/T-07-proposal.md`）も反映する。

`vault/rules/planner/ai-harness-lessons.md` と各ディレクトリの `.gitkeep` は削除せず残す。
