---
id: P-20261010-vision-local-only
status: approved
---
# ゴール
docs/vision.md を、このリポジトリ（ai-harness 本体）で動くエージェントだけが意識するようにする。導入先には配らない。vision の本文は二重持ちしない（docs/vision.md が唯一の正本で、写し・要約を他に書かない）。

人と合意済みの方式：
1. `vault/rules/common/vision.md` を `../../../docs/vision.md` へのシンボリックリンク（git でシンボリックリンクとして追跡）として作り、`scripts/rules.sh` 経由で creator・verifier・planner が読む。`scripts/install.sh` は `vault/rules/` 配下を README と .gitkeep しか配らないので導入先には届かない
2. このリポジトリの `CLAUDE.md` のマーカーブロックの外（後ろ）に `@docs/vision.md` を1行足し、メインセッションが読む
3. `scripts/merge_claude_md.py` を、src からマーカーブロックだけを抜き出して使うよう直し、マーカーの外の行が導入先に配られないようにする

## 分割方針
- 配布の経路を先に塞いでから、配りたくない行を足す。T-01（merge_claude_md.py）→ T-02（install.sh の `--no-claude-md` の新規作成経路。ここは merge_claude_md.py を通らず `CLAUDE.md` 全体を `cp` している）→ T-03（`CLAUDE.md` への追記）の順にする
- T-01・T-02 の smoke の検査は、`$ROOT/CLAUDE.md` に `@docs/vision.md` が無い間は自明に通るものも含む。T-03 で行を足した時点で意味を持ち、T-03 の受け入れ基準で全部 ok であることを確かめる
- シンボリックリンク（T-04）は配布の経路と独立だが、導入先に届かないことを T-02 の smoke（`(in-out)`）で確かめるため、T-02 の後にする
- 説明文書（`docs/install.md`・`README.md`）は挙動が決まった後に T-05 でまとめて合わせる。`README.md` の「`CLAUDE.md` は4行ブロックだけを持つ」という記述は T-03 の後に事実と食い違うため、T-03 の後にする
- `scripts/smoke.sh` は T-01 と T-02 の両方が変えるが、`after` で直列にしているので衝突しない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | merge_claude_md.py が src からマーカーブロックだけを抜き出して使う | |
| T-02 | todo | 0 | T-01 | install.sh の --no-claude-md の新規作成でもマーカーブロックだけを置く | |
| T-03 | todo | 0 | T-01,T-02 | CLAUDE.md のマーカーの外に @docs/vision.md を足す | |
| T-04 | todo | 0 | T-02 | vault/rules/common/vision.md を docs/vision.md へのシンボリックリンクとして作る | |
| T-05 | todo | 0 | T-01,T-02,T-03 | docs/install.md と README.md の CLAUDE.md の配布の説明を合わせる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 全タスクが done になった時点で、`bash scripts/smoke.sh 2>&1 | grep -c '^  NG '` が `0`
