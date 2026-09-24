---
id: P-20260925-scripts-search-distribution
status: approved
---
# ゴール
`scripts/install.sh` の `scripts/` 配布を、ファイル名の列挙から `scripts/*.sh`・`scripts/*.py` の検索方式に変える（`manifest_paths()` とマニフェストの対象、通常の複製 `copy_if_absent` の呼び出しの両方）。配らないスクリプトは install.sh 内の除外リスト（当面は空）で明示できるようにする。これにより現在配られていない `scripts/vcs_finish.sh` も配られるようになる。あわせて `scripts/smoke.sh` に、新規インストール先で導入先のスキル等（`.claude/`・`vault/rules/`・`vault/templates/`・`docs/vault-spec.md`・`CLAUDE.md`）に書かれた `scripts/<名前>` がすべて存在することを確かめるケースを足し、同じ種類の配布漏れを機械的に検出できるようにする。`scripts/install.sh` 冒頭の「複製するもの」コメントと `docs/install.md` の配布物の説明も実態に合わせる。設計文書 `vault/designs/D-007.md` のフェーズ1に対応する。

## 分割方針
- T-01（install.sh 本体）を先に切る。`manifest_paths()` と通常複製のロジック変更、除外リスト変数の追加、冒頭コメントの更新をまとめて1つの成果物（`scripts/install.sh`）にする。以後のタスクはこの変更が入っていることを前提にできる
- T-02（smoke.sh の参照チェック）は T-01 の後に着手する。検索方式に変わった `install.sh` を実際にインストールして、新しく配られる `vcs_finish.sh` を含めた参照整合性を確認するケースなので、実装が先に必要
- T-03（docs/install.md の記述更新）は文面の書き換えだけで、決定済みの表現がすでに確定しているため、実装の完了を待たずに独立して進められる。`after` は付けない
- フェーズ2（`worktree.baseRef` のマージ、`scripts/merge_settings_json.py` 関連）は別計画で扱う。今回のタスク一覧には含めない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | install.sh の scripts 配布を検索方式にする | |
| T-02 | todo | 0 | T-01 | smoke.sh に参照される scripts の存在チェックを追加する | |
| T-03 | review | 1 | - | docs/install.md の配布物説明を実態に合わせる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
