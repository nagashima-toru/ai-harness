---
id: P-20261005-bash-write-unify
status: draft
---
# ゴール
設計文書 `vault/designs/D-011.md` の「フェーズ3 agent_write_guard.py の Bash 書き込み判定の一本化」を行う。

`agent_write_guard.py` で、Bash コマンドの書き込み対象を求める処理を1つの関数 `bash_write_targets(cmd, root)` にまとめ、1回のフック呼び出しで1度だけ計算するようにする。今は `targets_vault_rules`・`targets_transcript_dir`・`targets_creator_denied_paths`・`find_done_task_write`・ALLOWED 判定（と `is_git_commit_command`）が、それぞれ `analyze_bash_writes` を呼び直している。解析できない時の従来判定も、わずかに違う正規表現で4通り書かれている。

- 解析できた時：`analyze_bash_writes` の結果を返す
- 解析できない時：4通りの従来判定が拾っていた候補の和集合（リダイレクト先・`extract_bash_write_targets` の結果・保護対象パス（`vault/rules/`・`vault/plans/`・`vault/log/`・`vault/tasks/`・`vault/verdicts/`・`.claude/projects`）を含む path-like トークン）を返す
- 各判定はこの結果をパスで絞り込むだけにする
- `BASH_WRITE_PATTERNS`・`OTHER_WRITE_PATTERNS`・`DESTRUCTIVE_BASH_PATTERN` の重複を、1つの定義から組み立てる形にまとめる

既存の smoke は全件 PASS のまま保ち、それ以外で挙動が変わる箇所は拒否する側に倒す。D-011 の決定事項の表、フェーズ3の「決定済み」、「今回やらないこと」を前提にする（settings.json の許可リスト・smoke.sh の分割・Bash 解析の精度向上・`project_dir` の統一は含めない）。

## 分割方針
- 現状（planner が読み取り専用で確かめた事実。2026-10-05 時点の main = 854cc4e。フェーズ1・2はマージ済み）
  - `bash scripts/smoke.sh 2>&1 | tail -1` は `smoke: pass=513 fail=0`
  - `analyze_bash_writes` を呼んでいる関数は `targets_vault_rules`・`targets_transcript_dir`・`targets_creator_denied_paths`・`find_done_task_write`・`is_git_commit_command`・`main`（ALLOWED 判定）の6つ。1回の Bash 判定で最大5回呼ばれる（フィクスチャ `bash_writes_check.py` の出力で `max_calls=5`）
  - 解析できない時の従来判定は4通り（いずれも `BASH_WRITE_PATTERNS` に一致しなければ書き込み無し）
    - `_legacy_targets_vault_rules_bash`：リダイレクト先 ＋ `vault/rules/` を含む path-like トークン（区切りは空白・`'`・`"`）
    - `targets_transcript_dir`：`extract_bash_write_targets` ＋ `.claude/projects` を含む path-like トークン。末尾の `)`・バッククォート・`;` を落として判定
    - `targets_creator_denied_paths`：リダイレクト先 ＋ `vault/plans/`・`vault/log/` を含む path-like トークン
    - `find_done_task_write`：`extract_bash_write_targets` ＋ `vault/tasks/`・`vault/verdicts/` を含む path-like トークン（区切りに `)` も含む）。末尾の `)`・`"`・`'`・バッククォートを落として判定。git add / git commit だけなら対象外
    - ほかに `main` の ALLOWED 判定：`extract_bash_write_targets` の対象が全て root 外なら許可、リダイレクト先が全て ALLOWED 配下で `DESTRUCTIVE_BASH_PATTERN` に一致しなければ許可
  - `OTHER_WRITE_PATTERNS` の git サブコマンドの並びは、既存の `GIT_WRITE_SUBCOMMANDS` と同じ集合
- 確認用のフィクスチャ（planner が作成済み。どのタスクも編集しない）。verifier は repo の外に書けず、`>` や書き込み動詞を含む確認コマンドは書き込みガード自身に拒否されるので、判定を確かめる処理はスクリプトにして `vault/tasks/P-20261005-bash-write-unify/fixtures/` に置いた
  - `fixtures/patterns_check.py`：一本化前の3つのパターン定義を写しで持ち、201件のサンプルで新旧の一致を比べる。今は `pattern_mismatch=0`
  - `fixtures/targets_check.py`：`bash_write_targets(cmd, root)` の戻り値を10件の期待と比べる。今は関数が無いので `targets_mismatch=all`。期待値は、planner が T-02 の「決定済み」どおりの試作を差し込んで `targets_mismatch=none` になることを確かめた（試作はファイルに残していない）
  - `fixtures/bash_writes_check.py`：`agent_write_guard` を import し、`analyze_bash_writes` を数える関数で包んで13件の Bash payload を `main()` に渡す。今は `mismatch=change-example`・`max_calls=5`
  - `fixtures/vault/plans/P-FX.md`：`bash_writes_check.py` が使う計画票（T-01 done、T-02 doing）。フックは `vault/plans/*.md` しか見ないので判定に影響しない
- タスクの分け方
  - T-01〜T-03 はすべて `.claude/hooks/agent_write_guard.py` を変えるので順に進める
  - T-01：3つのパターン定義を1つの定義から組み立てる（挙動は変えない）
  - T-02：`bash_write_targets` を足し、`vault/rules/`・会話記録・creator の3つの拒否判定をそれに載せ替える。メモ化にして、残りの呼び出し元はこの時点ではそのまま
  - T-03：done 判定・`is_git_commit_command`・ALLOWED 判定を載せ替え、`analyze_bash_writes` を直接呼ぶのを `bash_write_targets` だけにする。挙動が変わる箇所（拒否側）はここで出る
  - T-04（smoke.sh）・T-05（docs/vault-spec.md）は T-03 の後に1つずつ。互いに別ファイルなので並行してよい
- D-011 の受け入れ基準の候補からの調整
  - 「`grep -c BASH_WRITE_PATTERNS` が3以下」は、docstring の言及も数えてしまい、語を数えるだけの確認になるので、AST で「その名前を参照している関数が `bash_write_targets` だけ」を確かめる形にした（T-03）
  - 「`analyze_bash_writes` の呼び出しが高々1回」は、smoke のケース（T-04）に加えて、フィクスチャ `bash_writes_check.py` の `max_calls=1` でも確かめる（T-03）
  - 挙動が変わる例として、少なくとも `change-example`（verifier の、解析できない形で `/tmp` だけに書き込み、引数に `vault/tasks/...` を含むコマンド。変更前は許可、変更後は拒否）がある。T-04 で smoke のケースにする
- 既存の smoke の期待値は変えない（D-011）。T-01〜T-03 で既存の smoke が落ちた場合は、smoke.sh を直さず blocked にして question に書く
- 確認コマンドで `agent_write_guard` を import する時は `python3 -B` を使う（フィクスチャも `sys.dont_write_bytecode = True` にしてある）。構文の確認は `ast.parse` で行い、`py_compile` は使わない

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | BASH_WRITE_PATTERNS・OTHER_WRITE_PATTERNS・DESTRUCTIVE_BASH_PATTERN を1つの定義から組み立てる | |
| T-02 | todo | 0 | T-01 | bash_write_targets を足し vault/rules・会話記録・creator の拒否判定を載せ替える | |
| T-03 | todo | 0 | T-02 | done 判定・is_git_commit_command・ALLOWED 判定を bash_write_targets に載せ替える | |
| T-04 | todo | 0 | T-03 | smoke.sh に analyze_bash_writes の呼び出し回数と挙動が変わった例のケースを足す | |
| T-05 | todo | 0 | T-03 | docs/vault-spec.md 12節の Bash 判定の記述を一本化後の規則に直す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `analyze_bash_writes` を直接参照する関数が `bash_write_targets` だけ：`python3 -B -c "import ast; t = ast.parse(open('.claude/hooks/agent_write_guard.py').read()); print(sorted({f.name for f in t.body if isinstance(f, ast.FunctionDef) for n in ast.walk(f) if isinstance(n, ast.Name) and n.id == 'analyze_bash_writes'}))"` の出力が `['bash_write_targets']`
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0` を含み、pass が516以上

## 次フェーズの候補（票は起こさない）
- なし（D-011 はこのフェーズで完了。「今回やらないこと」の settings.json 許可リストの件は別の設計で扱う）

## 人への質問
1. ALLOWED 判定（verifier・planner の Bash）も和集合の候補で判定するため、解析できない形で repo の外だけに書き込むコマンドでも、引数や引用符の中に保護対象パス（`vault/tasks/...` など）があると拒否されるようになる（例：`python3 -c "open('vault/tasks/P/T-01.md')" > /tmp/x.txt`。変更前は許可）。D-011 の「拒否する側に倒す」に従い、この変化を受け入れる前提で計画した。verifier の確認コマンドが拒否されやすくなるのが困る場合は、ALLOWED 判定だけ和集合を使わない（従来の候補のまま）形に T-03 の「決定済み」を変えるので、指示がほしい
2. D-011 は「挙動が変わった点を PR 本文に『変更前→変更後』の形で列挙する」としているが、`scripts/vcs_finish.sh` は引数なしだと `gh pr create --fill`（コミットメッセージから本文を作る）になる。計画では、変わった点を T-03 の「進捗」と T-05 の `docs/vault-spec.md` 12節に書き、PR 本文への列挙は run の最後にオーケストレーターが `bash scripts/vcs_finish.sh --title ... --body ...` で行う想定にしている。この運用でよいか
3. `vault/rules/planner/planner.md` の「書き込みガードが拒否する形」の (2) は、解析できない形について「コマンドのどこかに `vault/rules/` を含む語があるだけで拒否されうる」と書いている。一本化後は `vault/plans/`・`vault/log/`・`vault/tasks/`・`vault/verdicts/`・`.claude/projects` を含む語でも同じことが起こりうる（質問1の帰結）。ルールの実体は人が直すため、この計画には含めていない。追随の要否を判断してほしい（必要なら、別計画で `<id>-proposal.md` を成果物とするタスクにする）
