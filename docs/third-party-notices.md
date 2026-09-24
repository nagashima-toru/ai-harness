# サードパーティ通知（Third-Party Notices）

このリポジトリを public 化するにあたり、選定ライセンス（MIT License、
`Copyright (c) 2026 nagashima-toru`。T-01 で決定）との互換性確認のため、
以下の対象について外部由来のコード・雛形が含まれていないかを確認した結果を記録する。

## 調査対象と方法

調査対象は T-03 の「決定済み」で指定された範囲に限る。

- `.claude/skills/` 配下の全ファイル
- `.claude/hooks/` 配下の全ファイル
- `.claude/agents/` 配下の全ファイル
- `.claude/settings.json`
- `vault/rules/` 配下の全ファイル

上記の実ファイルをすべて読み、外部プロジェクト・OSS ライブラリ・チュートリアル等からの
コピー由来と判断できる記述（ライセンスヘッダー、出典コメント、既知ライブラリのボイラープレート
コードとの一致など）が無いかを確認した。

## `.claude` 配下の確認結果

対象ファイル一覧（実ファイルを1つずつ読んで確認）：

- `.claude/skills/design/SKILL.md`
- `.claude/skills/plan/SKILL.md`
- `.claude/skills/run/SKILL.md`
- `.claude/hooks/stop_gate.py`
- `.claude/hooks/plan_guard.py`
- `.claude/hooks/agent_write_guard.py`
- `.claude/agents/planner.md`
- `.claude/agents/verifier.md`
- `.claude/agents/creator.md`
- `.claude/settings.json`

**確認結果：該当なし。**
いずれもこのリポジトリ（AI協働ハーネス）固有の運用（`vault/` の状態遷移、Stop/PreToolUse/
PostToolUse フックによる書き込み制御、`plan`/`run`/`design` スキル定義）を記述したオリジナルの
Markdown・Python・JSON であり、外部プロジェクトからのコピー・雛形の流用と判断できる記述は
見つからなかった。ライセンスヘッダーや出典コメント、既知の OSS テンプレートとの一致も無い。

## `vault/rules` 配下の確認結果

対象ファイル一覧（実ファイルを1つずつ読んで確認。`.gitkeep` は空ファイルのため内容確認は不要）：

- `vault/rules/README.md`
- `vault/rules/common/git.md`
- `vault/rules/common/roles.md`
- `vault/rules/common/.gitkeep`
- `vault/rules/creator/creator.md`
- `vault/rules/creator/git-workflow.md`
- `vault/rules/creator/.gitkeep`
- `vault/rules/planner/planner.md`
- `vault/rules/planner/.gitkeep`
- `vault/rules/verifier/verifier.md`
- `vault/rules/verifier/.gitkeep`

**確認結果：該当なし。**
いずれも本リポジトリの役割定義（planner / creator / verifier の責務、git 運用方針）を記述した
オリジナルの Markdown であり、外部由来のコード・雛形は見つからなかった。

## 結論

`.claude/skills/`・`.claude/hooks/`・`.claude/agents/`・`.claude/settings.json`・`vault/rules/`
配下のいずれについても、外部由来のコード・雛形は見つからなかった（該当なし）。したがって
選定ライセンス（MIT License）との互換性判断（出典URL・元ライセンス名の記載）は不要と判断する。

今後、これらのディレクトリに外部由来のコード・雛形を追加する場合は、本ファイルに出典URL・
元ライセンス名・MIT License との互換性判断を追記すること。
