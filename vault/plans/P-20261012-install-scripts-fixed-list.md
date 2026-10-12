---
id: P-20261012-install-scripts-fixed-list
status: approved
---
# ゴール
GitHub Issue #201「install.sh の scripts/ 配布も検索方式のため、配布元の独自スクリプトが導入先に複製されマニフェストに載る」を解決する。

`scripts/install.sh` は `.claude/` 配下を固定リスト `CLAUDE_FILES` に限った（Issue #200・PR #202）が、`scripts/` 直下は今も `scripts_list()` が `find` で `scripts/*.sh`・`scripts/*.py` を列挙し、`SCRIPTS_EXCLUDE` だけを除いて配っている。導入済みリポジトリを配布元にすると、配布元が `scripts/` に置いた独自スクリプトが導入先に複製され、`.claude/harness-manifest.json` に記録されて `--update`・`uninstall.sh` の管理対象になる。

## 分割方針
- 推奨案（人への質問の1・2で確認する）で計画を書いた：`scripts/` 直下も install.sh 内の固定リスト `SCRIPTS_FILES` にし、smoke に (inst-only) と同様のケース `(inst-scr)` を足す。リストの更新漏れ（ハーネス本体にスクリプトを足したのに `SCRIPTS_FILES` に足し忘れる）は、ai-harness 本体で smoke を実行した時に検出する。
- T-01 は実装（`scripts/install.sh`）と、その動作を確かめる smoke のケース（`scripts/smoke.sh`）を1タスクにする。#200 の T-01 と同じ切り方で、smoke のケースは install.sh の変更の受け入れ確認そのものであり、分けると片方だけでは受け入れ基準を確かめられないため。
- T-02 は文書（`docs/install.md` の「複製されるもの」段落と「ハーネスを更新する」節、`docs/decisions.md` の判断の行）。T-01 の実ファイル（変数名・挙動）に合わせて書くので `after` を T-01 にする。古い記述（検索方式・`SCRIPTS_EXCLUDE`・`scripts_list`）が残っていないことのリポジトリ全体での確認も T-02 に置く。
- `scripts/uninstall.sh` はマニフェストの `files` だけを見て削除するため変更不要（install.sh がマニフェストに独自スクリプトを載せなくなれば、uninstall の対象からも外れる）。成果物にしない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | install.sh の scripts/ の複製とマニフェスト記録を固定リスト SCRIPTS_FILES に限り、smoke に (inst-scr) を足す | |
| T-02 | doing | 1 | T-01 | docs/install.md の scripts/ の配布の説明を固定リストに合わせ、decisions.md に判断を記録する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 導入済みリポジトリを配布元にして install・`--update` しても、配布元の `scripts/` 直下の独自スクリプトは導入先に複製されず、マニフェストにも載らない（smoke の `(inst-scr)` で確かめる）

## 人への質問（回答済み）
1. 方針：`scripts/` 直下も固定リストにするか、検索方式を維持して説明を残すか。**推奨：固定リスト `SCRIPTS_FILES` にする**（この計画はこの案で書いてある）。理由：`.claude/` と同じ問題（業務用の独自スクリプトが導入先に複製され、`--update`・`uninstall.sh` の管理対象になる）が残り、導入先の資産と本体の境界が `.claude/` と `scripts/` で食い違うため。代償はハーネス本体にスクリプトを足す時のリスト更新で、これは質問2の検出で補う。検索方式を維持する場合は、この計画を T-02 相当（docs への説明の追記）だけに作り直す。 → 回答：固定リスト `SCRIPTS_FILES` にする（推奨案）
2. リスト更新漏れの検出：固定リストにする場合、本体にスクリプトを足したのに `SCRIPTS_FILES` に足し忘れたことを smoke で検出するか。**推奨：検出する**（T-01 の `(inst-scr) 06`）。ただし導入先では利用者が `scripts/` に独自スクリプトを置くので、検出は `.claude/harness-manifest.json` が無いリポジトリ（＝ai-harness 本体）でだけ行い、導入先では省略する（ok と数える）。検出しない場合は T-01 の `(inst-scr) 06`・`07` と受け入れ基準の件数を外す。 → 回答：検出する（推奨案。`(inst-scr) 06`・`07` を入れる）
3. 配る範囲：`SCRIPTS_FILES` には、今 `scripts/` 直下にある `*.sh`・`*.py` の21本をすべて載せる（今の配布内容を変えない）。`run_unattended.py`・`model_stats.py`・`usage_stats.py`・`verdict_notes.py` のような補助スクリプトも今どおり配る想定でよいか。**推奨：21本すべて配る**（配る範囲を減らすのは Issue #201 の範囲外）。 → 回答：21本すべて配る（推奨案）
