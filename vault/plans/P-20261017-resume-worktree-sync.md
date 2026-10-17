---
id: P-20261017-resume-worktree-sync
status: approved
---
# ゴール
GitHub Issue #208「worktree を引き継いで再開すると、待機中にマージされた他タスクの変更が worktree に入らず、リポジトリ全体を見る基準を古い状態で判定する」を解決する。

## 分割方針
- 現状の確認：Issue の提案 (A)（引き継ぐ時に worktree へ計画ブランチの今の HEAD をマージする）は、`scripts/transition.py` の `resume_worktree` に `046478e`（#192）から入っている。H（計画ブランチの今の HEAD）が worktree のブランチの祖先でなければ worktree の中で `git merge --no-ff H -m "<計画ID>/<id>: 計画ブランチを取り込み"` を行い、衝突したら `merge --abort` して終了コード 5、成功時は `plan_head=H` を出す。smoke の `(transition-resume) 04`・`05`・`07` がこれを確かめていて、今の smoke は通る（pass=563 fail=0）。Issue の導入先はこれより前の版だった可能性があるが、確かめられない
- 残っている穴：取り込みでできたマージコミットを、review・done の「新規コミットの判定」（`git rev-list --count <plan-head>..<branch>`）が creator のコミットとして数える。blocked の時点で creator のコミットが無く、引き継いだ後も何も作らなかった worktree が、「新規コミット無し」の blocked にならずに review へ進む。T-01 で判定をマージコミットを数えない形（`--no-merges`）に直す
- Issue の場面そのもの（待機中に他タスクの成果物が計画ブランチに入り、その後に引き継ぐ）を smoke に足し、worktree に他タスクの変更が入ること・出力の `plan_head` と worktree の差分が自タスクの変更だけであること（逆向きの差分が宣言外の変更に見えないこと）・その `plan_head` で review と done が通ることを確かめる（T-01）
- 仕様の正本 `docs/vault-spec.md`（1節の証跡のコミットの種類・2節の review／done／引き継ぎ）と `.claude/skills/run/SKILL.md` 手順3の1を合わせる（T-02）。T-02 は T-01 と別のファイルだけを変え、新しいファイルを作らないので並行に進められる
- 衝突時の扱いは、今の終了コード 5（何も変えず、run がその id を通常の着手に回す）のまま変えない。理由：引き継ぎは todo からの遷移で、遷移表に todo→blocked が無い。通常の着手に回すと新しい worktree が計画ブランチの今の HEAD から作られるので、古い状態で判定する問題は起きない。古い worktree は破棄せず残り、run が完了報告で人に知らせる（run SKILL の終了コード 5 の行）
- 範囲外（次フェーズの候補）：引き継ぎでない通常の並行実行。同じ組で並行に作った T-02・T-03 は、手順4の review が両方とも手順6の done より前に行われるため、review や verifier の前に worktree へ計画ブランチを取り込んでも、同じ組の他タスクの変更は入らない（取り込みで解決できるのは引き継ぎの場合だけ）。同じ組の他タスクの変更に依存する基準を正しく判定するには、done の時点で計画ブランチが plan_head から進んでいたら再検証する、などの設計が要り、run の流れ全体に効くので今回は扱わない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | 新規コミットの判定で取り込みのマージコミットを数えず、Issue #208 の場面を smoke で確かめる | |
| T-02 | todo | 0 | - | vault-spec と run SKILL に引き継ぎの取り込みと新規コミットの判定を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補
- 通常の並行実行で、同じ組の他タスクが先に done になった後に検証・マージするタスクの、リポジトリ全体を見る基準の判定（done の時点で計画ブランチが plan_head から進んでいたら、計画ブランチを取り込んだ worktree で再検証する、など）。設計（`/design`）から始める
