---
id: P-20260925-write-guard-placeholder
status: approved
---
# ゴール

GitHub issue #54 に対応する。`.claude/hooks/agent_write_guard.py` の `PreToolUse:Bash` 判定にあるリダイレクト検出用正規表現（`BASH_WRITE_PATTERNS` 1行目、`r"(^|[^<>])>{1,2}\s*(?!&)\S"`）が、`grep -n -A 5 "doing→review attempt=<n>" .claude/skills/run/SKILL.md`（`.claude/skills/run/SKILL.md` 39行目に実在する文言）のような、山括弧プレースホルダー（`<n>`・`<計画ID>` 等）を含むだけの読み取り専用コマンドを、`<n>` の `n>` 部分をリダイレクトと誤認して拒否してしまう不具合を直す。

再現は本計画作成時に planner 自身のセッションでも確認済み：`echo 'doing→review attempt=<n>' > /tmp/xxx.txt` のような、実際のリダイレクト（`>` 実体）とプレースホルダー（`<n>`）が同じコマンド文字列に混在するケースでは、`extract_bash_write_targets()` 等が `<n>` 側から誤ったダミーの書き込み対象（例えば直後の `"` や `'` 1文字）を抽出し、「全対象がリポジトリ外」「全対象が許可ディレクトリ配下」のどちらの許可条件も満たせなくなって fail-closed で deny される。誤検知は `>` 単体のパターンマッチだけでなく、その後段の書き込み対象抽出ロジックにも及ぶ。

`vault/verdicts/` 以外に書き込めない verifier がこの誤検知で確認コマンドを実行できず、Read での目視確認という代替手段に頼らざるを得なかった（`P-20260925-run-commit-before-worktree` の T-01 検証時）。

修正は `.claude/hooks/agent_write_guard.py` のロジック変更に閉じ、実際のリダイレクト（`> file`・`>> file`）や `rm`/`git commit` 等の既存の破壊的操作検出能力は維持する。再発防止のため `scripts/smoke.sh` に回帰テストケースを追加する。

## 分割方針

対象は同一ファイル（`.claude/hooks/agent_write_guard.py`）内の正規表現・抽出ロジックの修正1点と、密結合する回帰テスト（`scripts/smoke.sh`）の追加のみで、成果物が2ファイルに閉じる小さいバグ修正。契約タスクと実装タスクを分ける規模ではない。同種の過去のバグ修正（`P-20260924-write-guard-nested-dir`／issue #24、`P-20260924-gh-api-write-guard`／issue #6）もいずれも「フック本体の修正＋`scripts/smoke.sh` への回帰ケース追加」を1タスクにまとめており、それに倣う。1タスク（T-01）のみで構成する。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | agent_write_guard: 山括弧プレースホルダー内の `>` をリダイレクト誤検知から除外する（issue #54） | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（`after` は `-` のみ）
- 1タスクが1コンテキストで終わる粒度である
- 誤検知の解消（山括弧プレースホルダーを含む読み取り専用コマンドが許可される）と、既存の破壊的操作検出能力の維持（実際のリダイレクト・`rm`・`git commit` 等は引き続き拒否される）の両方が受け入れ基準に含まれている

## 人への質問
（なし）
