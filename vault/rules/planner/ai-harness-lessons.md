## 目的
`.claude/agents/planner.md` の「やらないこと」節が生まれた、このリポジトリ（ai-harness）固有の経緯（T-xxxx・計画 ID・issue 番号と、何が起きたか）を集めた経緯集。
汎用の教訓の本文は `.claude/agents/planner.md` の「やらないこと」節に残してあり、ここには経緯だけを置く。このファイルは導入先に配布しない（`install.sh` が配るファイル（マニフェストに載るもの）にも、削除の対象の一覧にも加えない）。
`vault/rules/planner/` に置くため、このリポジトリ自身の planner が `bash scripts/rules.sh planner` で読む。

## ルール
各項目は「教訓（`.claude/agents/planner.md` の「やらないこと」節の項目を指す一言）」と、その元になった経緯を並べる。

**状態ファイルの差分不変を基準にしない**
- 経緯：状態ファイル（計画票のタスク表・`vault/log/<計画ID>.md`・タスク票の「進捗」）への `git diff --quiet` を基準にしたため、T-0002 が blocked になった（旧方式での失敗例）。

**語を数えるだけの緩い確認コマンドを書かない**
- 経緯：T-0016 の `grep -c 'planner' <file>` が1以上、という基準は、「planner を呼ばない」と書けていなくても通ってしまった。

**成果物本文に無い文字列を grep しない**
- 経緯：T-0012（`vault/rules`）・T-0013（「## 構成」ツリーの `rules.sh`）では、基準を通すために creator が後から文言を足す羽目になった。

**差分の確認を `main` と比べない（計画ブランチとの分岐点と比べる）**
- 経緯：`P-20260925-worktree-baseref-merge` の T-01・T-03 で、`git diff main -- ...` が空という形の基準が、先行タスクの変更が計画ブランチに既にマージされているため字句どおり機能しなかった。過去2回 verifier が自力で `git status --porcelain` 等の代替確認に切り替えて PASS 判定した（issue #42）。
- 経緯：`P-20261011-smoke-worktree-remove-quiet`（単一タスクの計画）で、planner が受け入れ基準の差分確認を `git diff --numstat main -- <path>` の形で書いた。作業中にローカルの `main` が進むと（`/plan` の手順2の `git fetch origin main:main` など）誤って FAIL になる形で、振り返りで指摘された。あわせて、それまで勧めていた `git status --porcelain` は、review への遷移の収集コミットの後は空になり、verifier の時点では何も確かめないことを、`P-20261011-planner-check-cmd-guidance` の planner が一時リポジトリで確かめた（`git diff --merge-base` で計画ブランチからの分岐点と比べる形は、収集の前後とも成果物だけを出した）。

**後片付けに `rm -rf` を前提にしない（固定パス＋`mkdir -p`）**
- 経緯：`P-20260925-vcs-finish-push-and-diff-criteria` の T-01 で、確認コマンドが `$(mktemp -d)` と事前の `rm -rf` 前提で書かれていたため、verifier が `.claude/settings.json` の `permissions.deny`（`Bash(rm -rf *)`）に阻まれ、その場で固定パス `/tmp/vftest_a`・`/tmp/vftest_b`・`/tmp/vftest_c` に書き換えて回避した（issue #46）。

**確認コマンドを複合コマンドにしない**
- 経緯：ツール実行時サンドボックスが、パイプ・`&&`・コマンド置換を含む複合コマンドを「即時拒否」または「無応答ハング」で止めた（issue #46, #48）。
- issue #48 では "git" を含まない場合でも、`&&` 連結や末尾に `git status --porcelain | grep` を含む長い複合コマンドでハングが再現した。

**「他ファイル不変」の除外パスにタスク票自身を含める**
- 経緯：`P-20260925-sandbox-hang-timeout`/T-01 で、除外パスにタスク票自身が無い基準が、creator の「進捗」追記のため毎回非空になり3回連続で FAIL した。人が個別に確認コマンドを修正してから再開した（issue #51）。

**単語の出現有無・回数だけを唯一の確認コマンドにしない**
- 経緯：`P-20260926-fix-smoke-sh-failures`/T-03・T-04 の受け入れ基準1（`grep -n "worktrees" <file>` の出力が1行以上）について、verifier が「単語の出現回数のみを見る緩い基準で、単独では実際の除外動作を保証しない」と指摘した。後続の基準が機能検証を兼ねていたため実害は無かった（issue #68）。

**新しく作るファイルへの参照は、そのファイルを作るタスク以降に入れる**
- 経緯：P-20261011-user-guide-entry の T-01 で `.claude/agents/planner.md` に、後続の T-02 で作る `docs/guide.md` をバッククォートで書かせたため、smoke の `(ref-1)` が NG になり `fail=0` の基準と同時に満たせず blocked になった（issue #172）

**確認コマンドの grep パターンにシェルの特殊文字を入れない**
- 経緯：`P-20261011-smoke-worktree-remove-quiet` の T-01 で、creator が受け入れ基準の `grep -cF 'git -C "$WTMAIN" worktree remove --force "$LEAF" >/dev/null 2>&1' scripts/smoke.sh` を実行しようとしたところ、Claude Code 側のガード（サンドボックス／権限判定）がコマンドごと拒否し、creator はパターンの一部（`git -C "`）を削って確かめた。`P-20261011-planner-check-cmd-guidance` の planner のセッション（メインセッション、auto mode）で同じコマンドを実行した時は拒否されず（出力 `1`）、このリポジトリのフックと `.claude/settings.json` の `permissions.deny` にも該当する判定が無いため、原因は確定していない。

## 確認方法
- planner が受け入れ基準を書く時、ここの経緯を参照し、同じ失敗（状態ファイルの差分不変・緩い grep・複合コマンド・`rm -rf` 前提・除外パスの漏れなど）を繰り返していないかを見る。
- 経緯に対応する教訓が `.claude/agents/planner.md` の「やらないこと」節に残っているか（教訓を消してここだけに経緯が残る形になっていないか）。
- このファイルが導入先に配布されていないか（`install.sh` が配るファイル（マニフェストに載るもの）にも、削除の対象の一覧にも含まれていないか）。