---
id: P-20260925-worktree-baseref-merge
status: approved
---
# ゴール
`scripts/merge_settings_json.py` に、ハーネス側 settings.json の `worktree.baseRef` を導入先にマージする処理を足す。導入先に `worktree.baseRef` が無ければハーネス側の値（`"head"`）を足してマージ扱いにする。同じ値が既にあれば何もしない。別の値が入っていれば上書きせず、標準出力に `note` 行で「`worktree.baseRef` が `<値>` のため `run` の worktree が計画ブランチから分岐せず blocked になる。`"head"` にすること」という趣旨の案内を出す。`scripts/unmerge_settings_json.py` は変更しない（`worktree.baseRef` は uninstall で残す）。`scripts/smoke.sh` にこの3通りのケースを足し、`docs/install.md` の settings.json の説明（109行目・142行目・164行目付近）と `scripts/install.sh` 冒頭コメントを更新する。

## 分割方針
D-007 フェーズ2の受け入れ基準の候補を、契約寄りの実装タスク（T-01）と、それに依存する2つのタスク（T-02: smoke.sh のケース追加、T-03: ドキュメント更新）に分けた。T-02・T-03 は互いに独立で、どちらも T-01 の実装（`worktree.baseRef` マージ処理と出力形式）が固まらないと正しい内容を書けないため `after: T-01` とした。T-02・T-03 は `after` で依存し合わないため、着手可能集合として並行できる。
`scripts/unmerge_settings_json.py` は変更しないことが決定済みのため、これを変更しないことの確認は T-01 の受け入れ基準に含めた（uninstall 時に `worktree.baseRef` が残る、という決定を裏付ける確認）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | merge_settings_json.py に worktree.baseRef のマージ処理を足す | |
| T-02 | todo | 0 | T-01 | smoke.sh に worktree.baseRef の3ケースを足す | |
| T-03 | todo | 0 | T-01 | docs/install.md と install.sh 冒頭コメントを worktree.baseRef の扱いに合わせて更新する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 全タスク done 後、`bash scripts/smoke.sh | tail -1` が `fail=0` で終わる
