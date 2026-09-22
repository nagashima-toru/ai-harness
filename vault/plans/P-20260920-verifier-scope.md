---
id: P-20260920-verifier-scope
status: approved
---
# ゴール
verifier（検証エージェント）の責務に2つの新しい軸を加え、「creator が書いた確認コマンドを再実行するだけ」の状態から脱する。
足す責務は (1) 各受け入れ基準について「確認コマンドが通ることがタスク票の『目的』の達成を意味するか」を判定し、
基準が緩いと判断したら `ok: true` のまま `note`/`reasons` に記録する、(2) 変更されたファイル一覧とタスク票の
「成果物」を突き合わせ、宣言外ファイルの変更を同じ機構で記録する、の2つに限定する。どちらも `FAIL` には繋がない
（既存の「判定不能」の機構をそのまま流用する）。`vault/rules/verifier/verifier.md`・`.claude/agents/verifier.md`・
`docs/vault-spec.md`・`docs/decisions.md` を改訂し、実際に verifier サブエージェントを呼んで挙動を確認する。

## 分割方針
全57件の verdict がすべて `PASS`/`attempt: 1` で、verifier が FAIL を出した記録が一件も無いこと、
`vault/rules/planner/planner.md` が「語を数えるだけの緩い確認コマンドを書かない」と定めているにも関わらず
`vault/tasks/P-20260920-git-workflow/T-01.md` の `grep -c 'ブランチ' ...` が1以上という緩い基準を
verifier が PASS にした実例（`vault/verdicts/P-20260920-git-workflow/T-01.json`）が背景にある。
人の決定済み事項どおり、verifier に自由裁量は与えず、具体的で検査可能な責務を2つだけ足す。

タスクは「ルール文書の改訂（正本）→ エージェント定義の改訂（正本を実行手順に落とす）→ 周辺ドキュメントの改訂 →
実地での動作確認」の順に割った。

- T-01：`vault/rules/verifier/verifier.md` の「責務」に2つの新責務と宣言外ファイルの除外リストを追加する契約タスク。
  以降のタスクが参照する正本になるため最初に置く。
- T-02：`.claude/agents/verifier.md` の手順に同じ2責務を具体的なステップとして追加する。verifier サブエージェントは
  実際にはこのファイルの手順に従って動くため、T-01 の内容を手順として落とし込む。`after: T-01`。
- T-03：`docs/vault-spec.md` の「## 6. verdict.json」節に、`reasons` が FAIL 理由だけでなく判定不能・基準が緩い・
  宣言外ファイルの記録にも使われることを明記する。ドキュメントの整合のみで T-01/T-02 の実ファイルには依存しない
  （文言は本票の決定済みで確定しているため独立して進められる）。
- T-04：`docs/decisions.md` に今回の判断（責務拡張とFAILに繋がない理由）を1行追記する。同じ理由で独立させる。
- T-05：ダミーの計画票・タスク票を使い、緩い基準と宣言外ファイルの変更を実際に仕込んで verifier サブエージェントを
  呼び、生成された verdict の `reasons` に両方が記録されることを確認する実地テスト。挙動の変更を検証する以上
  `after: T-01,T-02` とし、確認後はダミーファイルをすべて削除する。

- T-06（T-01 完了後に人の承認で追加）：T-01 が書いた宣言外ファイル検査は `git status --porcelain` で変更
  ファイル一覧を取る内容だったが、`vault/rules/creator/git-workflow.md` が「作業ステップごとにコミット」と
  定めているため、verifier が動く時点では作業ツリーがクリーンで何も検出できないことが T-01 の検証中に判明
  した（`vault/verdicts/P-20260920-verifier-scope/T-01.json` の `reasons` が空）。取得方法を
  `git diff --name-only main...HEAD` に直す。あわせて T-05 の実地テストも「コミットしてから verifier を
  呼ぶ」形に直し、実運用の条件を再現するようにした（`after` を `T-02,T-06` に変更）。

6タスクで収まり、次フェーズの候補は無い（今回追加しない2点「verifier が確認コマンドを自分で導出する」
「宣言外ファイル検出を FAIL に昇格させる」は決定済みで明示的に対象外とされており、運用が固まった後に
人が改めて計画するかどうかを判断する）。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | vault/rules/verifier/verifier.md に2つの新責務を追加する | |
| T-02 | done | 1 | T-01 | .claude/agents/verifier.md の手順に同じ2責務を反映する | |
| T-03 | done | 1 | - | docs/vault-spec.md の verdict 節に reasons の意味論拡張を明記する | |
| T-04 | review | 1 | - | docs/decisions.md に責務拡張の判断を1行追記する | |
| T-06 | done | 1 | T-01 | 宣言外ファイル検査の取得方法を git diff --name-only main...HEAD に直す | |
| T-05 | todo | 0 | T-02,T-06 | 実地テストで verifier の新責務2つの動作を確認する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01 → T-02 → T-05、T-03・T-04 は独立）
- 1タスクが1コンテキストで終わる粒度である
- 全タスク完了後、`bash scripts/smoke.sh | tail -1` に `fail=0` が含まれる
- `vault/rules/verifier/verifier.md` の「やらないこと」節が変更されていない
