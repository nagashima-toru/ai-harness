---
id: P-20261009-auto-approve
status: approved
---
# ゴール
承認待ちをなくし、会話記録の検査を外す（D-015 フェーズ2）

`/plan` を、承認待ちで止まらない流れにする。`.claude/skills/plan/SKILL.md` の A（計画を作る）の最後で、粒度の検査を通ったら計画票の `status` を `approved` にし、log に `- <日時> - draft→approved /plan による自動承認` を足してコミットし、続けて `/run`（`.claude/skills/run/SKILL.md`）の手順を実行する。B（`/plan approve`）は削る。C（`/plan unblock`）は残す。`.claude/hooks/plan_guard.py` から、会話記録による承認の裏付けの検査と unblock の裏付けの検査を削る（表の整合・done の行の verdict・粒度の検査は残す）。`.claude/ai-harness.md`・`docs/runbook.md` 1〜2節・`docs/vault-spec.md` 10節を合わせる。

正本は `vault/designs/D-015.md` の「フェーズ2 承認待ちをなくし、会話記録の検査を外す」（ゴール文・受け入れ基準の候補・決定済み）。前提のフェーズ1（P-20261009-sandbox-remove）は done でマージ済み。

あわせて、このフェーズ単独で動くために次の2つも直す（計画作成時の調査で分かったこと。人への質問1）。
- `.claude/hooks/agent_write_guard.py` の承認（draft→approved）の判定：メインセッションでも、会話記録に `/plan approve <計画ID>` が無ければ計画票の Edit を拒否する。これを残すと、`/plan` の自動承認が必ず拒否される
- `.claude/skills/run/SKILL.md` 手順1の2：承認済みの計画が無い時に「`/plan approve <計画ID>` を実行してください」と案内している

## 分割方針
- 成果物（主なファイル）ごとに1タスクにする。`scripts/smoke.sh` は T-01・T-02 の両方で変えるので、T-02 を T-01 の後にして並行させない
  - T-01：`plan_guard.py` から承認・unblock の裏付けの検査（`newly_approved_plans`・`approval_check`・`unblocked_rows`・`unblock_check` と警告の出力）を削る。付随して smoke の `(approve-post)`・`(unblock-post)` のケースを、「ブロックしない」ことを確かめる新しいケースに置き換える
  - T-02：`agent_write_guard.py` から承認の判定（`find_plan_approval` とその呼び出し）を削り、使われなくなる `_hooklib.py` の `is_approve_command` を削る。付随して smoke の `(approve-pre)` のケースを置き換える。unblock の判定（`find_plan_unblocks`）は D-015 フェーズ3 で消すので残す
  - T-03：`.claude/skills/plan/SKILL.md` の A の最後を自動承認と `/run` の続行にし、B を削って C を B に繰り上げる。frontmatter の description・argument-hint も直す。付随して `.claude/skills/run/SKILL.md` 手順1の2の案内を直す
  - T-04：`.claude/ai-harness.md` のスキルの節の `/plan` の説明を直す
  - T-05：`docs/runbook.md` の1節・2節を直す
  - T-07：`README.md` の「## 使い方」の `/plan` の行と「## 仕組み」の図を直す（人への質問2の回答で追加）
  - T-08：`.claude/agents/planner.md` の「## 禁止」と「## 受け渡し」の承認の記述を直す（人への質問2の回答で追加）
  - T-06：`docs/vault-spec.md` の10節（裏付けの検査の2段落）と、それに連なる記述（2節の transition.py の注記・4節の status の表・7節の承認の log の形式・12節の承認の行と会話記録の説明）を直す
- 依存：T-01・T-03・T-04・T-05・T-07・T-08 は互いに独立。T-02 は T-01 の後（smoke.sh を共有）。T-06 は T-01・T-02・T-03 の後（フックの実際の判定と skill の log の形式を書くため）
- 範囲外にしたもの（D-015 の後のフェーズで直す）
  - `agent_write_guard.py` の unblock の判定・会話記録への書き込みの拒否・`_hooklib.py` の `human_messages`・`is_unblock_command`（フェーズ3。unblock の判定が使うので今回は残す）
  - `docs/runbook.md` の冒頭の「人の仕事」の「計画を承認する」（フェーズ5 の受け入れ基準の候補が直す）
  - `.claude/ai-harness.md`・`docs/runbook.md` 4節・`docs/vault-spec.md` 2節の「フックが会話記録で確認する」：今回も `agent_write_guard.py` の unblock の判定が会話記録を見るので事実のまま。フェーズ3・5 で直す
- 計画作成時の確認：`bash scripts/smoke.sh 2>&1 | tail -1` は `smoke: pass=716 fail=0`。`(approve-post)` の ok は26件、`(unblock-post)` は31件、`(approve-pre)` は31件、`(unblock-pre)` は41件

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | plan_guard.py から承認と unblock の会話記録による裏付けの検査を削り、smoke のケースを置き換える | |
| T-02 | done | 1 | T-01 | agent_write_guard.py から承認の判定を削り、_hooklib.py の is_approve_command と smoke のケースを合わせる | |
| T-03 | done | 1 | - | plan スキルの A を自動承認と /run の続行にし、B（/plan approve）を削る | |
| T-04 | done | 1 | - | ai-harness.md のスキルの節から /plan approve を外し、自動承認の説明にする | |
| T-05 | done | 1 | - | runbook の1節・2節を承認待ちの無い流れに直す | |
| T-06 | doing | 1 | T-01,T-02,T-03 | vault-spec の10節と関連する記述から承認の裏付けの検査を外し、自動承認に合わせる | |
| T-07 | doing | 1 | - | README.md の使い方の表と仕組みの図から /plan approve を外し、自動承認の流れにする | |
| T-08 | done | 1 | - | planner.md の「承認は人が行う」の記述を /plan による自動承認に合わせる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `scripts/transition.py` が変わっていない（どのタスクの「成果物」にも宣言していないので、差分ゲートで確認される。「approved でなければ拒否」は残す）
- `vault/log/` の既存の行は書き換えない（`vault/log/` は差分ゲートで変更できない）
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む

## 次のフェーズの候補（票は起こさない）
- D-015 フェーズ3（agent_write_guard を3つの判定に絞る。unblock の判定と `human_messages`・`is_unblock_command` もここで消える）

## 人への質問（回答済み）
1. `agent_write_guard.py` の承認の判定を T-02 で丸ごと削る既定案 → はい（T-02 の決定済みに反映）
2. `README.md`・`.claude/agents/planner.md` をこの計画に含めるか → 含める（T-07・T-08 を追加）
3. T-03 の流れ → はい。質問があれば止まり、解消するまで進まない。無ければ進む（T-03 の決定済みに反映）
