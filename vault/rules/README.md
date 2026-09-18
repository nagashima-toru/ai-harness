# vault/rules/ の書き方

作成エージェント・verifier・planner に渡す「ルール」の置き場。ハーネスは planner / creator / verifier の役割定義を標準ルールとして同梱する（`common/roles.md`・`creator/creator.md`・`verifier/verifier.md`・`planner/planner.md`）。コーディングルール・開発標準・方式設計・テスト観点などドメイン固有のルールはインストール先で書く。

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
`doing` / `review` 中のタスクがある間は、`vault/rules/` への書き込みをフックで拒否する。
