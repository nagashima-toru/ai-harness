---
id: P-20260926-design-closes-keyword
status: approved
---
# ゴール

GitHub issue #15 への対応。`/design` スキル（`.claude/skills/design/SKILL.md`）の手順8（PR/MR を作って提示し、止まる）に、PR/MR 本文で issue 番号に触れる際は `Closes #N`・`Fixes #N`・`Resolves #N` などの自動クローズキーワードを使わず、`Relates to #N` 等の非クローズキーワードを使う旨の指示を追記する。

背景：`/design` が作る PR は設計文書（`vault/designs/D-xxx.md`）のみで、issue の実装は後続の `/plan` → `/run` が複数フェーズに分けて進める。実例として issue #9 は、設計 PR #11（`Closes #9` を含む本文）のマージ時点、つまり実装着手前に GitHub によって自動クローズされてしまった。実際にフェーズ1〜3が完了したのはその後の PR #12・#13・#14。

対応方針は issue #15 の「対応案」に決定済みとして明記されている（人による追加判断は不要）。
- `/design` が作る PR 本文では `Closes #N` ではなく `Relates to #N` 等の非クローズキーワードを使う
- 実際に issue を閉じるのは、最終フェーズの `/plan` → `/run` が生成する PR（全フェーズ完了時点）にする（この計画のスコープ外。`/design` 側の記述変更のみを扱う）

補足：現状の `.claude/skills/design/SKILL.md` 本文には `Closes #N` という文字列自体は存在しない（issue #9 でその文言を書いたのは過去のセッションの判断であり、SKILL.md に明文化された指示ではなかった）。そのため本タスクは既存の `Closes #N` という文字列を単純に置換するのではなく、手順8に「非クローズキーワードを使う」旨の指示を新規に追記する作業になる。

## 分割方針

対象ファイルは `.claude/skills/design/SKILL.md` 1本、変更点も「手順8に非クローズキーワード運用の指示を1箇所追記する」という単一の小さな変更なので、T-01 の1タスクで完結させる（分割不要）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | design/SKILL.md 手順8に PR 本文の非クローズキーワード運用を追記する（issue #15） | |

## 計画の受け入れ基準
- タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（`after` は `-` のみ）
- 1タスクが1コンテキストで終わる粒度である
