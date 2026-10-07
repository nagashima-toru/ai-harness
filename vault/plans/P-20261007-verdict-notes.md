---
id: P-20261007-verdict-notes
status: approved
---
# ゴール
verifier の指摘を見えるようにする（D-013 フェーズ2）

1つの計画の verdict の `reasons` を一覧にする `scripts/verdict_notes.py <計画ID>` を新設する。run の手順7（全タスクが done になった後）で、その出力を完了報告に含め、PR 本文にも入れる。そのために `scripts/vcs_finish.sh` に、環境変数 `HARNESS_PR_BODY_FILE`（本文のファイル）と `HARNESS_PR_TITLE` を受け取る経路を足す。あわせて、`scripts/model_stats.py` に、最後の verdict の `reasons` が空でないタスクの割合の列 `noted_rate` を足す。

正本は `vault/designs/D-013.md` の「フェーズ2 verifier の指摘を見えるようにする」（ゴール文・受け入れ基準の候補・決定済み）。verifier の定義とルール（`.claude/agents/verifier.md`、`vault/rules/`）は変えない。

## 分割方針
- コードの変更3つ（verdict_notes.py の新設・vcs_finish.sh・model_stats.py）と文書の変更2つ（run/SKILL.md の手順7・docs/vault-spec.md）に分け、1タスク1つの主な成果物にする（smoke のケースは付随ファイル）
  - T-01：`scripts/verdict_notes.py` の新設と smoke のケース
  - T-02：`scripts/vcs_finish.sh` の `HARNESS_PR_BODY_FILE`・`HARNESS_PR_TITLE` の経路と smoke のケース
  - T-03：`scripts/model_stats.py` の `noted_rate` 列と smoke のケース（既存の (ms-1)・(ms-5) の期待値に列を足す）
  - T-04：`.claude/skills/run/SKILL.md` の手順7（T-01・T-02 の実装に合わせる）
  - T-05：`docs/vault-spec.md` の1節（vcs_finish の段落）・6節・7節（T-01〜T-03 の実装に合わせる）
- T-01・T-02・T-03 はどれも `scripts/smoke.sh` を変えるので直列にする（T-01 → T-02 → T-03）
- T-04 は T-01・T-02 の後（手順7が使うスクリプトと環境変数が先にあること）。T-05 は T-01・T-02・T-03 の後
- T-04（SKILL.md）と T-05（vault-spec.md）は別ファイルで、smoke も変えないので並行してよい。T-03 と T-04 も別ファイルなので並行してよい
- 各タスクは単体でマージしても smoke が `fail=0` で通る。文書のタスクは、先に入ったスクリプトの動きを書くだけにする
- smoke の件数は計画作成時点で `smoke: pass=658 fail=0`。T-01 で6件、T-02 で5件、T-03 で1件以上増える前提。受け入れ基準は件数ではなく `fail=0` とケース名で見る
- `scripts/pr_body.py` は変えない（run が本文のタスク一覧としてその出力を使う）。`.claude/agents/verifier.md`・`vault/rules/` は触らない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | verdict の reasons を一覧にする scripts/verdict_notes.py を新設する | |
| T-02 | done | 1 | T-01 | vcs_finish.sh に HARNESS_PR_BODY_FILE と HARNESS_PR_TITLE で本文とタイトルを渡す経路を足す | |
| T-03 | done | 1 | T-02 | model_stats.py の出力の末尾に noted_rate 列を足す | |
| T-04 | doing | 1 | T-01,T-02 | run/SKILL.md の手順7で verdict_notes.py の出力を PR 本文と完了報告に入れる | |
| T-05 | done | 1 | T-01,T-02,T-03 | docs/vault-spec.md の1節・6節・7節に verdict_notes.py・PR 本文の経路・noted_rate を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む
- `vault/rules/` と `.claude/agents/verifier.md` は変わっていない（`git status --porcelain -- vault/rules .claude/agents/verifier.md` が空）

## 次フェーズの候補
- D-013 フェーズ3（creator のモデルの切り替えと計測）。フェーズ2の後に始める

## 人への質問
計画は次の前提で書いた。違う場合は承認前に指示してほしい。
1. `HARNESS_PR_BODY_FILE` を使うと、`vcs_finish.sh` の今の既定の本文（`pr_body.py` のタスク履歴表）は使われなくなる。そこで run が作る本文の「タスク一覧（id と title）」には `python3 scripts/pr_body.py <計画ID>` の出力をそのまま使うことにした（計画 ID・id・title に加えて、commit・verdict の列も残り、スカッシュマージ後に辿れる性質を保てる）。id と title だけの表にしたい場合は指示してほしい
2. run は `HARNESS_PR_TITLE` に今の既定と同じ `<計画ID>: <ゴールの1行目>` を渡すことにした（PR のタイトルが今と変わらないように）。`HARNESS_PR_TITLE` が無い時のタイトルは、設計どおり計画 ID にする。計画が見つからないブランチ（`design/d-xxx` など）で `HARNESS_PR_BODY_FILE` だけが設定された時は、現在のブランチ名をタイトルにする
3. `verdict_notes.py --dir <ディレクトリ>` の `<ディレクトリ>` は、`<id>.json` を直接持つディレクトリ（例：`vault/archive/2026-10/verdicts/<計画ID>`）とした
4. `model_stats.py` に渡した log が `log` という名前のディレクトリの中に無い時（smoke の既存のフィクスチャのように一時ディレクトリの直下にある時）は、verdict の場所を決められないので、そのタスクは全部「指摘なし」として数える
