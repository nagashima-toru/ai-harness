# T-02 提案：vault/rules/verifier/verifier.md への追記

## 対象ファイル
`vault/rules/verifier/verifier.md`

## 挿入位置
「責務」箇条書きにある次の既存行の直後：

```
- 書き込むのは `vault/verdicts/<id>.json` だけ。
```

## 追記する文面（差分）

```
- worktree に入っている場合（プロンプトに「対象 worktree: `<path>`」が含まれ、`EnterWorktree(path=<path>)` で入った場合）は、`vault/verdicts/<id>.json` を書く前に `ExitWorktree(action: "keep")` でメインリポジトリ側の working directory に戻ってから書く。worktree・ブランチ自体は残したままでよい（`keep`）。または、戻らずに絶対パス（`$CLAUDE_PROJECT_DIR` 基準）で直接メインリポジトリ側のパスに書いてもよい。いずれの方法でも、相対パスのまま worktree 内に書き込んでしまわないことが目的。
```

## 反映後のイメージ（該当箇所のみ抜粋）

```
**責務**
- 受け入れ基準を上から1行ずつ取り出し、それぞれ真偽で判定する。全体の印象でまとめて採点しない。
...
- 書き込むのは `vault/verdicts/<id>.json` だけ。
- worktree に入っている場合（プロンプトに「対象 worktree: `<path>`」が含まれ、`EnterWorktree(path=<path>)` で入った場合）は、`vault/verdicts/<id>.json` を書く前に `ExitWorktree(action: "keep")` でメインリポジトリ側の working directory に戻ってから書く。worktree・ブランチ自体は残したままでよい（`keep`）。または、戻らずに絶対パス（`$CLAUDE_PROJECT_DIR` 基準）で直接メインリポジトリ側のパスに書いてもよい。いずれの方法でも、相対パスのまま worktree 内に書き込んでしまわないことが目的。
- 各受け入れ基準について、確認コマンドが通ることがタスク票の「目的」の達成を意味するかを判定する。...
```

## 備考
- `.claude/agents/verifier.md`（T-01 の成果物想定）と同趣旨の内容。ただしこちらはルール文書（`vault/rules/verifier/verifier.md`）の「責務」箇条書きへの1行追記であり、`.claude/agents/verifier.md` の「手順」節のような番号付き手順の追加・並べ替えは行わない。
- 既存の判定ロジック（曖昧判定・緩さ判定・起点コミット検査等）には触れない。書き込み先の明記のみを追加する。
- 実体（`vault/rules/verifier/verifier.md`）への反映は人が手作業で行う。このファイル自体は編集しない。
