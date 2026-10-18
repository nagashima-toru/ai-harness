---
id: P-20261018-push-and-run-hardening
status: approved
---
# ゴール
GitHub Issue #217・#207・#211（nagashima-toru/ai-harness）をまとめて解決する。(1) `scripts/vcs_finish.sh` の `do_push` が、`HARNESS_PUSH_BRANCH` が無く上流が設定済みの時にも毎回現在のブランチを push するようにし、smoke に「上流があり先行している時も push される」検査を足す（#217）。(2) `.claude/skills/run/SKILL.md` に、creator・verifier の Agent 呼び出しがエラーで即時に返った時の節を足す（#207）。(3) `.claude/agents/planner.md` の grep パターンの特殊文字の箇条とセルフチェックに `#` を足す（#211）。

## 分割方針
- Issue ごとに1タスク（T-01 = #217、T-02 = #207、T-03 = #211）。3つは互いに依存せず、並行に進められる（`after` は `-`）
- T-01 と T-02 はどちらも `docs/vault-spec.md` を変えるが、T-01 は1節の `HARNESS_PUSH_BRANCH` の段落、T-02 は7節の遷移行の補足の段落で、離れた行なので `git merge --no-ff` で衝突しない想定
- T-01 は `scripts/vcs_finish.sh`・`scripts/smoke.sh` を変えるコードを変更するタスクなので、全タスクの後に計画単位のレビュータスク T-04 を足す（T-02・T-03 は `.md` だけの変更）
- T-01 で上流があっても push するようになると、smoke の既存の vcs_finish の検査（origin が `https://github.com/o/r.git` で上流を `.` にして push を避けていたもの）が実際に push しようとして失敗するため、T-01 の中でそれらのフィクスチャの push 先をローカルの bare に向ける

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | vcs_finish.sh が上流の有無に関係なく毎回現在のブランチを push する | |
| T-02 | review | 1 | - | run SKILL に Agent 呼び出しがエラーで返った時の節がある | |
| T-03 | doing | 1 | - | planner.md の grep パターンの特殊文字の列挙に # がある | |
| T-04 | todo | 0 | T-01,T-02,T-03 | 計画の差分が `/code-review` を通過する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
