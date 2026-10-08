---
id: P-20261009-sandbox-friendly
status: approved
---
# ゴール
サンドボックスを有効にしたことで人の手作業が増えた不具合を直す（人の操作は計画の承認・blocked の解除・マージだけに戻す）

D-013 フェーズ5 のマージ後に分かった次の4つを直す。(1) transition.py の done・再試行の後の worktree とブランチの削除が、サンドボックスの `.git/worktrees/` への書き込み拒否で失敗し、人が `git worktree remove --force` と `git branch -D` を打っている。(2) `bash scripts/vcs_finish.sh` が、`git push -u` の `.git/config` への書き込み拒否と、`gh` の TLS の証明書の検証エラー（x509 OSStatus -26276）で失敗し、人が PR を作っている。(3) エージェントは `rm -rf` の拒否で自分の一時ファイルを消せず、人に消させている。(4) `scripts/smoke.sh` はサンドボックスの中で `mktemp -d` が失敗すると、空の変数のまま worktree と共有の `.git` に git の操作をして main を壊した前例がある。

## 分割方針
- 方針（推奨。人への質問1で確認する）：
  - A（採る）：`.claude/settings.json` の `sandbox.excludedCommands` に、検証付きの2つのスクリプト（`scripts/vcs_finish.sh`・`scripts/discard_worktree.sh`）の呼び出しだけを足す。`allowUnsandboxedCommands: false` は変えない
  - C（採る）：worktree の後始末は transition.py の中では直せない（サンドボックスの中の子プロセスは外に出られない）。run が transition.py の後に worktree が残っていれば `bash scripts/discard_worktree.sh` を呼ぶ（このスクリプトは除外の対象なのでサンドボックスの外で動く）。transition.py は変えない
  - D（採る）：一時ファイルは `/tmp/claude/<計画ID>-<タスクID>/` か `$TMPDIR` の下に作り、消さない・人に消させない。スクリプトの `mktemp` は `${TMPDIR:-/tmp}` のテンプレートを渡す。smoke.sh・install.sh・uninstall.sh・archive_plans.sh の4つを直し、smoke をサンドボックスの中でも通るようにする（人の回答：質問5。今回の計画で全部対応）
  - B（採らない）：`filesystem.allowWrite` に `.git/worktrees`・`.git/config` を足すと `.git` の保護が弱まる
  - E（採らない。参考）：`sandbox.enableWeakerNetworkIsolation: true`（macOS の trustd への接続を許し、`gh` などの Go の TLS の検証を通す）と `git push` の `-u` をやめる組み合わせでも PR は作れるが、全コマンドの通信の隔離が弱まる
- 成果物ごとに1タスクにする。同じファイルを2つのタスクで変えない。タスクは9つで、1計画7タスクの上限を超えるのは人が了承済み（質問5の回答）
  - T-01：`scripts/smoke.sh` に mktemp の失敗での中断を入れ、一時ディレクトリを `$TMPDIR` の下に作る（不具合4の保護）
  - T-02：`.claude/settings.json` の `sandbox.excludedCommands` に4つのパターンを足す（不具合1・2の土台）
  - T-03：`.claude/skills/run/SKILL.md` に「worktree の後始末（サンドボックス）」の節を足す（不具合1）
  - T-04：`docs/vault-spec.md` 12節のサンドボックスの小節と2節の done の後始末を直す（「`excludedCommands` は設定していない」が古くなるため。smoke がサンドボックスの中でも通ることも書く）
  - T-05：`docs/runbook.md` 9節を直す（「人がサンドボックスの外で `vcs_finish.sh` を実行する」が古くなるため。手順4の smoke はサンドボックスの中で流す形にする）
  - T-06：`.claude/agents/planner.md` の一時ファイルの置き場を `/tmp/claude/` にし、人に消させないと書く（不具合3）
  - T-07：`scripts/install.sh` の4か所の `mktemp` を `$TMPDIR` の下にし、失敗で中断する（smoke の install.sh のケースをサンドボックスの中で通す）
  - T-08：`scripts/uninstall.sh` の1か所の `mktemp` を `$TMPDIR` の下にし、ファイルを消す前に作って失敗で中断する
  - T-09：`scripts/archive_plans.sh` の1か所の `mktemp` を `$TMPDIR` の下にし、失敗で中断する
- 依存：T-01・T-07・T-08・T-09（4つのスクリプト）は互いに独立で並行できる。T-02・T-03・T-06 も独立。T-04・T-05（文書）は T-01・T-02・T-03・T-07・T-08・T-09 の後（smoke の動き・settings の実際の値・run の手順・4つのスクリプトの中断の文言を書くため）
- 調べて分かったこと（計画作成時。このセッションはサンドボックスの中）：
  - macOS の `mktemp -d`（テンプレート無し）と `mktemp`（同）は `$TMPDIR`（このセッションでは `/tmp/claude-501`）を使わず `/var/folders/...` に作ろうとして `Operation not permitted` で失敗する。`mktemp -d "$TMPDIR/x.XXXXXX"` は成功する
  - リポジトリを `/tmp/claude/psf-probe` に clone し、`BASH_ENV`（`/tmp/claude/psf-env.sh`）で `mktemp` をテンプレート付きに差し替えて smoke をサンドボックスの中で実行した。smoke.sh だけ直すと `fail=54`、smoke.sh と install.sh を直すと `fail=22`（`scripts/uninstall.sh`・`scripts/archive_plans.sh` の `mktemp` で落ちる）、smoke.sh・install.sh・uninstall.sh・archive_plans.sh の `mktemp` を全部直すと `smoke: pass=700 fail=0`。実行後の clone の `git status --porcelain`・`git worktree list`・ブランチは変わっていなかった（smoke は `$ROOT` のリポジトリに書かない）
  - 同じ差し替えで、`bash scripts/install.sh <dir>`・`--update` は最後に `done: <dir>` を出し、`.claude/settings.json` の写しをマニフェストにした導入先への `bash scripts/uninstall.sh` は最後に `remove .claude/harness-manifest.json` を出し、`bash scripts/archive_plans.sh --list --keep 100000` は `archive_plans: 移す計画がありません` を出した。差し替え無しでは3つともサンドボックスの中で `mktemp` の失敗で終わる（T-07〜T-09 の受け入れ基準はこの差を見る）
  - `scripts/uninstall.sh` の `mktemp` は、マニフェストに載ったファイルを消し CLAUDE.md を書き換えた後にあるので、失敗すると中途半端な状態で終わる。T-08 で消す前に移す
  - `excludedCommands` の仕様：公式ドキュメントはこのセッションから読めず（通信先が GitHub だけ）、未確認。代わりにインストール済みの Claude Code 2.1.294 の設定スキーマの説明で、`excludedCommands` は「Command patterns (Bash permission-rule syntax) that always run outside the sandbox. A convenience, not a security boundary: excluded commands still go through the permission flow.」、プロジェクトの設定の `excludedCommands` が無視されるのは「managed settings or a --settings file set allowUnsandboxedCommands: false」などの時だけ、と読めた。このリポジトリはプロジェクトの設定にだけ `allowUnsandboxedCommands: false` があるので、`excludedCommands` は効く見込み（マージ後に人が `/sandbox` で確かめる）
  - `gh` の TLS のエラーは、サンドボックスが macOS の trustd への接続を止めるためと読めた（同じスキーマに `enableWeakerNetworkIsolation` の説明「Needed for Go-based CLI tools (gh, gcloud, terraform, etc.) to verify TLS certificates」がある）。`vcs_finish.sh` をサンドボックスの外で動かせば起きない
- サンドボックスの中での実行の制約：
  - `.claude/settings.json`・`.claude/skills/`・`.claude/agents/` は書き込みが保護されていて、creator は編集を拒否されることがある。拒否された時は、各票の決定済みのとおり `/tmp/claude/P-20261009-sandbox-friendly-<タスクID>/` に写して編集・確認したパッチを残して `blocked` にし、人がパッチを計画ブランチに当ててコミットし `/plan unblock` で進める（人への質問4）。人の手作業はタスクごとにこの1回の適用だけで、以後は増えない
  - `bash scripts/smoke.sh` の全件は、個別のタスクのうちは creator・verifier ともサンドボックスの中で実行しない（T-01 の保護が計画ブランチに入るまでは空の変数で git を操作する危険があり、T-07〜T-09 が入るまでは install.sh などのケースが落ちる）。T-01 の受け入れ基準の、`TMPDIR` を存在しないディレクトリにした起動（最初の mktemp で中断する）だけは、grep の基準が真の時に限って実行する
  - T-07〜T-09 の受け入れ基準の install.sh・uninstall.sh・archive_plans.sh の起動は、`/tmp/claude/` の下の導入先か、読み取りだけの `--list` に限るので、サンドボックスの中で実行してよい（各票の決定済み）
  - 一時ファイル・フィクスチャは `/tmp/claude/P-20261009-sandbox-friendly-<タスクID>/` の固定パスに置き、`mkdir -p` で作る。消さない
- この計画の run の間は、T-02・T-03 が計画ブランチに入るまで transition.py の後始末が失敗して worktree が残る（不具合1そのもの）。T-02・T-03 が入った後、run は「worktree の後始末（サンドボックス）」の節で残った worktree を消してよい

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | smoke.sh が mktemp の失敗で中断し、一時ディレクトリを $TMPDIR の下に作るようにする | |
| T-02 | todo | 0 | - | settings.json の sandbox.excludedCommands に vcs_finish.sh と discard_worktree.sh を足す | |
| T-03 | todo | 0 | - | run スキルに、残った worktree を discard_worktree.sh で消す後始末の節を足す | |
| T-04 | todo | 0 | T-01,T-02,T-03,T-07,T-08,T-09 | docs/vault-spec.md のサンドボックスの小節と done の後始末を直す | |
| T-05 | todo | 0 | T-01,T-02,T-03,T-07,T-08,T-09 | docs/runbook.md 9節を excludedCommands と後始末に合わせて直す | |
| T-06 | todo | 0 | - | planner.md の一時ファイルの置き場を /tmp/claude/ にし、人に消させないと書く | |
| T-07 | todo | 0 | - | install.sh が mktemp の失敗で中断し、一時ファイルを $TMPDIR の下に作るようにする | |
| T-08 | todo | 0 | - | uninstall.sh が mktemp の失敗で中断し、一時ファイルを $TMPDIR の下に作るようにする | |
| T-09 | todo | 0 | - | archive_plans.sh が mktemp の失敗で中断し、一時ファイルを $TMPDIR の下に作るようにする | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `scripts/transition.py`・`scripts/vcs_finish.sh`・`scripts/discard_worktree.sh`・`.claude/hooks/` が変わっていない（どのタスクの「成果物」にも宣言していないので、差分ゲートで確認される）
- 既存の smoke が全件通る：`bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む（未実行。人がサンドボックスの外で確認する。creator・verifier は個別のタスクのうちはサンドボックスの中で実行しない）

## マージ後に人が行う作業
- サンドボックスの外（ターミナル）で `bash scripts/smoke.sh 2>&1 | tail -1` を実行し、`fail=0` を確かめる（計画の受け入れ基準）
- 新しいセッションで `docs/runbook.md` 9節の手順を行う（T-05 で直す手順）。`/sandbox` の Config タブで `excludedCommands` に4つのパターンが出ていること、手順4でサンドボックスの中の `bash scripts/smoke.sh` が `fail=0` になることを確かめる（docs の「全件が通ることは未確認」を確かめる1回）
- 次の計画の run の最後で、PR が人の手を介さずに作られること、`git worktree list` に done のタスクの worktree が残っていないことを確かめる。通らなかった時は `docs/runbook.md` 9節の「うまくいかなかった時」を見る

## 次の計画の候補（票は起こさない）
- `scripts/discard_worktree.sh` を、worktree のディレクトリが消えてメタデータだけ残った状態（transition.py の後始末が途中で失敗した時に起こりうる。未確認）でも消せるようにする
- run の手順8の `gh issue create` もサンドボックスの中では TLS の検証で失敗する見込み（今はファイルへの書き残しに落ちる）。除外に足すかを決める
- `docs/install.md` の「サンドボックスを有効にする（任意）」の既知の制約に、`excludedCommands` で `vcs_finish.sh` を外に出す方法を書く
- `scripts/install.sh` の `UPDATE_LIST`・`MANIFEST_LIST` の一時ファイルが trap で消されない（T-07 では直さない。今までどおり）
- 人への質問2の答えによっては、creator・verifier（`agent_type` が空でないもの）が除外の対象のスクリプトを呼ぶのを `agent_write_guard.py` で拒否する（D-013 フェーズ6 とは別の計画）

## 人への質問
1. 直し方は A（`excludedCommands` に `vcs_finish.sh`・`discard_worktree.sh` だけを足す）＋ C（run が残った worktree を `discard_worktree.sh` で消す）＋ D（一時ファイルは `/tmp/claude/`・`$TMPDIR` に置いて消さない）を推奨し、B（`.git` の書き込みを許す）と E（`enableWeakerNetworkIsolation` で `gh` の TLS をサンドボックスの中で通す）は採らない、でよいか
2. `excludedCommands` はコマンドの文字列で照合するので、creator が自分の worktree の `scripts/vcs_finish.sh` を書き換えて worktree の中で `bash scripts/vcs_finish.sh` を実行すると、そのスクリプトはサンドボックスの外で動く（permissions とフックの判定は受ける。サンドボックスを入れる前と同じ水準）。この穴はこの計画では塞がず、`docs/vault-spec.md` に既知の弱点として書く（T-04）、でよいか。塞ぐなら次の計画で `agent_write_guard.py` に足す
3. run の PR 作成の呼び出しは `env HARNESS_PR_BODY_FILE=<本文ファイル> HARNESS_PR_TITLE="<計画ID>: <ゴールの1行目>" bash scripts/vcs_finish.sh` の形で、パターン `env HARNESS_PR_BODY_FILE=* bash scripts/vcs_finish.sh` の `*` が空白・日本語・引用符を含むタイトルまで一致するかは確かめられていない（設定はセッションの外でしか効き目を見られない）。一致しなければ、run の呼び出しの形かパターンを直す計画を立てる、でよいか
4. T-02（`.claude/settings.json`）・T-03（`.claude/skills/run/SKILL.md`）・T-06（`.claude/agents/planner.md`）は、creator が編集を拒否されたら blocked にしてパッチを `/tmp/claude/P-20261009-sandbox-friendly-<タスクID>/` に残す。人がパッチを当ててコミットし `/plan unblock` で進める手作業が、最大3回（タスクごとに1回）ありうる。この運用でよいか

## 人の回答
- 質問5（回答済み）：smoke をサンドボックスの中で通すための install.sh・uninstall.sh・archive_plans.sh の修正は、次の計画に回さず今回の計画で全部対応する（T-07・T-08・T-09 を足した。タスクが7を超えるのも了承済み）
