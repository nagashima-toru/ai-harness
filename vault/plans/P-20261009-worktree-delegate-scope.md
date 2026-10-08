---
id: P-20261009-worktree-delegate-scope
status: approved
---
# ゴール
worktree 委譲の範囲を絞る（D-013 フェーズ6）

`.claude/hooks/agent_write_guard.py` が worktree の版のフックへ判定を委譲するのを、書き込み対象がすべて委譲先の worktree の中にある時だけにする。

- 書き込み対象に worktree の外のパス（メインリポジトリ・`~/.claude/projects/` など）が1つでもあれば、委譲せずにメインリポジトリ側のコードで判定する
- 書き込み対象が無い呼び出し（読み取りだけ）は、今どおり委譲する

`docs/vault-spec.md` 12節に委譲の範囲を書く。

正本は `vault/designs/D-013.md` の「フェーズ6 worktree 委譲の範囲を絞る」（ゴール文・受け入れ基準の候補・決定済み・依存）。`.claude/hooks/_hooklib.py`・`plan_guard.py`・`stop_gate.py` の委譲は変えない。

## 分割方針
- コードの変更（`agent_write_guard.py` と smoke のケース）と文書の変更（`docs/vault-spec.md` 12節）の2タスクに分ける
  - T-01：`agent_write_guard.py` の `main()` で、`H.delegate_to_worktree` を呼ぶ前に書き込み対象がすべて worktree の中かを判定する。あわせて、worktree から Bash でメインリポジトリの `vault/rules/` を絶対パスで指した時にメインリポジトリ側の判定で拒否できるようにする（下記）。smoke に `(wds-N)` のケースを足す
  - T-02：`docs/vault-spec.md` 12節に「worktree への委譲の範囲」の小節を足す（T-01 の実装に合わせる）
- T-02 は T-01 の後（直列）
- 計画作成時の調査で分かったこと：委譲を絞るだけでは、D-013 の受け入れ基準の候補「Bash の書き込み対象にメインリポジトリ側の絶対パスを含む時も拒否される」を満たせない。cwd が worktree の時、メインリポジトリ側のコードも root を worktree のルートで求めるため（`resolve_root`）、`touch <メインリポジトリ>/vault/rules/a.md` は `../...` と正規化されて `vault/rules/` 拒否に当たらず、許可される（一時リポジトリと `_HOOK_DELEGATED=1` で確認済み。Write は `file_path` の親から root を求めるので今でも拒否される）。そのため T-01 に、`vault/rules/` 拒否で絶対パスの書き込み対象をメインリポジトリのルート基準でも見る変更を入れる（ゴールの受け入れ基準を満たすのに要る最小の変更。人への質問1）
- smoke の件数は計画作成時点で未確認（planner のサンドボックスでは `mktemp -d` が `/var/folders/...` に書けず smoke が走らないため。人への質問4）。受け入れ基準は件数ではなく `fail=0` とケース名で見る

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | blocked | 1 | - | agent_write_guard.py の worktree 委譲を書き込み対象がすべて worktree の中にある時だけにする | マージに失敗した: error: unable to unlink old '.claude/hooks/agent_write_guard.py': Operation not permitted |
| T-02 | todo | 0 | T-01 | docs/vault-spec.md 12節に worktree への委譲の範囲を書く | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む

## 次フェーズの候補（票は起こさない）
- D-013 フェーズ7（古い記述の修正と参照切れの検査）。この計画には含めない

## 人への質問
1. 【計画への反映済み・要確認】T-01 に、`vault/rules/` 拒否で絶対パスの書き込み対象をメインリポジトリのルート（`CLAUDE_PROJECT_DIR`、無ければフックのファイルから求めた git のルート。`delegate_to_worktree` の `self_root` と同じ求め方）基準でも判定する変更を入れた。委譲を絞るだけでは D-013 の受け入れ基準の候補（Bash でメインリポジトリの絶対パスを指すと拒否）を満たせないため。この範囲の拡大でよいか
2. 【計画への反映済み・要確認】`2>/dev/null` や `> /tmp/claude/x` のように worktree の外（`/dev/`・`/tmp` を含む）へ書くコマンドも、D-013 のゴール文どおり「外のパスが1つでもあれば委譲しない」に含めた（例外を設けない）。その時はメインリポジトリ側のコードが判定する（root は今どおり worktree のルート）。例外を設けたい場合は指示がほしい
3. 同じ穴は creator の `vault/plans/`・`vault/log/` 拒否にもある（worktree から Bash でメインリポジトリの `vault/plans/` を絶対パスで指すと、root が worktree のため拒否に当たらない）。D-013 の範囲外なのでこの計画では直さない。別の計画にするか
4. このセッション（planner）のサンドボックスでは、macOS の `mktemp -d` が `/var/folders/...` に書けず、`bash scripts/smoke.sh` が `pass=292 fail=408` になった（`TMPDIR=/tmp/claude` でも `mktemp -d` は `/var/folders/...` を使うため変わらない）。creator・verifier のセッションで smoke が通るかは、run の最初の実行で確かめてほしい
