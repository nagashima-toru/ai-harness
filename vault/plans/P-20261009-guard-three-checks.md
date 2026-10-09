---
id: P-20261009-guard-three-checks
status: approved
---
# ゴール
agent_write_guard を3つの判定に絞る（D-015 フェーズ3）

`.claude/hooks/agent_write_guard.py` の判定を次の3つだけにする。

- (a) done のタスク票（`vault/tasks/<計画ID>/<id>.md`）・verdict（`vault/verdicts/<計画ID>/<id>.json`）への Write・Edit・MultiEdit・NotebookEdit を、agent_type を問わず拒否する（今の判定と同じ条件）
- (b) 現在のブランチが `main` の時の `git commit` を拒否する（Bash のコマンドを正規表現で見る簡単な判定。引用符の中などの誤検知は許容する）
- (c) verifier の Write・Edit の書き込み先を `vault/verdicts/` に限る

`vault/rules/` の保護、会話記録への書き込みの拒否、リモート直叩き（`gh api`・`curl`）の検知、Bash の書き込み解析（`bash_write_targets` とその周辺）、creator・planner の書き込み先の制限は削る。worktree への委譲は残す。`_hooklib.py` の関数で使われなくなったものは削る。`scripts/smoke.sh` の削った判定のケースを消し、`docs/vault-spec.md` 11〜12節を新しい判定に合わせる（提案ファイル方式・改ざん防止の記述も消す）。

正本は `vault/designs/D-015.md` の「フェーズ3 agent_write_guard を3つの判定に絞る」（ゴール文・受け入れ基準の候補・決定済み）。前提のフェーズ2（P-20261009-auto-approve）は done でマージ済み。フェーズ2 の計画で残した blocked の解除の判定（`find_plan_unblocks`。会話記録で `/plan unblock` を確かめる）も、3つの判定に入らないのでこのフェーズで削る。

## 分割方針
- D-015 の決定済みのとおり「フックの本体」「smoke のケース」「文書」で分ける。同じファイルを2つのタスクで変えない
  - T-01：`agent_write_guard.py` を3つの判定と worktree への委譲だけにし、使われなくなった `_hooklib.py` の関数（`human_messages`・`is_unblock_command`）を削る。smoke はまだ直さないので、T-01 の時点では smoke の agent_write_guard の節に NG が出る（受け入れ基準はフックを直接呼んで確かめる）
  - T-02：`scripts/smoke.sh` から削った判定のケースを消し、3つの判定・削った判定が効かないこと・委譲のケースを足す。T-01 の後にする。smoke 全体の `fail=0` はここで初めて基準にする
  - T-03：`docs/vault-spec.md` の 11〜12節を新しい判定に合わせる。smoke の参照切れの検査を含めて `fail=0` を基準にするので、T-01・T-02 の後にする
- タスク数は3。フェーズ4（stop_gate）・フェーズ5（文書の整理）は別の計画にする

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | agent_write_guard.py を3つの判定と worktree への委譲だけにし、使われなくなった _hooklib.py の関数を削る | |
| T-02 | todo | 0 | T-01 | smoke.sh の agent_write_guard のケースを3つの判定に合わせて消し・足す | |
| T-03 | todo | 0 | T-01,T-02 | vault-spec.md の11〜12節を3つの判定に合わせ、提案ファイル方式・改ざん防止の記述を消す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 範囲外（このフェーズでは変えない。フェーズ5 か別の計画で扱う）
- 計画作成時の調査で、守りを絞った後に古くなる記述が `docs/vault-spec.md` の 11〜12節の外にもあると分かった。2節の遷移の説明「（フックが会話記録で裏付ける）」がその例で、ゴールが 11〜12節に限っているので変えない（フェーズ5 の「文書を実際の状態に揃える」で直す）
- `agent_write_guard` の拒否・提案ファイル方式に触れている `README.md`・`docs/runbook.md`・`docs/install.md`・`docs/decisions.md`・`vault/rules/README.md`・`.claude/agents/planner.md`・`.claude/agents/creator.md` も変えない。このうち `README.md`・`vault/rules/README.md`・`.claude/agents/*.md` は、D-015 フェーズ5 の対象の一覧（`docs/` と `.claude/ai-harness.md`）に入っていない
