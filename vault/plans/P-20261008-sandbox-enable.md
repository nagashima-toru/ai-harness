---
id: P-20261008-sandbox-enable
status: approved
---
# ゴール
サンドボックスを有効にする（D-013 フェーズ5）

このリポジトリの `.claude/settings.json` に Claude Code のサンドボックスの設定（`sandbox.enabled: true`・`sandbox.allowUnsandboxedCommands: false`・`sandbox.filesystem.denyWrite` に `vault/rules/` と `~/.claude/projects/`・`sandbox.network.allowedDomains` に GitHub のドメイン）を足す。あわせて `docs/install.md`（導入先で有効にしたい人向けの手順と既知の制約）、`docs/vault-spec.md` 12節の「残る弱点」（Bash とその子プロセスの書き込みは OS が拒否し、Bash の解析は補助になる）、`docs/runbook.md`（有効にした後、新しいセッションで人が確かめる手順）を更新する。`scripts/smoke.sh` には、導入先の既存の `.claude/settings.json` に `sandbox` キーが入らないことのケースを足す。

正本は `vault/designs/D-013.md` の「フェーズ5 サンドボックスを有効にする」（ゴール文・受け入れ基準の候補・決定済み・依存）。`scripts/merge_settings_json.py` は、新規作成の時に `sandbox` を書かないようにする最小の変更だけ入れる（T-06。人への質問1の回答：案A）。`permissions.allow`・`permissions.deny`・`agent_write_guard.py` の Bash の解析は変えない。

## 分割方針
- 成果物ごとに1タスクにする。同じファイルを2つのタスクで変えない
  - T-01：`.claude/settings.json` に `sandbox` を足す（設定の本体）
  - T-02：`scripts/smoke.sh` に、導入先の `.claude/settings.json`（新規導入でも既存でも）へ `sandbox` が入らないことのケースを足す
  - T-03：`docs/install.md` に、導入先で有効にする手順と既知の制約の節を足す
  - T-04：`docs/vault-spec.md` 12節に、サンドボックスの小節を足し「残る弱点」を直す
  - T-05：`docs/runbook.md` に、新しいセッションで人が効き目を確かめる手順の節を足す
  - T-06：`scripts/merge_settings_json.py` の新規作成の経路で `sandbox` キーを書かないようにする（T-02 の新規導入のケースの前提。`scripts/smoke.sh` は T-02 だけが変える）
- T-03〜T-06 は T-01 の後（実際の `sandbox` の値を引用・前提にするため）。T-02 は T-01 と T-06 の後（新規導入のケースが T-06 の変更を前提にするため）、T-03 も T-06 の後（新規導入でも入らないと書くため）。T-04・T-05・T-06 は互いに独立で、T-02・T-03 は T-06 の後に並行してよい。文書どうしの参照（T-03・T-04 → T-05 の節名「9. サンドボックスを確かめる」、T-04・T-05 → T-03 の節名「サンドボックスを有効にする（任意）」）は、節名を各票の決定済みで固定して依存を作らない
- 設定はセッションの開始時に読まれるため、creator・verifier のセッションの中ではサンドボックスの効き目を確かめられない。受け入れ基準は設定の形（`python3 -c` で JSON を読む）と文書の記述までにし、効き目はマージ後に人が新しいセッションで T-05 の手順に沿って確かめる
- smoke は導入先にも配られる（`install.sh` が `scripts/smoke.sh` を複製する）。そのため T-02 のケースは、このリポジトリの `.claude/settings.json` に `sandbox` があることを前提にせず、smoke の中で `sandbox` 入りの src のフィクスチャを作って使う
- smoke の件数は計画作成時点で `smoke: pass=694 fail=0`。受け入れ基準は件数ではなく `fail=0` とケース名で見る

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | .claude/settings.json にサンドボックスの設定を足す | |
| T-02 | todo | 0 | T-01,T-06 | 導入先の settings.json に sandbox が入らないことを smoke で確かめる | |
| T-03 | todo | 0 | T-01,T-06 | docs/install.md に導入先でサンドボックスを有効にする手順と既知の制約を書く | |
| T-04 | done | 1 | T-01 | docs/vault-spec.md 12節にサンドボックスの小節を足し「残る弱点」を直す | |
| T-05 | review | 1 | T-01 | docs/runbook.md に新しいセッションでサンドボックスの効き目を確かめる手順を書く | |
| T-06 | doing | 1 | T-01 | merge_settings_json.py が新規作成の時に sandbox キーを書かないようにする | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `bash scripts/smoke.sh 2>&1 | tail -1` の出力が `fail=0` を含む
- サンドボックス無しでも動く：`scripts/agent_write_guard.py` と `.claude/settings.json` の `permissions`・`hooks` が main の版から変わっておらず（`git diff main -- scripts/agent_write_guard.py` が空）、smoke がサンドボックスの無いこのセッションで `fail=0` で通る（上の smoke の基準と同じ確認）
- `merge_settings_json.py` の変更は新規作成（`create`）の経路と docstring だけで、merge・skip の経路は変わっていない（T-06 の受け入れ基準と smoke の既存ケースで確認）

## マージ後に人が行う作業
- 新しいセッションを起動し、`docs/runbook.md` の「9. サンドボックスを確かめる」（T-05）の手順（`/sandbox` の Config タブの確認・`python3 -c "open('vault/rules/x.md','w')"` が失敗すること・`bash scripts/smoke.sh` が通ること・`bash scripts/vcs_finish.sh` の push と PR 作成が通ること）で効き目を確かめる
- `vcs_finish.sh` が通らなかった時は、人がサンドボックスの外（ターミナル）で `bash scripts/vcs_finish.sh` を実行する。繰り返すようなら、D-013 の決定どおり別の計画で `excludedCommands` に `bash scripts/vcs_finish.sh` を足す

## 人への質問（回答済み）
1. （回答済み）新規導入で `sandbox` が導入先に複製される件 → 人の回答：案A。`merge_settings_json.py` の `create` の経路で `sandbox` を除く。T-06 に入れ、T-02（新規導入のケース (sb-5)・(sb-6)）・T-03（新規導入でも入らない旨）に反映した
2. （回答済み）creator が `.claude/settings.json` を編集できない場合 → 人の回答：人が手で足す。T-01 が blocked になったら、人が T-01 の決定済みの JSON を足してコミットし、`/plan unblock` で進める
3. （回答済み）計画の途中でサンドボックスが効き始める件 → 人の回答：了解。公式ドキュメントでは、`sandbox.filesystem` の編集は実行中のセッションに反映されると書かれているため、T-01 のマージ後に効き始める可能性が実際にある。`vcs_finish.sh` が通らない時は、人がサンドボックスの外で `bash scripts/vcs_finish.sh` を実行する
4. （回答済み・確認済み）`denyWrite` のパスの書き方 → 公式ドキュメント（sandboxing）で、プロジェクトの設定では `.` の相対パスがプロジェクトのルートに解決され、`~/` はホーム、`/` は絶対パスと確認した。`./vault/rules`・`~/.claude/projects` の系統は合っている。`./` 付きのサブディレクトリと末尾の細かい表は確認できていないので、マージ後に `/sandbox` の Config タブで解決先を確かめる（T-05）
