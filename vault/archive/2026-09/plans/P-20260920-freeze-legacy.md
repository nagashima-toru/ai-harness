---
id: P-20260920-freeze-legacy
status: done
---
# ゴール
既存資産（17計画・29タスク票・29 verdict・`vault/log/queue.md`・`vault/todo.md`）を `vault/archive/2026-09/` に移し、
`vault/todo.md` を削除して新方式への切り替えを完了する。`scripts/install.sh` の複製対象とマニフェストを
新構造に合わせ、`README.md`・`docs/runbook.md`・`docs/install.md`・`.claude/ai-harness.md`（CLAUDE.md か
ら読み込まれる本文）・`docs/decisions.md` を新方式で書き直す。`vault/designs/D-001.md` フェーズ4に対応
する（設計文書の再検討は行わない）。

## 分割方針
実ファイルを調べたところ、`決定済み`（人が確定済み）にある「旧 ID（`P-001`〜`P-017`、`T-0001`〜
`T-0029`）」という指定と、計画/タスク/verdict の実数（`status: done` の計画が P-001〜P-017 の17件、
タスク票と verdict がそれぞれ T-0001〜T-0029 の29件）が完全に一致した。よってアーカイブ対象は
「P-001〜P-017（計画17件）・T-0001〜T-0029（タスク票29件・verdict 29件）」に確定する（P-019・P-020は
done だが D-001 自身の移行フェーズ1・2の記録であり対象外、P-021 は現行の approved 計画）。この件は念
のため「人への質問」に確認事項として残す。

まず T-01 でアーカイブと破棄（ファイル移動・削除）を行い、リポジトリの実ファイル構成を新方式に揃え
る契約タスクとする。以降のドキュメント系タスクはこの実ファイル構成を前提に書けるため、T-02〜T-05は
すべて T-01 の後に置く。

`scripts/install.sh`（T-02）は複製・生成物の仕様そのものを変えるので、それを参照する `.claude/
ai-harness.md`（T-03）・利用者向けドキュメント（T-04, T-05）より先に固める。`.claude/ai-harness.md`
はエージェントの规律本文でありREADME/runbookより先に確定させたいのでT-03を先に置く。README.md と
docs/install.md はどちらも「install.sh が何を複製・生成するか」を説明する対（T-04）。docs/runbook.md
と docs/decisions.md は「人が日々やること」と「決定ログ」の対で、最後に全体の通し確認を兼ねる（T-05）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | 旧資産をアーカイブし vault/todo.md 等を廃止する | |
| T-02 | done | 1 | T-01 | scripts/install.sh を新構造に合わせて改訂する | |
| T-03 | done | 1 | T-02 | .claude/ai-harness.md を新方式に書き直す | |
| T-04 | done | 1 | T-02,T-03 | README.md・docs/install.md を新方式に更新する | |
| T-05 | done | 1 | T-04 | docs/runbook.md・docs/decisions.md を新方式に更新し通し確認する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01 → T-02 → T-03 → T-04 → T-05 の一本鎖）
- 1タスクが1コンテキストで終わる粒度である
- 全タスク完了後、`bash scripts/smoke.sh | tail -1` に `fail=0` が含まれる
- `grep -rc 'vault/todo.md' README.md docs/runbook.md docs/install.md .claude/ai-harness.md scripts/install.sh` がすべて0

## 人への質問
- **アーカイブ対象の範囲の確認。** ゴール本文の「読むべきファイル」節は `vault/plans/P-001.md〜
  P-020.md（旧資産）` と書いており P-019・P-020 を含む読み方もできるが、「決定済み」節は「旧 ID
  （`P-001`〜`P-017`、`T-0001`〜`T-0029`）はアーカイブ内でそのまま残す」と明記しており、これは実際の
  計画17件・タスク票/verdict各29件という実ファイル数（`status: done` の P-001〜P-017、T-0001〜
  T-0029）と完全に一致する。この計画では**P-001〜P-017・T-0001〜T-0029のみをアーカイブし、P-019・
  P-020（D-001自身のフェーズ1・2の記録。done だが直近）はアーカイブしない**という解釈で進める。異な
  る意図であれば承認前に指摘してほしい。
- **「`/plan` から `/run` までの1周が通る」の確認方法。** 候補の受け入れ基準にある文言だが、実際に
  `claude -p` を起動して確認するのはコストとリスクが伴い、かつ `/plan`・`/run` 自体のロジックは前フ
  ェーズ（P-021）で既に検証済みでこの計画では変更しない。そのため T-05 の受け入れ基準では「一時ディ
  レクトリへ install して `bash scripts/smoke.sh` が `fail=0`」までを機械確認の対象にし、実際に
  `claude -p` で1周させる確認は人が最終確認する運用とした。自動検証まで必要であれば承認前に指摘して
  ほしい。
