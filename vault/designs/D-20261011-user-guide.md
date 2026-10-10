---
id: D-20261011-user-guide
---
# ゴール
利用者（ハーネスを使う人）の視点で足りていないガイドを整える。指定できる環境変数（`HARNESS_*`）を1か所に一覧化して意味・既定値・使う場面が分かるようにし、やりたいこと別に引ける入口を作り、runbook を人向けの内容に整理する。

## 決定事項
人に聞いて確定した回答。以降のフェーズはこれを前提にする。1件1行。

| 決めたこと | なぜ |
|---|---|
| 新しく `docs/configuration.md`（環境変数リファレンス）と `docs/guide.md`（やりたいこと別の入口）の2ファイルを作り、`README.md` から両方へリンクする | 人の選択。一覧（引く場所）と入口（探す場所）を分け、既存の install・runbook の手順は重ねて書かずにリンクで辿らせる |
| 2ファイルは導入先に配らない（`scripts/install.sh` の配布対象に足さない）。ai-harness リポジトリで読む | 人の選択。`docs/install.md`・`docs/runbook.md` と同じ扱い。導入先の docs を増やさない（原則8） |
| 一覧とコードのずれは `scripts/smoke.sh` で検査する。表は手で書き、`scripts/`・`.claude/` に出てくる `HARNESS_*` がすべて表にあること、表の変数がすべてコードに出てくることを確かめる | 人の選択。自動生成の仕組みを増やさず、変数を足した時の書き忘れだけを機械で止める（原則2） |
| 範囲は、環境変数リファレンス・やりたいこと別の入口・runbook 全体の人向け整理まで。`settings.json` の権限やスキル引数のリファレンス化は含めない | 人の選択 |
| 既定値は「未設定の時に実際に使われる値」をコードから書き、経路で違うものはその旨を書く（例：`HARNESS_STRICT_STOP` は Stop フック単体では `0`、`scripts/run_unattended.py` 経由では `1` を入れて渡す） | 人の要望「各変数のデフォルト値も分かるようにする」。値が1つに決まらないものを1つに書くと誤る |
| runbook はエージェントが内部でやること（transition.py が何を書くか等）を本文に持たない。仕様は `docs/vault-spec.md`、手順はスキル（`.claude/skills/*/SKILL.md`）が正本で、runbook はそこへリンクする。runbook にしか無い内部仕様は削らずに `docs/vault-spec.md` へ移す | 人の選択「runbook 全体の整理」。runbook を「人が日々やること」に絞り、仕様の二重持ちをやめる |

## 依存関係
- フェーズ1 → フェーズ2 → フェーズ3（直列）
  - フェーズ2の入口はフェーズ1のリファレンスへリンクする
  - フェーズ3の runbook 整理は、フェーズ2の入口からのリンク先（runbook の節）を変えるので、入口を先に作って一緒に直す

---

## フェーズ1 環境変数リファレンス `docs/configuration.md` を作る

### ゴール文
利用者が指定できる環境変数（`HARNESS_*`）を `docs/configuration.md` に1つの表で一覧化する。各変数について、意味・既定値（未設定の時に実際に使われる値。経路で違う時はその旨）・読むもの（スクリプト・フック・スキル）・使う場面・詳しい説明へのリンクを書く。run が内部で渡すだけの変数（`HARNESS_PR_BODY_FILE`・`HARNESS_PR_TITLE`）は利用者が設定するものと分けて載せる。`README.md` からリンクし、`scripts/smoke.sh` に表とコードの変数の一致を確かめるケースを足す。

### 受け入れ基準の候補
- `docs/configuration.md` があり、表に今の11変数（`HARNESS_BASE_BRANCH`・`HARNESS_PUSH_BRANCH`・`HARNESS_MAX_ATTEMPTS`・`HARNESS_MAX_PARALLEL`・`HARNESS_CREATOR_MODEL`・`HARNESS_STRICT_STOP`・`HARNESS_VCS_HOST`・`HARNESS_RUN_CMD`・`HARNESS_RUN_TIMEOUT`・`HARNESS_PR_BODY_FILE`・`HARNESS_PR_TITLE`）がすべて1行ずつある
- 表の各行に「既定値」の列があり、値がコードの実装と一致する（決定済みの既定値の一覧と照合する）
- `README.md` に `docs/configuration.md` へのリンクがある（`grep -c 'docs/configuration.md' README.md` が1以上）
- `bash scripts/smoke.sh` に、`scripts/`・`.claude/` に出てくる `HARNESS_[A-Z_]+` の集合と `docs/configuration.md` の表の変数の集合が一致することを確かめるケースがあり、ok になる
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0`
- `scripts/install.sh` の配布対象は変えない（`grep -c 'configuration.md' scripts/install.sh` が0）

### 決定済み
- 表の列は「変数・意味・既定値・読むもの・使う場面・詳しく」の6列。「詳しく」は既存の説明（`docs/vault-spec.md`・`docs/runbook.md`・`docs/install.md` の節）へのリンク
- 既定値（今のコードから調べたもの。作成時にコードを読んで再確認する）：
  - `HARNESS_BASE_BRANCH`：`main`（前後の空白を除いて空なら `main`）
  - `HARNESS_PUSH_BRANCH`：未設定（現在のブランチに push し、head も現在のブランチ）
  - `HARNESS_MAX_ATTEMPTS`：`3`
  - `HARNESS_MAX_PARALLEL`：`3`。スクリプトは読まず、run スキル（オーケストレーター）が読む
  - `HARNESS_CREATOR_MODEL`：未設定（`.claude/agents/creator.md` の frontmatter の `model`）
  - `HARNESS_STRICT_STOP`：Stop フック単体では `0`。`scripts/run_unattended.py` は未設定なら `1` を入れて子に渡す
  - `HARNESS_VCS_HOST`：`auto`（origin の URL から github / gitlab / none を判定）
  - `HARNESS_RUN_CMD`：`claude -p "/run"`
  - `HARNESS_RUN_TIMEOUT`：`3600`（秒）
  - `HARNESS_PR_BODY_FILE`・`HARNESS_PR_TITLE`：未設定。run 手順7が `vcs_finish.sh` に渡す内部用。利用者は通常設定しない
- 表の上に、設定のしかた（シェルで `export`／1回だけ `env VAR=値 …`／恒久的には `.claude/settings.json` の `env`）を短く書く。起動後に変えても run の Bash に効かない場合があり、変えたら起動し直すことも書く（`docs/runbook.md` 8節と同じ注意）
- smoke の照合は、`scripts/smoke.sh` 自身・`vault/`・`docs/` を除いた `scripts/`・`.claude/` を対象に `grep -rhoE 'HARNESS_[A-Z_]+'` で集め、`docs/configuration.md` の表の1列目のバッククォート内の変数と比べる。差があれば差の変数名を出して fail
- 既存文書の説明は消さない（フェーズ3で runbook を整理する時に、重なる説明をリンクに置き換える）
- `docs/configuration.md` は smoke の `(ref-1)` の対象にする（バッククォート内のパスが実在すること）

### 依存
-

---

## フェーズ2 やりたいこと別の入口 `docs/guide.md` を作る

### ゴール文
利用者がやりたいことから必要な手順・設定に辿り着ける入口を `docs/guide.md` に作る。各項目は「やりたいこと」「すること（コマンドや設定の最小例）」「詳しく（`docs/install.md`・`docs/runbook.md`・`docs/configuration.md` の節へのリンク）」の形にする。`README.md` からリンクする。

### 受け入れ基準の候補
- `docs/guide.md` があり、決定済みに挙げた項目がすべて見出しとしてある（項目ごとに `grep -c` で確かめる）
- 各項目に「詳しく」のリンクが1つ以上あり、リンク先のファイルが実在する（smoke の `(ref-1)` が ok）
- 環境変数を使う項目は、`docs/configuration.md` の該当変数へのリンクか変数名を含む
- `README.md` に `docs/guide.md` へのリンクがある
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0`

### 決定済み
- 載せる項目（見出しの文言は作成時に決めてよいが、次の内容をすべて含める）：
  - 初めて使う（インストールして最初の PR まで）
  - 大きなゴールを設計してから進める（`/design`）
  - main 以外（develop など）をベースにする（`HARNESS_BASE_BRANCH`）
  - クラウドセッション（push 先が指定される環境）で使う：エージェントに何を頼むか、`HARNESS_PUSH_BRANCH` で指定ブランチに push する方法と、許可して `work/…` に push する方法の違い（PR の head が変わる）
  - 安いモデルで creator を回す（`HARNESS_CREATOR_MODEL`）
  - 無人で回す（`scripts/run_unattended.py`、`HARNESS_RUN_TIMEOUT` など）
  - blocked に答えて再開する（`/plan unblock`）
  - 再試行の上限・並列数を変える（`HARNESS_MAX_ATTEMPTS`・`HARNESS_MAX_PARALLEL`）
  - ルールを足す（`vault/rules/`）
  - ハーネスを更新する・取り外す
  - マージ済みの計画を片づける（`scripts/purge_plan.sh --merged`）
- 手順の本文は重ねて書かない。最小例（1〜3行）だけ載せ、詳細はリンク先に任せる
- フェーズ1の `docs/configuration.md` は main にある前提でリンクしてよい

### 依存
フェーズ1

---

## フェーズ3 runbook を人向けに整理する（最終フェーズ）

### ゴール文
`docs/runbook.md` を「人が日々やること」に絞る。エージェントが内部でやること（transition.py・スキルの手順の中身など）の説明は、`docs/vault-spec.md` やスキルに同じ内容があれば runbook から削ってリンクに置き換え、runbook にしか無い内部仕様は `docs/vault-spec.md` に移す。環境変数の説明は `docs/configuration.md` へのリンクにする。古くなった記述（例：「`/run` は1件処理して報告」）を今の動作に直す。`docs/guide.md` のリンク先の節がずれたら直す。最後に決定事項を `docs/decisions.md` に取り出し、この設計文書を削除する。

### 受け入れ基準の候補
- `docs/runbook.md` の各節が「人が打つコマンド・人が判断すること・人が見る場所」を本文にし、エージェントの内部動作は1〜2行の要約とリンクだけになっている（作成時に節ごとの方針を進捗に残し、検証は節ごとに読んで確かめる）
- runbook から削った内部仕様が `docs/vault-spec.md` かスキルに存在する（削った記述ごとに移し先を進捗に書き、`grep` で確かめる）
- `docs/runbook.md` の環境変数の説明が `docs/configuration.md` へのリンクに置き換わっている（`grep -c 'configuration.md' docs/runbook.md` が1以上）
- `docs/guide.md` のリンク先の runbook の節が実在する
- `bash scripts/smoke.sh 2>&1 | tail -1` が `fail=0`
- 決定事項のうち docs に無いものを `docs/decisions.md` に追記し、設計文書を削除する（`test ! -e vault/designs/D-20261011-user-guide.md`）

### 決定済み
- runbook の節番号（0〜10）は変えてよい。変えたら `docs/guide.md`・`README.md`・他文書からのリンクと「`docs/runbook.md` の N 節」という参照をすべて直す（`grep -rn 'runbook' docs README.md .claude` で洗う）
- 削る基準：同じ内容が `docs/vault-spec.md` かスキルにある時だけ削ってリンクにする。無ければ `docs/vault-spec.md` の該当節に移す（情報を失わない）
- `docs/install.md` は今回整理しない（インストール手順として人向けにまとまっているため）
- 設計文書の削除は creator がタスクの成果物として行う（成果物に `vault/designs/` を宣言する。差分ゲートの禁止対象ではない）。この設計文書を読む他のタスクの後に `after` で依存させて置く
- 1フェーズが7タスクを超えそうなら、runbook の節を前半・後半に分けたタスクにする

### 依存
フェーズ2

---

## 今回やらないこと
- `.claude/settings.json` の権限設定やスキル引数のリファレンス化
- 環境変数リファレンスの自動生成
- `docs/configuration.md`・`docs/guide.md` の導入先への配布
- `docs/install.md` の構成の見直し
- 環境変数の追加・名前の変更・既定値の変更（今の動作を書くだけ）
