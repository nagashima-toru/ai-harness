---
id: P-20261009-stale-docs-refcheck
status: approved
---
# ゴール
古い記述の修正と参照切れの検査（D-013 フェーズ7）

今の仕様と合わなくなった記述を直す。

- `.claude/skills/design/SKILL.md`：廃止した `vault/todo.md` への言及、存在しない「第14節」
- `.claude/ai-harness.md`：`/run` の説明、役割の節、開始時に読む順
- `README.md`：`/run` の説明、構成の節
- `.claude/skills/run/SKILL.md`：frontmatter の description

あわせて、`scripts/smoke.sh` に参照切れの検査を足す。主な文書の中にバッククォートで書かれたリポジトリ相対パスが、すべて存在することを確かめる検査。

正本は `vault/designs/D-013.md` の「フェーズ7 古い記述の修正と参照切れの検査」（ゴール文・受け入れ基準の候補・決定済み・依存）。文書の書き換えは、今の `.claude/skills/run/SKILL.md`・`docs/vault-spec.md` を正として合わせる。`docs/decisions.md` は対象外（直さず、検査もしない）。

## 分割方針
- 成果物（ファイル）ごとに1タスクにする。同じファイルを2つのタスクで変えない
  - T-01：`.claude/skills/design/SKILL.md`。`vault/todo.md` の2か所と「第14節」を直す（設計文書の仕様は `docs/vault-spec.md` の13節「設計文書（`vault/designs/`）」）
  - T-02：`.claude/ai-harness.md`。開始時に読む順・役割の節・スキルの節の `/run` の説明を、今の run（オーケストレーター＋creator/verifier サブエージェント＋transition.py）に合わせる
  - T-03：`README.md`。使い方の表の `/run`・無人実行の説明、仕組みの図の「作成エージェント（メイン）」、構成の節（agents の3つと主なスクリプト）を直す
  - T-04：`.claude/skills/run/SKILL.md` の frontmatter の description だけを直す（本文は変えない）
  - T-05：`scripts/smoke.sh` に参照切れの検査とそのケース `(ref-1)`〜`(ref-4)` を足す
- 依存：T-01〜T-04 は互いに独立で並行できる。T-05 は T-01〜T-04 の後（文書を直してからでないと、今の文書に対する検査 `(ref-1)` が `vault/todo.md` で落ちる。T-02〜T-04 で書き足すパスも検査の対象になる）
- 計画作成時の調査（このブランチの作業ツリー。T-05 と同じ規則で、対象の文書のバッククォート内のパスのうち存在しないものを列挙した）：
  - `vault/todo.md`（`.claude/skills/design/SKILL.md` の2か所。T-01 で消す）
  - 例として挙げているだけのもの：`vault/designs/D-xxx.md`（README・runbook・design/SKILL.md・planner.md）、`vault/rules/common/naming.md`（README）、`vault/rules/...`（vault-spec）、`vault/rules/x.md`（runbook）
  - ほかの環境にしか無いもの：`.claude/projects`（vault-spec・runbook・planner.md。`~/.claude/projects/` の略記）、`.claude/harness-manifest.json`・`.claude/settings.local.json`（install.md。導入先・各人の環境にできるファイル）
  - これらを T-05 の除外（`vault/rules/` で始まるものは前方一致で除外、ほかは除外リスト）に入れる。`vault/todo.md` は除外しない
- `scripts/smoke.sh` は導入先にも配られるが、導入先には `README.md`・`docs/runbook.md`・`docs/install.md` が無く、`docs/vault-spec.md` などが指す `docs/runbook.md` も無い。そのため参照切れの検査は、導入先（`.claude/harness-manifest.json` があるリポジトリ）では行わない（T-05 の決定済み）
- `.claude/` の下のファイル（T-01・T-02・T-04）の編集が拒否された時は、別の手段で書き換えず、拒否の理由を question に書いて `blocked` にする（各票の決定済み）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | design/SKILL.md の vault/todo.md と第14節を、vault/plans/ と vault-spec.md 13節に直す | |
| T-02 | todo | 0 | - | ai-harness.md の開始時に読む順・役割・/run の説明を今の run に合わせる |  |
| T-03 | done | 1 | - | README.md の /run と無人実行の説明・仕組みの図・構成の節を今の構成に合わせる | |
| T-04 | blocked | 1 | - | run/SKILL.md の frontmatter の description を今の手順に合わせる | .claude/skills/run/SKILL.md への Edit（3行目の description と7行目の2か所）が、権限判定（auto mode classifier、理由 Self-Modification）に拒否された。タスク票の決定済みどおり、別の手段では書き換えていない。成果物は未変更。この変更を許可して再実行するか、人が手で反映するか。 |
| T-05 | todo | 0 | T-01,T-02,T-03,T-04 | smoke.sh に主な文書の参照切れの検査を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `grep -rn "vault/todo.md" .claude/skills .claude/agents .claude/ai-harness.md README.md docs/vault-spec.md docs/runbook.md docs/install.md` の出力が空
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含み、`(ref-1)`〜`(ref-4)` の4件が ok になる
- `docs/decisions.md` が変わっていない（どのタスクの「成果物」にも宣言していないので、差分ゲートで確認される）

## 人への質問
1. （回答済み：直す。T-04 に反映した）
2. （回答済み：直す。T-02 に反映した）
