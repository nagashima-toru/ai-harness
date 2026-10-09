---
id: P-20261009-sandbox-remove
status: draft
---
# ゴール
サンドボックスと不要な deny を外す（D-015 フェーズ1）

`.claude/settings.json` から `sandbox` キーを丸ごと外す。`permissions.deny` から `Bash(git reset --hard*)`・`Bash(git clean *)`・`Bash(git branch -D *)`・`Bash(curl *)`・`Bash(wget *)`・`Bash(claude *)` を外す（`git push --force` 系・`rm -rf` 系・`sudo`・`gh pr merge*`・`glab mr merge*` は残す）。`.claude/skills/run/SKILL.md` の「worktree の後始末（サンドボックス）」の節と、その節への参照を削る。`docs/runbook.md` 9節「サンドボックスを確かめる」を削り、`docs/vault-spec.md` 12節の「サンドボックス」の小節を「使っていない。理由」の短い記述にする。`docs/install.md` の「サンドボックスを有効にする（任意）」に、ハーネス自身（`.claude/`）を変える作業には向かない旨を足す。

正本は `vault/designs/D-015.md` の「フェーズ1 サンドボックスと不要な deny を外す」（ゴール文・受け入れ基準の候補・決定済み）。前提として P-20261008-sandbox-enable・P-20261009-sandbox-friendly は done（この計画はそれらが足したものを外す側で、重複しない）。

## 分割方針
- 成果物（ファイル）ごとに1タスクにする。同じファイルを2つのタスクで変えない
  - T-01：`.claude/settings.json` から `sandbox` と6つの deny を外す。`scripts/smoke.sh` の `(approve-settings)` のケースが `Bash(claude *)` が deny に「有る」ことを確かめているので、同じタスクで直す（settings だけ先に変えると smoke が落ちるため、付随の成果物として同じタスクに入れる）
  - T-02：`.claude/skills/run/SKILL.md` の「worktree の後始末（サンドボックス）」の節と、そこへの参照（手順4・6の「続けて…節を行う」、手順7の4の「サンドボックスの外で実行される」、回帰確認の5）を削る
  - T-03：`docs/runbook.md` の「## 9. サンドボックスを確かめる」の節を丸ごと削る
  - T-04：`docs/vault-spec.md` 12節の「サンドボックス」の小節を短くし、ほかの節のサンドボックス・`Bash(claude *)`・runbook 9節への言及を直す
  - T-05：`docs/install.md` の「サンドボックスを有効にする（任意）」に、ハーネス自身を変える作業には向かない旨を足し、本体で有効にしてある記述と runbook 9節への参照を直す
- 依存：T-01・T-02・T-03 は互いに独立で並行できる。T-04 は T-01・T-02・T-03 の後（settings の実際の値・run の手順・runbook の節を消した後の姿を書くため）。T-05 は T-01・T-03 の後
- 参照切れの調査（計画作成時）：
  - 「runbook 9節」への参照は `docs/vault-spec.md`（12節のサンドボックスの小節の「9. サンドボックスを確かめる」）と `docs/install.md`（「サンドボックスを有効にする（任意）」の末尾）の2か所だけ。どちらも T-04・T-05 で消す。runbook の 9 は番号付きの節の最後なので、ほかの節の番号は変わらない
  - smoke の参照切れの検査（`(ref-1)`）はバッククォート内のパスだけを見るので、節の削除では落ちない
  - smoke の `== sandbox を導入先に入れない ==`（`(sb-1)`〜`(sb-6)`）は、フィクスチャに `sandbox` を足して「導入先に入らない」ことを見るケースで、本体の settings.json の `sandbox` の有無に依存しない（本体から `sandbox` を消しても通る）。変えない
  - 計画作成時の `bash scripts/smoke.sh 2>&1 | tail -1` は `smoke: pass=710 fail=0`
- D-015 の依存の注記：フェーズ1 は、サンドボックスの中で `.claude/` を変えるタスクを取り込めない。サンドボックスの無いセッション（Web など）で run する。`.claude/settings.json`・`.claude/skills/run/SKILL.md` の編集を拒否された時は、別の手段で書き換えず、拒否の理由を question に書いて `blocked` にする（T-01・T-02 の決定済み）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | settings.json から sandbox と6つの deny を外し、smoke の deny のケースを合わせる | |
| T-02 | todo | 0 | - | run スキルから「worktree の後始末（サンドボックス）」の節とその参照を削る | |
| T-03 | todo | 0 | - | runbook の 9節「サンドボックスを確かめる」を削る | |
| T-04 | todo | 0 | T-01,T-02,T-03 | vault-spec のサンドボックスの小節を「使っていない。理由」にし、関連する記述を直す | |
| T-05 | todo | 0 | T-01,T-03 | install.md のサンドボックスの節に、ハーネス自身を変える作業には向かない旨を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `scripts/transition.py`・`scripts/discard_worktree.sh`・`scripts/vcs_finish.sh`・`scripts/merge_settings_json.py`・`.claude/hooks/` が変わっていない（どのタスクの「成果物」にも宣言していないので、差分ゲートで確認される）
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む

## 次のフェーズの候補（票は起こさない）
- D-015 フェーズ2（承認待ちをなくし、会話記録の検査を外す）
- 人への質問1の答えによっては、`.claude/agents/creator.md`・`scripts/discard_worktree.sh` のコメント・`README.md` の「サンドボックス」の古い記述を直す

## 人への質問
1. この計画の範囲（D-015 フェーズ1 のゴール文）の外に、deny・サンドボックスを外すと古くなる記述が3つある。(a) `.claude/agents/creator.md` の git 節「`git clean`・`git reset --hard` は使わない（`.claude/settings.json` の `permissions.deny` で拒否済み）」、(b) `scripts/discard_worktree.sh` の冒頭のコメント「`git branch -D` は … permissions.deny で … 拒否されているため」、(c) `README.md` の構成の節「settings.json（hooks・許可・サンドボックス）」。D-015 フェーズ5 の対象（`docs/`・`.claude/ai-harness.md`）にも入っていない。ゴールを広げないため、この計画では直さず次の計画に回す、でよいか（creator.md の「使わない」という指示そのものを残すか外すかも、その時に決めたい）
