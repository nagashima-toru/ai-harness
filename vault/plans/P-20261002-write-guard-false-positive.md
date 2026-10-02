---
id: P-20261002-write-guard-false-positive
status: approved
---
# ゴール
`.claude/hooks/agent_write_guard.py` が Bash コマンド文字列を過剰に拒否する問題を、ガードの安全性（fail-closed、すり抜けを作らない）を弱めずに解消する。GitHub Issue **#91**（P1 bug）と **#87**（P2 bug）を1計画で解決する。

- #91：creator / verifier / planner が Bash の引数・ヒアドキュメント・grep パターンなどに `~/.claude/projects/`・`vault/plans/`・`vault/log/`・`→`（`->`）・`git commit`・`git add`・`mkdir` を含む文字列を渡すと、実際には書き込まないのに拒否される（#85 の後半を集約）。main ブランチ上の `git commit` 拒否にも同じ誤検知がある（人の回答で範囲に含めた）。
- #87：done 遷移のコマンドを `&&` で連結すると（例：`printf '...' >> vault/log/<計画ID>.md && git add ... vault/verdicts/...`、`git add ... && git commit -m "$(cat <<'EOF' ...)"`）、`is_git_stage_or_commit_only` の除外が効かず拒否される。`.claude/skills/run/SKILL.md` 手順6.3.4 に「分けて実行する」旨の記載が無い。

## 分割方針
**現行コードの分析（計画時点）**
- Bash の判定6か所（`targets_vault_rules`・`targets_transcript_dir`・`targets_creator_denied_paths`・`find_done_task_write`・`main()` の verifier/planner 向け ALLOWED 判定・`main()` 冒頭の main 直接コミット拒否）は、どれも「`BASH_WRITE_PATTERNS`（main 直接コミット拒否は `GIT_COMMIT_PATTERN`）がコマンド文字列のどこかにマッチするか」で書き込みの有無を決めている。前の5か所は、そのうえで対象パスを「パスらしいトークン全部」から正規表現で拾っている。引用符内・ヒアドキュメント本文・読み取りコマンドの引数も区別しないため、誤検知が起きる。planner 自身も、この計画を作る途中で `awk '$1>430'` と `python3 -c "...'...2>&1 >> a.md...'"` が拒否された（#91 と同じ現象）
- main 直接コミット拒否は、main 上で `grep -n "git commit" README.md`・`echo "run git commit later"`・ヒアドキュメント本文の `git commit` まで拒否する。一方で `git -C . commit -m x`・`git -c user.name=x commit -m x` は `\bgit\s+commit\b` にマッチしないため許可される（planner が計画時点の現行フックで確認）
- #87 の1例目（`printf ... >> vault/log/... && git add ... vault/verdicts/...`）は、リダイレクトを含むため `is_git_stage_or_commit_only` が False になり、従来の判定に落ちる。従来の判定は、`git add` の引数にある done の verdict パスを書き込み対象として拾ってしまう。2例目は `$(` を含むため同じく従来の判定に落ちる

**方式**
- 共通の解析関数 `analyze_bash_writes(cmd)` を1つ作り、shlex のトークン化とセグメント分割でコマンドごとの実際の書き込み対象（verb と target の組）を求める。各判定は、解析できた時だけこの精密な結果を使う。解析できない形（コマンド置換・サブシェル・`cd`・変数を含む対象・インタプリタやラッパー経由・`git -C` などの前置オプション・展開されるヒアドキュメント本文の `$(` など）では `None` を返し、**現行の判定をそのまま使う**（fail-closed。精密化は「解析できた範囲で狭める」だけで、解析できない形の判定は今と変わらない）
- main 直接コミット拒否（人の回答1）：解析できた時は、実際に実行される `git commit`（`&&`・`;`・改行で連結した後ろも含む）がある時だけ拒否する。解析できない時は従来の `GIT_COMMIT_PATTERN` に加え、`git -<オプション> … commit` の形も拒否する。後者は現行で許可される `git -C . commit` を拒否側に倒すもので、人の指示（「`git -C` 等の形を含めて引き続き拒否」）による唯一の締め付けになる
- #87：**案1（run/SKILL.md 6.3.4 に「別々のコマンドで実行し、コミットメッセージにコマンド置換・ヒアドキュメントを使わない」と明記）で確定。案2（`$(cat <<'EOF' …)` の標準形に限って許可）は採らない**（人の回答2）。理由は次の3つ
  - 1例目（`printf >> log && git add ...`）は、T-03 の精密解析で自然に許可される（リダイレクト先は log だけで、done の verdict は `git add` の対象＝内容を変えない）。特別な緩和は要らない
  - 2例目は `$(` を含む。コマンド置換の中身は任意のコマンドを実行できるので、標準形を見分ける専用の解析を足すのは、ガードで最もすり抜けを作りやすい箇所を緩めることになる
  - done 遷移のコミットメッセージは短い定型（`<計画ID>/<id>: done` 等）で足り、ヒアドキュメントは要らない
- 「起点コミット」欄（#91 の検討事項）：**採らない**。理由は次の3つ
  - 起点の記録は既に2つある。creator がタスク票「進捗」に `起点コミット: <hash>` を書き、`.claude/agents/verifier.md` の宣言外ファイル検査がそれを読む。run も log に `worktree path=... plan_head=<sha>` を追記する（`docs/vault-spec.md` 7節）
  - 計画票のタスク表に列を足すと、表を解析するフック（plan_guard・stop_gate・agent_write_guard の `plan_raw_rows`、列数6の検査）と `docs/vault-spec.md` 4節の列定義に影響する
  - タスク票の6見出しは固定（5節）
- タスクの切り方：解析関数と最初の利用者（agent_type を問わない改ざん防止2判定）を T-01 で作り、残りの利用者を1判定ずつ T-02〜T-04・T-07 に分ける。T-01〜T-04・T-07 はどれも `agent_write_guard.py` と `scripts/smoke.sh` の2ファイル（実装とその回帰テストで1PR分。P-20260929-done-guard-git-staging/T-01 と同じ扱い）を変えるため、競合しないよう `after` で直列にする（T-01→T-02→T-03→T-04→T-07）。T-07 は人の回答で後から足したので ID が末尾になっている
- T-05（run/SKILL.md 6.3.4）は別ファイルなので、T-01 と並行して着手できる。T-06（`docs/vault-spec.md` 12節）は実装の挙動を正確に書くため、T-04・T-05・T-07 の後にする
- 対象外：`ln`・`dd of=`・`rsync`・`install`・`truncate` など、現行でも検出していない書き込み経路は今回も足さない（ゴールを広げない）。main 直接コミット拒否で、git のエイリアス（`git ci` 等）も今回は検出しない（現行でも検出していない）

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | analyze_bash_writes を追加し vault/rules/ と会話記録の Bash 判定を精密化する | |
| T-02 | review | 2 | T-01 | creator の vault/plans/・vault/log/ 拒否の Bash 判定を analyze_bash_writes に載せ替える | |
| T-03 | todo | 0 | T-02 | done タスク書き込み拒否の Bash 判定を analyze_bash_writes に載せ替える（#87 の連結を許可） | |
| T-04 | todo | 0 | T-03 | verifier/planner 向け ALLOWED の Bash 判定を analyze_bash_writes に載せ替える | |
| T-05 | done | 1 | - | run/SKILL.md 手順6.3.4 にログ追記・git add・git commit を別々に実行する旨を明記する | |
| T-06 | todo | 0 | T-04,T-05,T-07 | vault-spec.md 12節に Bash の精密判定と従来判定へのフォールバック条件を書く | |
| T-07 | todo | 0 | T-04 | main 直接コミット拒否の Bash 判定を analyze_bash_writes に載せ替える | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- T-01〜T-04・T-07 の完了後も、`bash scripts/smoke.sh` の既存ケース（計画時点で pass=370）が1件も NG にならない。追加ケースを含めた目安は T-07 完了時点で pass=435 以上（T-01 +16、T-02 +12、T-03 +10、T-04 +13、T-07 +14）

## 次フェーズの候補
- （無し。main 直接コミット拒否の精密化は人の回答で T-07 として今回に含めた）

## 人への質問
- （回答済み）main 直接コミット拒否は今回の計画に含める（T-07）。読み取り・引用符内・ヒアドキュメント本文は main 上でも許可し、実際に `git commit` を実行するコマンド（`&&`・`;` 連結の後ろ、`git -C` 等の形を含む）は拒否する。解析できない形は従来判定にフォールバックする
- （回答済み）#87 は案1（run/SKILL.md 6.3.4 に明記）で確定。案2は採らない
