作業は「作成 → 検証」の二段構成。検証（verifier）が PASS しない限り完了できない。状態はすべて
`vault/` のファイルにあり、仕様の正本は `docs/vault-spec.md`。1セッション=1計画=1ブランチで、計画
の作成から実行までを1本のブランチに閉じる。

## 開始時に読む順
1. `bash scripts/current_plan.sh` で、frontmatter の `status` が `approved` の計画票の計画 ID を得る（0件・2件以上なら止まる）
2. その計画票の「タスク表」を読む。`doing`・`review` の行があれば中断からの再開として扱う（`vault/log/<計画ID>.md` のその id の最後の記録行から worktree を復元する。手順は `.claude/skills/run/SKILL.md` の手順2）
3. 無ければ着手可能集合（`todo` かつ `after` が全部 `done` の行）の先頭から `HARNESS_MAX_PARALLEL`（既定3）件を取る
4. 「次は何をやる？」と聞かれたら、承認済み計画票のタスク表を読んで先頭タスクの ID と title を答える

## 状態遷移（5つで固定）
`todo → doing → review → (done | doing[attempt+1] | blocked)`。`blocked → todo` は人が `/plan unblock <計画ID> <id> [回答]` で指示した時だけ（フックが会話記録で確認する。エージェントの独断は不可）。
- `doing`/`review` は `after` 依存の無い集合（着手可能集合）に限り複数件になりうる。計画票・log への書き込みは常にオーケストレーター1プロセス（run のメインセッション）に集約する
- `done` にできるのは `vault/verdicts/<計画ID>/<id>.json` が PASS で、`attempt` が計画票のタスク表と一致する時だけ
- 状態を変えたら `scripts/transition.py` が `vault/log/<計画ID>.md` に1行追記する（`- YYYY-MM-DD HH:MM T-01 doing→review attempt=1 補足` の書式。日時は transition.py が実時刻で書くので、エージェントは書かない）

## 質問のしかた
- 着手前にまとめて出す。着手後は質問せず、判断が必要になったら `blocked` にして question 列に書く
- タスク票の「決定済み」にある回答を優先する。勝手に決めない、勝手に広げない

## 役割
- オーケストレーター（メインセッション）：`/run` でタスクを取り、`creator` を worktree で呼び、`verifier` で検証し、状態の変更と log の追記を `scripts/transition.py` で行う。全タスクが done になったら PR を作る。成果物は自分で作らない
- `creator`：着手時に `bash scripts/rules.sh creator` の列挙を読み、worktree で成果物を作り、タスク票の「進捗」に追記する。計画票のタスク表と `vault/log/` には書かない
- `verifier` は `vault/verdicts/`、`planner` は `vault/plans/`・`vault/tasks/` にだけ書く（詳細は `.claude/agents/` の各定義）

## スキル
`/plan <ゴール>`（計画を draft で作りブランチを切り、粒度の確認を通ったら approved にしてコミットし、続けて `/run` を実行する。`/plan unblock <計画ID> <id> [回答]` で blocked を解除して todo に戻す）・`/run`（自分のブランチの承認済み計画の取れるタスクを、全部 done になるまで処理し、PR を作る）・`/design <ゴール>`（大きなゴールを設計文書にする）

## 禁止
- `done` のタスク票・verdict を編集すること（フックで拒否される）
- `rm -rf`、`git push --force` などの破壊的操作（settings.json で拒否）
- 計画票のタスク表の列順・見出し名を変えること（フックが表を解析する）
