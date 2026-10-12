---
id: P-20261012-unblock-resume-and-install-fixes
status: done
---
# ゴール
GitHub Issue #189・#190・#191 の提案をハーネスに取り込む。

- #189：`/plan unblock` で成果物の追加と受け入れ基準の差し替えを正式に扱う（専用スクリプト `scripts/amend_task.py` で行い log に1行残す）。回答が他タスクにも効く時の追記は、回答文のタスク ID の書き方に頼らず、基準の文字列で同じ前提を持つ todo 票を探して行う
- #190：unblock 後の再着手で、blocked の時に残した worktree を引き継いで creator に続きを作らせる（`transition.py ... doing --resume-worktree`）。既定は引き継ぎで、人は unblock の時に `--fresh` で作り直しを選べる。分岐元が計画ブランチの HEAD より古ければ、先に計画ブランチを worktree にマージする
- #191：(1) `install.sh` が導入先の `.gitignore` に `.claude/worktrees/` を（無ければ）足し、`uninstall.sh` で戻す。(2) `/run` 手順7の PR 本文で、PR テンプレートの見出しを先に埋めてからハーネスの記録を付ける（テンプレートの選び方は汎用な書き方）。(3) creator の呼び出しは起動通知で返るのが普通、という主従に run の手順を改め、stop_gate の文言を「待機中なら問題ない」に寄せる

## 分割方針
- 仕組み（スクリプト・フック）を先に作り、それを使う手順書（スキル・エージェント定義）を後に、仕様書・判断の記録（`docs/`）を最後にする。新しく作る `scripts/amend_task.py` を参照する文書（smoke の `(ref-1)` の対象）は、T-01 に `after` で依存させる
- T-01〜T-04 は互いに依存しない（並行に取れる）。4つとも `scripts/smoke.sh` にテストを足すが、挿入位置をタスク票の「決定済み」で別々の離れた場所に固定して、計画ブランチへのマージで衝突しないようにした
- `.claude/skills/run/SKILL.md` は #190 と #191(2)(3) の3件の変更を1タスク（T-06）にまとめた（同じファイルを複数タスクで並行に変えるとマージが衝突するため）。`docs/vault-spec.md`・`docs/runbook.md`・`docs/guide.md`・`README.md`・`docs/decisions.md` の追従も1タスク（T-07）にまとめ、全タスクの後に置いた
- stop_gate（#191(3)）は「最初からブロックしない」案ではなく「文言を待機中なら問題ないに寄せる」案を採った。`docs/decisions.md` の 2026-10-10 の行（D-20261010-async-agent-wait、「`stop_gate.py` の判定は変えず…文面だけ」、人の選択）と食い違わないようにするため。あわせて、文言を出す条件を「その id の最後の `→doing` の行より後に記録行が無い」に直し、FAIL の再試行・引き継ぎの後の待ちでも同じ文言が出るようにする
- 受け入れ基準の差し替えは `--replace-criterion`（番号と新しい文）だけにした。行数を変えないので、受け入れ基準3〜7行の制約を崩さない。「読み替えの注記」で済ませる経路は作らない（verifier は基準そのものを判定するので、注記と基準が食い違うと Issue #189 の「判定不能。決定済みを優先して PASS」が再発する）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | scripts/amend_task.py を作る（成果物の追加・受け入れ基準の差し替えと log の記録） | |
| T-02 | done | 1 | - | transition.py に todo→doing の --resume-worktree（blocked の worktree の引き継ぎ）を足す | |
| T-03 | done | 1 | - | stop_gate.py の creator 待ちの文言と条件を直す | |
| T-04 | done | 1 | - | install.sh・uninstall.sh で導入先の .gitignore の .claude/worktrees/ を足し・戻す | |
| T-05 | done | 1 | T-01,T-02 | /plan unblock の手順に amend_task.py・基準の文字列での todo 票の探索・--fresh を入れる | |
| T-06 | done | 1 | T-02,T-03 | /run の手順に worktree の引き継ぎ・起動通知が普通という主従・PR テンプレートを入れる | |
| T-07 | done | 1 | T-01,T-02,T-03,T-04,T-05,T-06 | vault-spec・runbook・guide・README・decisions を今回の変更に追従させる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- 全タスクの後で `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` で終わる

## マージ後に人が行う作業
- Issue #189・#190・#191 を閉じる（PR 本文から参照する）
