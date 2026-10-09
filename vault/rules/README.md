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
フックは `vault/rules/` への書き込みを止めない。タスクの「成果物」に宣言すれば変えられ、宣言の無い変更は差分ゲート `scripts/diff_gate.py` が差し戻す。変更は PR の差分で見える。
