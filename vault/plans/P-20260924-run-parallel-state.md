---
id: P-20260924-run-parallel-state
status: approved
---
# ゴール
D-003（`vault/designs/D-003.md`）フェーズ1「状態遷移ルールの緩和とフックの整合性検査更新」を実施する。`.claude/ai-harness.md` と `docs/vault-spec.md` の状態遷移の記述を、「`doing` は計画内で常に1件だけ」から「`doing`/`review` は複数件になりうるが、その全ては `after` 依存の無い集合（着手可能集合）に限り、計画票・ログへの書き込みは常にオーケストレーター1プロセスに集約する」に書き換える。`.claude/hooks/plan_guard.py` の「doing が2件以上ならブロック」判定を「doing/review の集合内に `after` 依存関係が張られていたらブロック」判定に置き換え、`.claude/hooks/stop_gate.py` の「doing/review のタスクは1件だけ想定」というロジック（`next(...)` で1件だけ取り出す部分）を、doing/review の全行をそれぞれ検査するループに変更する。`run` スキル自体（`run/SKILL.md`）はこのフェーズでは変更しない。実際に複数タスクを同時に doing にする機能はフェーズ3で入れる。

## 分割方針
- 「ドキュメント（`.claude/ai-harness.md` + `docs/vault-spec.md`）の書き換え」「`plan_guard.py` の判定変更」「`stop_gate.py` の判定変更」は、互いの出力を入力にしない独立した成果物なので、3タスクとも `after: -` にして並行着手できるようにする（このフェーズ自体が issue #9 の並行実行機能の先行実装であるため）。
- `plan_guard.py`・`stop_gate.py` の各タスクは、実装コードと対応する `scripts/smoke.sh` のケース更新をセットにする。テストケースを直さないとロジック変更の正しさを確認できないため密結合であり、`P-20260924-gh-api-write-guard`/T-01 の前例（実装+smoke.sh を1タスクにまとめる）に倣う。
- ドキュメントタスクは `.claude/ai-harness.md` と `docs/vault-spec.md` の2ファイルにまたがるが、同一の文言変更（状態遷移の許容範囲の書き換え）を両ファイルに反映するだけの1PRとして扱う（粒度基準の「1ファイル/1PR/1関数」の1PRに該当）。
- 依存関係の判定方式（doing/review の `after` 列に、まだ `done` でない他の doing/review 行の id が含まれるかで見る。doing 同士の相互依存も検出する）は D-003 フェーズ1の「決定済み」をそのまま引き継ぐ。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | 状態遷移ルールの記述を ai-harness.md と vault-spec.md で書き換える | |
| T-02 | doing | 1 | - | plan_guard.py の doing 判定を after 依存検査に置き換える | |
| T-03 | todo | 0 | - | stop_gate.py の doing/review 検査を全行ループに変更する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh` を実行すると fail=0 になる（3タスク完了後の統合確認。コマンド: `bash scripts/smoke.sh | tail -1`）
