---
id: P-20260924-run-parallel-orchestration
status: approved
---
# ゴール
D-003（`vault/designs/D-003.md`）フェーズ3「並行実行オーケストレーション」を実施する。フェーズ1（`P-20260924-run-parallel-state`）・フェーズ2（`P-20260924-creator-subagent`）は完了済み（done）。`run` スキルに、計画票のタスク表から「着手可能集合」（`todo` かつ `after` が全て `done`）を求め、環境変数 `HARNESS_MAX_PARALLEL`（既定 3）を上限にタスクを選ぶ手順を追加する。選んだタスク全部をまとめて1回の書き込みで `doing` にし、`vault/log/<計画ID>.md` に1回（または選んだタスク分まとめて）追記する。その上で、選んだタスクそれぞれについて Agent ツールで `creator` を `isolation: "worktree"` 付きで並行起動する（1メッセージで複数呼び出し）。各呼び出しの結果からタスクごとの worktree パス・ブランチを受け取る。次に、完了した creator それぞれについて verifier を並行起動する。verifier は通常（非 worktree）の Agent 呼び出しとし、プロンプトでタスク ID と対象 worktree のパスを渡し、verifier は `EnterWorktree(path=...)` でその worktree に入ってから検証して `vault/verdicts/<計画ID>/<id>.json` を書く。全 verifier の完了後、オーケストレーターはタスクを1件ずつ逐次処理する：PASS なら該当 worktree のブランチを計画ブランチへ `git merge --no-ff` し、成功したら計画票を `review→done` にしてログ追記し worktree を削除する。マージでコンフリクトが起きたら該当タスクを `blocked` にし question にコンフリクトの状況を書き、worktree は削除せず残す。FAIL なら計画ブランチへはマージせず、attempt 上限未満なら `doing`（attempt+1）に、上限到達なら `blocked` にし、いずれもログに追記する（worktree は次の attempt で再利用するか、破棄して次の attempt 時に作り直すかは実装時に決めてよい）。着手可能集合が1件しかない場合も同じ経路（creator/verifier サブエージェント + worktree）を通す。

## 分割方針
フェーズ3のゴール文は「着手可能集合の算出とdoingへの一括反映」「creator の並行 worktree 起動と verifier の並行 EnterWorktree 起動」「マージ・状態遷移(done/blocked)・attempt 更新の逐次処理」の3つの塊に分かれており、いずれも `.claude/skills/run/SKILL.md` の別々の手順（手順2／手順3・5／手順6・7）を書き換える独立した変更なので、そのまま3タスクに分ける。3タスクとも同じファイル（`run/SKILL.md`）の異なる手順を扱うが、後段の手順は前段で決めた前提（着手可能集合が複数件になる・worktree パスが記録されている）を使って書くため、`after` で T-01→T-02→T-03 と直列に依存させる。
- T-01（契約タスク寄り）：`HARNESS_MAX_PARALLEL` の導入と、着手可能集合を複数件 `doing` に一括反映する手順を先に固定する。以降のタスクはこの「複数タスクが同時に doing になる」前提の上に書く。
- T-02：T-01 で選ばれた複数タスクを、creator（worktree 隔離）→ verifier（EnterWorktree）の順で並行処理する手順を書く。worktree の分岐元確認方法はこのタスクで実装時に調査して明記する。
- T-03：T-02 で得られた verdict と worktree を使い、マージ・状態遷移・attempt 更新を逐次処理する手順と、1件のみの場合の回帰確認手順を書く。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | 着手可能集合の算出と doing への一括反映（HARNESS_MAX_PARALLEL 導入） | |
| T-02 | todo | 0 | T-01 | creator 並行 worktree 起動と verifier 並行 EnterWorktree 起動の手順追加 | |
| T-03 | todo | 0 | T-02 | マージ・状態遷移（done/blocked）・attempt 更新の逐次処理と回帰確認 | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `.claude/skills/run/SKILL.md` を通しで読んで、手順2〜7が矛盾なく一連の流れとして繋がっている（手順番号のずれ・前提の齟齬がない）
</content>
