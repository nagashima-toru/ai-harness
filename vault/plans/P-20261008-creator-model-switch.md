---
id: P-20261008-creator-model-switch
status: approved
---
# ゴール
creator のモデルを環境変数 HARNESS_CREATOR_MODEL で切り替えられるようにし、使用量を集計する（D-013 フェーズ3）

環境変数 `HARNESS_CREATOR_MODEL` が設定されていれば、run は creator を呼ぶ Agent ツールの `model` にその値を渡す。`scripts/transition.py` が log に書く `creator=` の値は `HARNESS_CREATOR_MODEL` を優先し、無ければ `.claude/agents/creator.md` の frontmatter の値にする。会話記録の `toolUseResult` から、エージェントの種別×モデルごとに呼び出し回数・トークン数・所要時間を集計する `scripts/usage_stats.py` を新設する。`docs/runbook.md` に、haiku を試して sonnet の時と `model_stats.py`・`usage_stats.py` の出力を比べる手順を書く。

正本は `vault/designs/D-013.md` の「フェーズ3 creator のモデルの切り替えと計測」（ゴール文・受け入れ基準の候補・決定済み）。切り替えの対象は creator だけで、verifier・planner のモデルは変えない。`vault/rules/`・`.claude/agents/` は変えない。

## 分割方針
- コードの変更2つ（transition.py・usage_stats.py の新設）と文書の変更3つ（run/SKILL.md・docs/vault-spec.md・docs/runbook.md）に分け、1タスク1つの主な成果物にする（smoke のケースは付随ファイル）
  - T-01：`scripts/transition.py` の `creator=` に `HARNESS_CREATOR_MODEL` を優先させる。smoke のケースと、smoke 全体を環境変数に左右されなくする `unset`
  - T-02：`scripts/usage_stats.py` の新設と smoke のケース（サンプルの会話記録は smoke の中で作る）
  - T-03：`.claude/skills/run/SKILL.md` の手順0.5と手順3（creator の呼び出しに `model` を渡す）
  - T-04：`docs/vault-spec.md` 7節（`creator=` の値の決め方・`usage_stats.py` の定義）
  - T-05：`docs/runbook.md` に haiku を試して比べる手順
- T-01・T-02 はどちらも `scripts/smoke.sh` を変えるので直列にする（T-01 → T-02）
- T-03 は T-01 の後（手順0.5が transition.py の新しい動きを書くため）。T-02 とは別ファイルなので並行してよい
- T-04 は T-01・T-02 の後（両方の実装を書き写すため）。T-05 は T-02・T-03 の後（usage_stats.py の使い方と run の切り替え手順を参照するため）。T-04 と T-05 は別ファイルなので並行してよい
- 各タスクは単体でマージしても smoke が `fail=0` で通る。文書のタスクは、先に入ったスクリプトの動きを書くだけにする
- smoke の件数は計画作成時点で `smoke: pass=670 fail=0`。受け入れ基準は件数ではなく `fail=0` とケース名で見る
- `scripts/model_stats.py` は変えない（`creator=` の値をそのまま集計キーにするので、`creator=haiku` の行は自動で haiku の行になる）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | transition.py の creator= に HARNESS_CREATOR_MODEL を優先させる | |
| T-02 | doing | 1 | T-01 | 会話記録から agent×model の使用量を集計する scripts/usage_stats.py を新設する | |
| T-03 | doing | 1 | T-01 | run/SKILL.md の creator の呼び出しで HARNESS_CREATOR_MODEL を Agent ツールの model に渡す | |
| T-04 | todo | 0 | T-01,T-02 | docs/vault-spec.md 7節に creator= の値の決め方と usage_stats.py の定義を書く | |
| T-05 | todo | 0 | T-02,T-03 | docs/runbook.md に haiku を試して sonnet と比べる手順を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む
- `vault/rules/` と `.claude/agents/` は変わっていない（`git status --porcelain -- vault/rules .claude/agents` が空）

## 次フェーズの候補
- D-013 フェーズ4（標準の役割定義をエージェント定義に統合する）。フェーズ3の後に始める

## 人への質問
計画は次の前提で書いた。違う場合は承認前に指示してほしい。
1. 会話記録の `resolvedModel` は完全なモデル ID（実際の記録では `claude-sonnet-5` など）で、log の `creator=` は alias（`sonnet`・`haiku`）になる。`usage_stats.py` は `resolvedModel` を変換せずそのまま出す。runbook には「両者の表記が違うので見比べる時に対応を読み替える」と書く
2. （回答済み：B）`usage_stats.py` の既定の読み込み先は、プロジェクトの絶対パスの英数字以外をすべて `-` に置き換えたディレクトリにする（Claude Code の実際の変換に合わせる）
3. （回答済み：B）`totalToolUseCount` を読み、出力の末尾に `tool_uses_avg` 列を足す（D-013 の見出しに1列足した7列）
4. セッションの再開（`--resume` など）で同じ Agent 呼び出しの結果が複数の会話記録に写ることがあるため、`toolUseResult` の `agentId` が同じものは1回だけ数えることにした（設計に無い追加。`agentId` が無いものは毎回数える）
