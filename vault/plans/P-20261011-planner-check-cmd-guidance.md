---
id: P-20261011-planner-check-cmd-guidance
status: approved
---
# ゴール
前回の計画（P-20261011-smoke-worktree-remove-quiet、PR #182、マージ済み）の振り返りで出たハーネスへの改善提案2件に対応する。

(1) planner が単一タスクの計画で、受け入れ基準の差分確認を `git diff --numstat main -- <path>` のように `main` と比べる形で書いた。作業中にローカルの `main` が進むと（`/plan` の手順2の `git fetch origin main:main` など）誤って FAIL になる。`.claude/agents/planner.md` 68行目の指針は複数タスク時の誤検知だけを理由に挙げている。単一タスクでも `main` と比べず、ベースの変動に影響されない書き方にするよう指針を直す。verifier は creator の worktree（PLAN_HEAD から分岐し、review で収集コミット済み）の中で実行するので、その状況で本当に機能する形を選ぶ。

(2) creator が受け入れ基準の確認コマンド `grep -cF 'git -C "$WTMAIN" worktree remove --force "$LEAF" >/dev/null 2>&1' scripts/smoke.sh` を実行しようとしたところ、Claude Code 側のガードがコマンドごと拒否した。実行環境で再現を試み、分かった範囲で、planner.md に拒否されにくい確認コマンドの書き方の指針を足す。

## 分割方針
- 主な成果物は `.claude/agents/planner.md`。改善提案(1)と(2)を別タスク（T-01・T-02）に分ける。同じファイルを変えるので、マージの衝突を避けるため T-02 は T-01 に `after` で依存させる。
- planner.md の「やらないこと」節は汎用の教訓だけを置き、このリポジトリ固有の経緯（計画 ID など）は `vault/rules/planner/ai-harness-lessons.md` に置く運用なので、経緯の追記を T-03 として別に起こす（成果物が別ファイル。見出しの文言は決定済みで固定するので T-01・T-02 に依存させない）。
- planner が事前に確かめたこと（各タスクの決定済みに反映済み）
  - (1) 一時リポジトリで「計画ブランチから worktree を分岐 → worktree で未コミットの変更 → `main` と計画ブランチが進む → worktree で収集コミット」を再現した。`git diff --merge-base <計画ブランチ> --name-only` は収集の前後とも成果物だけを出し、`main`・計画ブランチの前進に影響されなかった。`git status --porcelain` は収集コミットの後は空、`git diff --numstat main` は計画ブランチの先行変更と `main` の前進分まで出した（git 2.43）。
  - (2) planner のセッション（メインセッション、auto mode）で同じ `grep -cF '...'` を `cd` 付き・無しの両方で実行したが拒否されず、出力は `1` だった。`.claude/hooks/agent_write_guard.py` が Bash で止めるのはベースブランチ上の `git commit` だけで、`.claude/settings.json` の `permissions.deny` にも grep に当たる項目は無い。拒否の原因は確定できなかった。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | planner.md の差分確認の指針を main と比べない形（計画ブランチとの分岐点）に直す | |
| T-02 | todo | 0 | T-01 | planner.md に拒否されにくい grep パターンの書き方の指針を足す | |
| T-03 | review | 1 | - | ai-harness-lessons.md に2件の経緯を足し見出しを直す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補（票は起こさない）
- `.claude/agents/verifier.md` 29行目の note の書式の例 `git diff --numstat -- README.md` は、収集コミットの後の worktree では空になる。例を `git diff --merge-base` の形に揃えるか検討する（今回のゴールの範囲外のため触れない）。
- creator が確認コマンドをガードに拒否された時のふるまい（基準を読み替えずに blocked にするか、同等の安全なコマンドで確かめて進捗に書くか）を `.claude/agents/creator.md` に書くか検討する。
