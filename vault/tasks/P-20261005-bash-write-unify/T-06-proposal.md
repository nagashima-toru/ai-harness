# T-06 修正案

`vault/rules/planner/planner.md` の「書き込みガードが拒否する形」(2) の記述を、一本化（D-011 フェーズ3）後の挙動に合わせる修正案。反映は人が手作業で行う。

## 現行の該当箇所

`vault/rules/planner/planner.md` 47行：

~~~text
  同じ形では、コマンドのどこかに `vault/rules/` を含む語があるだけで、それを書き込み先とみなして拒否されうる（引数・引用符の中・ヒアドキュメントの本文でも。コマンドの別の場所にリダイレクトか書き込み動詞がある時）。例外として、本文が `cat` のヒアドキュメントだけのコマンド置換（`--body "$(cat <<'EOF' … EOF)"` の形）と、先頭の `cd <リポジトリのルート>`（`;` か `&&` で後ろに続くもの）は解析できる形として扱われる。cd 先がルート以外（worktree など）の時は解析できない形のままになる。
~~~

`vault/rules/planner/planner.md` 49行：

~~~text
  避け方：比較は `>` を使わず、`grep -c` の出力を期待値と見比べるか `test <数> -gt <数>` を使う。構文の確認は `python3 -c` に `>` を含めず `ast.parse` で書く。出力は標準出力で読む。`python3 -m py_compile`・repo の外（`/tmp/...` など）へのリダイレクト・`&&`／`;`／`|` の連結は、それだけではガードに拒否されない（連結は区切りごとの書き込み先で判定される）ため、拒否の理由に合わない代わりの手段を書かない。ただし、repo の外へのリダイレクトはガードの外（Claude Code の権限判定）で止まることがあるので、代わりの手段としても勧めない（上記の「複合コマンドにしない」項目の代替に従う）。`vault/rules/` のパスを含むコマンドは、解析できない形（上の (2)）と同じコマンドにつながず分けて実行するか、Read で読む。
~~~

## 直した文面

47行の置き換え後（全文）：

~~~text
  同じ形では、コマンドのどこかに保護対象パス（`vault/rules/`・`vault/plans/`・`vault/log/`・`vault/tasks/`・`vault/verdicts/`・`.claude/projects`）を含む語があるだけで、それを書き込み先とみなして拒否されうる（引数・引用符の中・ヒアドキュメントの本文でも。コマンドの別の場所にリダイレクトか書き込み動詞がある時）。verifier・planner では、書き込み先が repo の外（`/tmp/...` など）だけでも、また自分の許可ディレクトリ（planner の `vault/plans/`・`vault/tasks/`）配下の語でも、その語が書き込み先の候補に入って拒否されうる。例：`python3 -c "open('vault/tasks/P/T-01.md')" > /tmp/x.txt`。例外として、本文が `cat` のヒアドキュメントだけのコマンド置換（`--body "$(cat <<'EOF' … EOF)"` の形）と、先頭の `cd <リポジトリのルート>`（`;` か `&&` で後ろに続くもの）は解析できる形として扱われる。cd 先がルート以外（worktree など）の時は解析できない形のままになる。
~~~

49行の置き換え後（全文。最後の文の主語だけを直し、他の文は変えない）：

~~~text
  避け方：比較は `>` を使わず、`grep -c` の出力を期待値と見比べるか `test <数> -gt <数>` を使う。構文の確認は `python3 -c` に `>` を含めず `ast.parse` で書く。出力は標準出力で読む。`python3 -m py_compile`・repo の外（`/tmp/...` など）へのリダイレクト・`&&`／`;`／`|` の連結は、それだけではガードに拒否されない（連結は区切りごとの書き込み先で判定される）ため、拒否の理由に合わない代わりの手段を書かない。ただし、repo の外へのリダイレクトはガードの外（Claude Code の権限判定）で止まることがあるので、代わりの手段としても勧めない（上記の「複合コマンドにしない」項目の代替に従う）。保護対象パス（`vault/rules/`・`vault/plans/`・`vault/log/`・`vault/tasks/`・`vault/verdicts/`・`.claude/projects`）を含むコマンドは、解析できない形（上の (2)）と同じコマンドにつながず分けて実行するか、Read で読む。
~~~

46行・48行・41行・50行・64行は直さない。T-03 の「進捗」に、これらと食い違う挙動の変化は書かれていなかった。

## 理由

- 一本化（D-011 フェーズ3）で、解析できない時の書き込み先の候補は、4通りの従来判定（リダイレクト・書き込み動詞・パスらしい語・不明）の和集合を `bash_write_targets` が1度だけ計算して返す形になった。done 判定・git commit 判定・ALLOWED 判定（verifier・planner の Bash）はすべてこの和集合をパスで絞り込んで判定する。そのため、`vault/rules/` に限らず保護対象パス（`vault/rules/`・`vault/plans/`・`vault/log/`・`vault/tasks/`・`vault/verdicts/`・`.claude/projects`）を含む語は、どれも同じ扱いで書き込み先の候補に入る。
- ALLOWED 判定も和集合で行う（人の決定・元の質問1）。解析できない時の許可は、書き込み動詞なし、または全候補が root の外（`legacy-write` が1つ以上）、または全候補が ALLOWED 配下で `legacy-redirect` が1つ以上かつ破壊的パターンなし、のいずれかに限られる。
- 挙動が変わった例（T-03 の「進捗」、実装に合わせた）：verifier の `python3 -c "open('vault/tasks/P-FX/T-02.md')" > /tmp/x.txt` は、変更前は許可（解析不能で root 外へのリダイレクトだけを扱っていた）、変更後は拒否（和集合に `legacy-path` の root 内パス `vault/tasks/P-FX/T-02.md` が入り、全候補が root の外とは言えなくなる）。T-03 の「進捗」に、他に変わった例の記載はない。
- この計画で planner.md に追随する（人の決定・元の質問3）。ルールは `vault/rules/` 配下でエージェントは編集できないため、この提案ファイルで人が反映する。

## 他のロールのルール

`grep -n -e '解析できない' -e 'path-like' -e '含む語' vault/rules/creator/*.md vault/rules/verifier/*.md vault/rules/common/*.md` を実行した結果：一致なし（出力は空）。

- `vault/rules/creator/creator.md`（12・17・23行）：`vault/rules/` などへの直接書き込みが拒否される記述はあるが、解析できない形で語を含むだけで拒否される旨の記述は無い。直接書き込みの拒否は一本化で変わらないので直さない。
- `vault/rules/verifier/verifier.md`：同上。同種の記述なし。
- `vault/rules/creator/git-workflow.md`・`vault/rules/common/*.md`：同種の記述なし。

同種の記述なし、修正案なし。
