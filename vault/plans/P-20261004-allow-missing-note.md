---
id: P-20261004-allow-missing-note
status: approved
---
# ゴール
install.sh 実行時、導入先の `.claude/settings.json` の `permissions.allow` に、ハーネスが動くのに必要な許可（ハーネス側 `.claude/settings.json` の `permissions.allow`）のうち足りないものがあれば、`scripts/merge_settings_json.py` が `note` 行で案内する。`permissions.allow` 自体は従来どおり一切変更しない。`docs/install.md` にもこの挙動と、許可が入らない場合の影響（対話実行では確認ダイアログ、無人実行（`claude -p`）では拒否される）を書く。

背景：`merge_settings_json.py` は hooks・`permissions.deny`・`worktree.baseRef` だけをマージし、`permissions.allow` は触らない。導入先に settings.json が既にあると、ハーネスの許可リストが入らず、利用者の個人設定に依存してしまう。人の判断で「allow は変えず、不足を note 行で知らせる」方針に決まった。

## 分割方針
- 現状（planner が読み取り専用で確認した事実。2026-10-04 時点）
  - `scripts/merge_settings_json.py` の note 行は `worktree_base_ref_note` の1種類だけで、`create`/`merge`/`skip` の行より前に出している。`permissions.allow` は docstring で「読み取るだけで一切変更しない」と明記している
  - `scripts/install.sh` は `--update` の有無・既存の有無にかかわらず `merge_settings_json.py` を常に呼び、出力をそのまま流す（install.sh 側の変更は不要）
  - `scripts/smoke.sh` の `== merge_settings_json.py ==` 節に (m)(n)(v)(w)(x) のケースがあり、`$STMP`（`mktemp -d`）を使う。ラベル `(al-` は未使用
  - `docs/install.md` の142行目（「ハーネスを更新する」節の箇条書き）に settings.json のマージ内容の説明がある。`docs/vault-spec.md` には merge_settings_json.py の記述が無いので変更しない
- タスクの分け方：T-01 でスクリプト本体（不足判定と note 行）、T-02 で smoke.sh のテスト、T-03 で docs/install.md。T-03 は note 行の実際の文言に合わせるため T-01 の後にする
- note 行の文言・判定方法は T-01 の「決定済み」で固定し、T-02・T-03 はそれを参照する

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | merge_settings_json.py に permissions.allow の不足を note 行で案内する処理を足す | |
| T-02 | review | 1 | T-01 | smoke.sh に permissions.allow 不足案内のケースを足す | |
| T-03 | review | 1 | T-01 | docs/install.md に permissions.allow 不足案内の挙動と影響・限界を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わる
