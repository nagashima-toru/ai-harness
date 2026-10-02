---
id: P-20261003-run-finish-verifier-worktree
status: approved
---
# ゴール
GitHub Issue #89 を解決する。(1) `bash scripts/vcs_finish.sh` を引数なしで実行すると、`gh pr create` が非対話環境で `--title`/`--body` を求めて失敗する。(2) verifier が `EnterWorktree(path=...)` を使えない（verifier の tools は `Read, Grep, Glob, Bash, Write` で `EnterWorktree` を含まない）。このため毎回、worktree の絶対パスと `git -C` で代わりに検証している。

## 分割方針
- 人の代理の設計判断（変えない）
  - (1) は `scripts/vcs_finish.sh` 側で直す。引数が1つも無い時だけ既定値を付ける（gh は `--fill`、glab は `--fill --yes`）。引数がある時は今まで通りそのまま渡す。ホスティング判定・push・none 経路・exit コードは変えない
  - (2) は verifier に `EnterWorktree` を持たせない（権限を増やさない）。手順を「worktree の絶対パスに対して `git -C <パス>` と絶対パスで検証する」形に揃える。実運用では既にこの形で検証できている
  - `.claude/hooks/`・`.claude/settings.json` は触らない（issue #85：creator のフック・設定の編集は auto mode で拒否されうる）
- T-01：`scripts/vcs_finish.sh` の引数なし既定と、それを確かめる `scripts/smoke.sh` のケース。`smoke.sh` には今 vcs_finish.sh のテストが無い（`grep -n vcs_finish scripts/smoke.sh` の出力が空）。それでも T-01 の動作を実在の gh/glab を呼ばずに確かめるには、スタブで差し替えるテストが要る。実装とその回帰テストは切り離すと検証できないので、2ファイルを1タスクの成果物にする（理由はタスク票の「決定済み」にも書く）
- T-02：`.claude/skills/run/SKILL.md`。手順4・手順5の2の `EnterWorktree` 前提の記述を書き換え、手順7に vcs_finish.sh の引数なし既定の1文を足す。1ファイルの変更をまとめて1タスクにする
- T-03：`vault/rules/verifier/verifier.md` の17行目（worktree の扱い）の書き換え。`vault/rules/` はフックで常に書けないので、提案ファイル方式（`vault/tasks/<計画ID>/T-03-proposal.md`）にする
- T-04：`.claude/agents/verifier.md` の手順1・手順11（`EnterWorktree`/`ExitWorktree` 前提）の書き換え
- 4タスクはどれも別のファイルを変えるので互いに独立（after は `-`）。T-02〜T-04 の worktree の扱いの中心の文は、各タスク票の「決定済み」で同じ趣旨にそろえてある
- `.claude/agents/`・`.claude/skills/` への creator の書き込みが auto mode で拒否されるかは分からない。拒否されたら blocked にしてよいと、T-02・T-04 の「決定済み」に書いた

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | vcs_finish.sh を引数なしで非対話で通るようにし、smoke にケースを足す | |
| T-02 | done | 1 | - | run スキルの verifier の worktree 検証手順を絶対パス方式にし、手順7に引数なし既定を書く | |
| T-03 | done | 1 | - | verifier ルールの worktree の扱いを絶対パス方式に書き換える提案を書く | |
| T-04 | done | 1 | - | verifier エージェント定義の手順1・11を絶対パス方式に書き換える | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
1. glab の既定値：このマシンには `glab` が入っておらず、`glab mr create --help` で確かめられませんでした。planner が知っている glab の公式ドキュメントの内容（`-f, --fill`：コミットの情報を使い、title/description を聞かない。`-y, --yes`：送信の確認を飛ばす）をもとに、T-01 では GitLab の引数なしの時に `--fill --yes` を付けることにしました。指示の「確認できなければ gh だけ対応する」に当たると考えるなら、T-01 の「決定済み」の glab の項目を「glab は変更しない」に直し、T-01 の基準3・T-02 の手順7の文から GitLab の部分を外してください。
2. smoke.sh のケースを足すこと：指示は「smoke.sh に vcs_finish.sh のテストがあれば足す」でした。テストは無かったのですが、実在の gh を呼ばずに T-01 を検証する手段として、T-01 で smoke.sh に新しい節を作ることにしました。新しい節を作らないなら、T-01 を vcs_finish.sh だけに絞り、基準2・3を「verifier が /tmp にスタブを作って確かめる」形に書き直す必要があります。
3. hook の worktree 委譲（D-008）との関係：verifier が worktree に入らないと、verifier の Bash に対するフックは常にメインリポジトリ側のものが動きます（cwd がメインのまま）。`.claude/hooks/` 自体が成果物のタスクを検証する時、worktree 側の新しいフックではなく、メイン側の古いフックで判定されます。実運用でも EnterWorktree は使えておらず、既にこの状態でした。なので今回は手順の文面を合わせるだけにし、この点には手を付けていません。
