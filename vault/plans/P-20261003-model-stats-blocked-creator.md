---
id: P-20261003-model-stats-blocked-creator
status: done
---
# ゴール
GitHub Issue #97 を解決する。`scripts/model_stats.py` の集計キーを「最後の `doing→review` 行の `creator=`」から「最後の `creator=` 付き行（`doing→review` または `doing→blocked`）の値」に広げる。これで、creator が blocked 報告で終わったタスク（`doing→blocked creator=<モデル>`）が `unknown` に流れなくなる。それ以外の集計の定義（対象タスク・1回目 PASS 率・平均 attempt・blocked 率の分母と分子、出力形式）は変えない。

## 分割方針
- 人の代理の設計判断（変えない）
  - 集計キーに使う行は、遷移が `doing→review` か `doing→blocked` の行だけにする。そのうち `creator=` が付いた最後の行の値を使う。`creator=` が付いていない行（既存の古い形式）は読み飛ばし、それより前の `creator=` 付きの行の値を残す。`creator=` 付きの行が1つも無いタスクは `unknown`
  - 他の遷移（`review→done` など）に `creator=` が付いていても集計キーには使わない
  - `.claude/hooks/`・`.claude/settings.json` は触らない（issue #85）
  - `docs/vault-spec.md` と `vault/designs/` は `vault/rules/` ではない。`agent_write_guard.py` が creator に拒否するのは `vault/plans/`・`vault/log/`・`vault/rules/` だけなので（`DENIED_FOR_CREATOR` と改ざん防止の判定）、creator が直接書ける。提案ファイル方式にはしない
- T-01：`scripts/model_stats.py` の `collect()` の集計キーの決め方を変える。確認は verifier が `/tmp` に書き出したフィクスチャ log で行う
- T-02：`scripts/smoke.sh` の `== model_stats.py ==` 節のフィクスチャに、`doing→blocked creator=` で終わるタスクを2つ足し、期待値を直す。期待値は T-01 の新しい挙動が前提なので、T-01 の後にする（after T-01）
- T-03：`docs/vault-spec.md` 7節の集計キーの行（143行目）を書き換える
- `vault/designs/D-010.md` は過去の設計文書として当時のまま残す（人の指示で書き換えない。T-04 は作らない）
- T-03 は別のファイルの1行の変更で、T-01・T-02 とも独立（after は `-`）
- 確認コマンドは planner が読み取り専用で実行し、期待値を確かめた（新しい挙動の期待値は、変更案を `/tmp` に写したスクリプトで計算した）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | model_stats.py の集計キーを最後の creator= 付き行（doing→review/doing→blocked）にする | |
| T-02 | done | 1 | T-01 | smoke の model_stats フィクスチャに doing→blocked creator= で終わるタスクを足す | |
| T-03 | done | 1 | - | vault-spec 7節の集計キーの定義を書き換える | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
1. `creator=` が付いていない `doing→review`／`doing→blocked` 行の扱い：今のコードは、最後の `doing→review` 行に `creator=` が無いと、それより前の `creator=` を捨てて `unknown` にします。issue の「最後の `creator=` 付き行」の字句どおり、`creator=` の無い行は読み飛ばして前の値を残すことにしました（分割方針の1点目）。今の vault/log/*.md ではどちらでも集計結果は変わりません（planner が確認済み）。「creator= の無い行で unknown に戻す」方がよければ、T-01 の「決定済み」と基準2の期待値（sonnet の行）を直してください。
2. （回答済み）D-010 は過去の設計文書なので、人の指示で当時のまま残す。T-04 は作らない。
