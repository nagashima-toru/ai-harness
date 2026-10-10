---
id: P-20261010-design-id-cleanup
status: approved
---
# ゴール
D-016 フェーズ3：設計文書の ID を `D-<YYYYMMDD>-<スラッグ>`（ブランチ `design/d-<YYYYMMDD>-<スラッグ>`）に変え、`/design` が最終フェーズの受け入れ基準に「決定事項のうち docs に無いものを `docs/decisions.md` に追記し、設計文書を削除する」を必ず入れるようにする。`docs/vault-spec.md` 13節・`.claude/skills/design/SKILL.md`・`vault/templates/design.md`・smoke を合わせて直す。あわせて既存の設計文書 `vault/designs/D-001.md`〜`D-016.md` を、D-016 の決定事項を `docs/decisions.md` に追記したうえで全部削除する。

## 分割方針
- 仕様（T-01：`docs/vault-spec.md`）、スキルとテンプレート（T-02）、旧形式を参照するほかの文書（T-03：README・runbook・planner 定義・run スキル）、smoke（T-04）、判断の記録（T-05：`docs/decisions.md`）、設計文書の削除（T-06）に分ける
- T-01・T-02・T-03・T-05 は互いに別のファイルを変えるので並行できる
- T-04 は smoke の参照切れ検査（refcheck）の除外リストから `vault/designs/D-xxx.md` を外すので、文書から `D-xxx.md` の参照が消える T-02・T-03 の後に置く。新しく足す smoke の検査も T-02 の文言を読む
- T-06（削除）は最後。D-016 を読む T-05 の後でなければならず、また `docs/vault-spec.md` に `vault/designs/D-001.md` の参照が残ったまま消すと smoke の (ref-1) が落ちるので T-01 の後に置く。全体の旧形式の残りの検査もここで行うため、T-01〜T-05 の全部に依存させる
- 各タスク票の「決定済み」に D-016 の決定事項を必要なだけ転記してある（D-016 の削除後も実行できるように）
- フック・スクリプト（`.claude/hooks/`・`scripts/` の smoke 以外）は設計文書の ID の形式に依存していない（`designs/` は install.sh・uninstall.sh のディレクトリ名だけ、`vcs_finish.sh` はブランチ名を見ない）ので、タスクにしない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | vault-spec の設計文書 ID・ブランチ名・最終フェーズでの削除を新方式にする | |
| T-02 | doing | 1 | - | /design スキルとテンプレートを新しい ID と最終フェーズの削除に合わせる | |
| T-03 | review | 1 | - | README・runbook・planner 定義・run スキルの旧形式の設計文書 ID を直す | |
| T-04 | todo | 0 | T-02,T-03 | smoke の設計文書 ID の例を新形式にし、/design の記述の検査を足す | |
| T-05 | todo | 0 | - | D-016 の決定事項を docs/decisions.md に追記する | |
| T-06 | todo | 0 | T-01,T-02,T-03,T-04,T-05 | 既存の設計文書 D-001〜D-016 を削除する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 全タスクの完了後、`grep -rnE --exclude=decisions.md --exclude-dir=worktrees 'D-xxx|d-xxx|vault/designs/D-[0-9]{3}|design/d-[0-9]{3}|最大値 ?\+1|\+ 3桁|^id: D-[0-9]{3}$' README.md docs .claude scripts vault/templates vault/rules` が何も出さず、`ls -A vault/designs` が `.gitkeep` だけを出し、`bash scripts/smoke.sh` が全部通る
