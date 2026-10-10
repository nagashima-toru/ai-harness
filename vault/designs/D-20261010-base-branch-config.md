---
id: D-20261010-base-branch-config
---
# ゴール
ハーネスが `main` を直書きしている箇所を、環境変数 `HARNESS_BASE_BRANCH`（既定 `main`）で変えられるようにする。あわせて、push 先と PR/MR の head を環境変数 `HARNESS_PUSH_BRANCH` で上書きできるようにし、クラウドセッションのように push 先が外から決められている環境でも手順どおりに PR まで進められるようにする（#163）。

## 決定事項
人に聞いて確定した回答。以降のフェーズはこれを前提にする。1件1行。

| 決めたこと | なぜ |
|---|---|
| 設定は環境変数 `HARNESS_BASE_BRANCH`・`HARNESS_PUSH_BRANCH` で持つ。専用の設定ファイルは作らない。恒久的に変える時は導入先の `.claude/settings.json` の `env` に書けば効く | 人の選択。既存の `HARNESS_MAX_ATTEMPTS` などと同じパターンにそろえ、読む規則（優先順位）を増やさない |
| どちらの値も前後の空白を除いて扱い、空（未設定を含む）なら未設定とみなす。`HARNESS_BASE_BRANCH` の未設定は `main`、`HARNESS_PUSH_BRANCH` の未設定は「現在のブランチ」 | `HARNESS_CREATOR_MODEL` の「空白を除いて空でなければ」と同じ扱いにそろえる。既定値で今の動作が変わらない |
| フック (b) の直接コミット拒否は、現在のブランチが `HARNESS_BASE_BRANCH` の値か `main` の時に拒否する（両方が同じなら1つ） | 人の選択。develop 運用でも main への直接コミットは引き続き守る |
| `HARNESS_PUSH_BRANCH` 上の直接コミットはフックで拒否しない | 人の選択（「ベースと main」を選んだ）。push 先ブランチ上ではそもそも作業しない運用で足りる |
| `/plan`・`/design` の開始条件は「現在のブランチがベースブランチ」、または「`HARNESS_PUSH_BRANCH` が設定され、現在のブランチがその値で、`git rev-parse HEAD` がローカルの `<ベースブランチ>` と同じコミット」のどちらか。どちらでもなければ従来どおり止まる。後者の時も現在の HEAD から `work/…`・`design/…` を切る | 人の選択。クラウドセッションはベースと同一コミットの指定ブランチ上で始まるため、内容が同じなら安全に切れる。違うコミットなら他の作業が乗っている可能性があるので止める |
| `HARNESS_PUSH_BRANCH` が設定されている時、`vcs_finish.sh` は上流の有無に関係なく毎回 `git push -u origin HEAD:<値>` で push し、GitHub の REST では `head=<値>`、GitLab では `glab mr create` に `--source-branch <値>` を足す。push が失敗したら（non-fast-forward 含む）その終了コードで終わる。force はしない | 指定ブランチはリモートに既にある場合が多く、上流が無いことを push の条件にすると push されない。失敗時は人が判断する |
| ホスティング無し（`none`）の経路は `HARNESS_PUSH_BRANCH` を見ない。マージ案内の取り込み先は `HARNESS_BASE_BRANCH` の値にする | none では push しないため。取り込み先だけがベースに依存する |
| 計画 ID・ローカルのブランチ名（`work/<計画IDの英小文字>`・`design/…`）・transition.py のブランチ検査は変えない。push 先だけを上書きする | ローカルの1計画=1ブランチの規律（transition.py・stop_gate.py・purge_plan.sh が前提にしている）を崩さない |
| クラウドセッションのように push 先が実行環境の指示で決まっていて環境変数に無い時は、オーケストレーターがその値を `env HARNESS_PUSH_BRANCH=<指定ブランチ> …` でコマンドに渡す（開始条件の確認と `vcs_finish.sh` の両方） | セッションごとに値が変わるので環境の設定には書けない。`env` で始めれば許可リストの `Bash(env *)` で通る |
| フェーズは2つに分ける：1 ベースブランチの設定化、2 push 先の上書き | 人の選択。フェーズ1だけでも既定値（main）で動作が変わらず、単体でマージできる |

## 依存関係
- フェーズ1 → フェーズ2（直列）。フェーズ2はフェーズ1の `HARNESS_BASE_BRANCH` の読み取り（開始条件の比較対象）を使う

---

## フェーズ1 ベースブランチを `HARNESS_BASE_BRANCH` で設定できるようにする

### ゴール文
ハーネスが `main` を直書きしている箇所を、環境変数 `HARNESS_BASE_BRANCH`（前後の空白を除いて空なら `main`）の値に置き換える。対象は `scripts/vcs_finish.sh`（GitHub REST の `base`・ホスティング無しのマージ案内）、`.claude/skills/plan/SKILL.md` 手順A-2 と `.claude/skills/design/SKILL.md` 手順1 の開始条件、`.claude/hooks/agent_write_guard.py` (b) の直接コミット拒否（ベースブランチと `main` の両方を拒否）、`scripts/purge_plan.sh --merged` のマージ済み判定（`<ベース>:vault/plans/…`）、`.claude/skills/run/SKILL.md` 手順7 の MCP 代替時の base と、`docs/vault-spec.md`・`docs/runbook.md`・`docs/install.md` の説明。既定値のままなら今の動作を変えない。`scripts/smoke.sh` に既定（main）と別名ベース（develop）の両方のケースを足す。

### 受け入れ基準の候補
- `scripts/vcs_finish.sh` の GitHub REST の経路3つが `base=<HARNESS_BASE_BRANCH の値、空なら main>` を渡し、`none` のマージ案内の取り込み先も同じ値になる。`grep -n 'base=main' scripts/vcs_finish.sh` が0件
- `HARNESS_BASE_BRANCH=develop` の時、`agent_write_guard.py` は `develop` 上と `main` 上の `git commit` を拒否し、`work/…` 上では許可する。未設定の時は従来どおり `main` 上だけを拒否する（`bash scripts/smoke.sh` の該当ケースが PASS）
- `HARNESS_BASE_BRANCH=develop` の時、`scripts/purge_plan.sh --merged --list` は `develop` の版の計画票で判定し、`main` の版は見ない（smoke の該当ケースが PASS）
- `.claude/skills/plan/SKILL.md` 手順A-2・`.claude/skills/design/SKILL.md` 手順1・`.claude/skills/run/SKILL.md` 手順7 の MCP 代替時の base が、固定の `main` ではなくベースブランチ（`HARNESS_BASE_BRANCH`、既定 `main`）を指す
- `docs/vault-spec.md` に `HARNESS_BASE_BRANCH` の意味・既定値・空白の扱い・影響する箇所が書かれ、`docs/install.md` に main 以外をベースにする導入先での設定方法（`.claude/settings.json` の `env` に書く例）が書かれている
- `bash scripts/smoke.sh` が終了コード0で、既定（main）と `HARNESS_BASE_BRANCH=develop` の両方のケースを含む（vcs_finish の `base=develop`、フック、purge_plan）

### 決定済み
- 値の読み方は、シェルでは前後の空白を除いて空なら `main`、Python（フック）では `os.environ.get("HARNESS_BASE_BRANCH", "").strip() or "main"`。値の形式（ブランチ名として正しいか）は検査しない
- フックの拒否メッセージには拒否したブランチ名を入れる（例：「develop への直接コミットはできません」）
- 引数ありの `vcs_finish.sh`（`gh pr create "$@"`・`glab mr create "$@"`）には base を足さない（従来どおり既定値を足さない）。GitLab の引数なしの経路は `--fill`/`--title` のままで、ターゲットブランチは指定しない（`glab` の既定＝リポジトリの既定ブランチに任せる）
- `transition.py`・`stop_gate.py`・`diff_gate.py` は変えない（ベースブランチ名を直接使っていない。`transition.py` の「main なら何も変えない」は `work/` 接頭辞の検査の結果であり、ベースの設定とは関係ない）
- `docs/vault-spec.md` 13節の「`main` から切る」「`main` にマージする」は「ベースブランチ（既定 `main`）」に言い換える。`docs/runbook.md` の「main の履歴」などの一般的な説明も同様にする。`README.md` の図の `orchestrator (main)` は「メインセッション」の意味なので変えない
- `.claude/agents/creator.md` の「`main` に直接コミットしない」は「ベースブランチ（既定 `main`）と `main` に直接コミットしない」に直す
- smoke の vcs_finish のケースは既存の偽 `gh`（引数を記録する方式）を使い、`HARNESS_BASE_BRANCH=develop` で `base=develop` が渡ることを確かめる。既存ケースの期待値（`base=main`）は変えない

### 依存
-

---

## フェーズ2 push 先と PR の head を `HARNESS_PUSH_BRANCH` で上書きできるようにする

### ゴール文
環境変数 `HARNESS_PUSH_BRANCH`（前後の空白を除いて空なら未設定）が設定されている時、`scripts/vcs_finish.sh` は GitHub・GitLab の経路で毎回 `git push -u origin HEAD:<値>` で push し、PR/MR の head（source branch）にその値を使う。`/plan`・`/design` の開始条件に「`HARNESS_PUSH_BRANCH` が設定され、現在のブランチがその値で、HEAD がローカルのベースブランチと同じコミットなら、ベース上とみなしてブランチを切る」を足す。`run`・`design` の MCP 代替時の head、`docs/` の説明（クラウドセッションでの使い方を含む）と `scripts/smoke.sh` のケースもそろえる。最後に決定事項を `docs/decisions.md` に取り出し、この設計文書を削除する。

### 受け入れ基準の候補
- `HARNESS_PUSH_BRANCH=ccr-x` の時、引数なしの `vcs_finish.sh`（GitHub）は `git push -u origin HEAD:ccr-x` を実行し、`gh api` に `head=ccr-x` を渡す。未設定の時は従来どおり（上流が無ければ現在のブランチ名で push し、head は現在のブランチ）（smoke の該当ケースが PASS）
- `HARNESS_PUSH_BRANCH` 設定時、GitLab の引数なしの経路は `glab mr create` に `--source-branch <値>` を足し、`none` の経路は値を見ない（smoke の該当ケースが PASS）
- `.claude/skills/plan/SKILL.md` 手順A-2 と `.claude/skills/design/SKILL.md` 手順1 に、`HARNESS_PUSH_BRANCH` のブランチ上で HEAD がベースブランチと同一コミットなら許可する条件と、その確認コマンド（`git rev-parse HEAD` と `git rev-parse <ベース>` の比較）が書かれ、違えば従来どおり止まると書かれている
- `.claude/skills/run/SKILL.md` 手順7・`.claude/skills/design/SKILL.md` 手順8 の MCP 代替時の head が「`HARNESS_PUSH_BRANCH` があればその値、無ければ現在のブランチ」になっている
- `docs/vault-spec.md` に `HARNESS_PUSH_BRANCH` の意味と `vcs_finish.sh` の push・head の動作が、`docs/runbook.md` にクラウドセッション（push 先が指定される環境）での使い方（`env HARNESS_PUSH_BRANCH=<指定ブランチ> …` で渡す）が書かれている
- `bash scripts/smoke.sh` が終了コード0
- 決定事項のうち docs に無いものを `docs/decisions.md` に追記し、設計文書（`vault/designs/D-20261010-base-branch-config.md`）を削除する（`test ! -e vault/designs/D-20261010-base-branch-config.md`）

### 決定済み
- push は上流の有無に関係なく毎回行う（指定ブランチはリモートに既にあることが多い）。`git push` が失敗したらその終了コードで終わり、PR は作らない。force は使わない（settings.json でも拒否）
- 引数ありの `vcs_finish.sh` でも push は `HEAD:<値>` で行う。PR 作成の引数（`--head` など）は足さない（引数には既定値を足さない従来の方針）
- ローカルのブランチ名（`work/<計画IDの英小文字>`）・`find_plan_id` の探し方・transition.py のブランチ検査は変えない。push 先だけが変わる
- 開始条件の比較対象はローカルの `<ベースブランチ>` の ref。それが無い時（`git rev-parse --verify <ベース>` が失敗）は止まる。`origin/<ベース>` との比較や fetch はしない
- 環境変数に無く、実行環境の指示で push 先が決められている時は、オーケストレーターがその値を `env HARNESS_PUSH_BRANCH=<指定ブランチ>` で開始条件の確認と `vcs_finish.sh` に渡す（スキルにこの一文を書く）
- smoke の push のケースは、一時ディレクトリに bare リポジトリを作って `origin` にし、push 後に `git -C <bare> rev-parse ccr-x` が作業ブランチの HEAD と一致することで確かめる。`gh` は既存の偽 `gh` を使う
- 設計文書の削除は creator がタスクの成果物として行う（成果物に `vault/designs/` を宣言する。差分ゲートの禁止対象ではない）。この設計文書を読む他のタスクの後に `after` で依存させて置く

### 依存
フェーズ1

---

## 今回やらないこと
- 専用の設定ファイル（`.claude/harness.env` など）の導入
- `HARNESS_PUSH_BRANCH` 上の直接コミットのフックでの拒否
- ベースブランチ名の形式検査（`git check-ref-format`）
- `origin/<ベース>` を fetch して開始条件を比べること
- GitLab のターゲットブランチ（`--target-branch`）を `HARNESS_BASE_BRANCH` で指定すること（必要になれば別途）
