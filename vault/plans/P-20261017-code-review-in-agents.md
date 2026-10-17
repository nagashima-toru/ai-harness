---
id: P-20261017-code-review-in-agents
status: approved
---
# ゴール
GitHub Issue #214（nagashima-toru/ai-harness）「creator・verifier から /code-review を使えるようにし、差分の外の指摘を判定から外す」を解決する。

- `.claude/agents/creator.md`・`.claude/agents/verifier.md` の tools に `Skill` を足し、Claude Code 組み込みの `/code-review`（Skill の `code-review`）を呼べるようにする
- verifier に、受け入れ基準がコードレビューを参照する時の判定方法を、ドメインに依らない一般の規則として書く（対象はそのタスクの差分・worktree のパスを明示して呼ぶ・差分で変えた行への致命的な指摘が残れば FAIL・差分の外の指摘は FAIL の根拠にしない・設計や仕様の変更が要る指摘は人に渡す）
- creator に、受け入れ基準がコードレビューを参照する時は、完了報告の前に同じ範囲で `/code-review` を実行し、差分内の致命的な指摘を直してから返すことを書く
- どのタスクにレビューを求めるかは導入先の planner ルールで決める。ハーネス本体はレビューを強制しない（`docs/vision.md` 原則7）

## 分割方針
- 規則の正本はエージェント定義（verifier・creator）に置き、仕様書（`docs/vault-spec.md`）はそれを要約して参照する。全タスクで同じ固定の語句（起動文言・致命的の定義・reasons の接頭辞2つ・blocked の補足）を使うため、各タスク票の「決定済み」に同じ文言を写してある
- T-01（verifier）と T-02（creator）は互いに独立。T-03（run）は verifier が書く接頭辞 `人の判断が必要:` を受けて PASS を blocked に回す手順で、T-01 の後に置く
- T-04（smoke）は T-01・T-02 で足した `Skill` が tools から消えたら止める検査で、両方の後に置く（先に入れると smoke が落ちる）
- T-05（仕様書）は T-01〜T-03 の実ファイルの文言に合わせるためその後に置き、T-06（`docs/decisions.md` への判断の記録）は仕様書の後に置く（成果物を1タスク1つにするため分けた）
- 「設計・仕様の変更が要る指摘を blocked で人に渡す」は、verifier に blocked にする権限が無い（状態はオーケストレーターだけが変える）ため、verifier が reasons に接頭辞 `人の判断が必要:` の要素を書き、run が PASS の時にそれを見て done の代わりに review→blocked にする形にした（T-03）。review→blocked は `scripts/transition.py` の既存の遷移で、スクリプトの変更は要らない
- `scripts/install.sh` は `.claude/agents/` の3本を既に配っており（`CLAUDE_FILES`）、`.claude/settings.json` の `permissions.allow` には `Skill` が既にあるため、どちらも変えない
- `.claude/agents/planner.md` は変えない（どのタスクにレビューを求めるかは導入先の planner ルールで決める。書き方の既定は仕様書（T-05）に置き、planner は仕様書を読む）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | verifier の tools に Skill を足し、コードレビューを参照する基準の判定規則を書く | |
| T-02 | doing | 1 | - | creator の tools に Skill を足し、完了前のコードレビューの手順を書く | |
| T-03 | todo | 0 | T-01 | run の手順6で、人の判断を求める PASS の verdict を blocked に回す | |
| T-04 | todo | 0 | T-01,T-02 | smoke に creator・verifier の tools の Skill の検査を足す | |
| T-05 | todo | 0 | T-01,T-02,T-03 | vault-spec にコードレビューを参照する基準の仕様を書く | |
| T-06 | todo | 0 | T-05 | decisions にコードレビューを参照する基準の判断を記録する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補（票は起こさない）
- Issue #214 の「確認したいこと」（`/code-review` の実行コストがタスクごと・attempt ごとに見合うか、`effort` と `--max-findings` の既定値）は、導入先で運用した結果を見て別 Issue で決める。この計画ではハーネス本体に既定値を置かず、受け入れ基準の行に引数が書かれていればそれを使う形にとどめる
