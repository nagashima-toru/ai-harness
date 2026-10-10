# インストールガイド

ハーネスを自分のプロジェクトに入れる手順。用途によって2通りある。

- **パターン1：まっさらな環境にインストールする** — 空のディレクトリに入れて、そこから新しく作業を始める
- パターン2：既存リポジトリに追加する — アプリ開発中のリポジトリに AI 開発の機能を足す

## 前提
`claude`（Claude Code）、`git`、`python3` が使えること。
以下では ai-harness を clone 済みとし、そのパスを `/path/to/ai-harness` と書く。

```bash
git clone git@github.com:nagashima-toru/ai-harness.git /path/to/ai-harness
```

## パターン1: まっさらな環境にインストールする
新しいディレクトリをそのまま AI 作業用のリポジトリにする場合。

### 1. 空ディレクトリを作って移動する
```bash
mkdir -p ~/work/my-project && cd ~/work/my-project
```

### 2. git リポジトリにする
```bash
git init
```
ハーネスは状態をすべてファイルに置くので、`vault/` の履歴がそのまま作業の履歴になる。最初に `git init` しておく。

### 3. ハーネスを複製する
```bash
bash /path/to/ai-harness/scripts/install.sh .
```
複製されるものは `scripts/install.sh` 冒頭のコメントのとおり（`.claude/`（`ai-harness.md` を含む）、`vault/` のテンプレートと `vault/{plans,tasks,verdicts,log,designs,templates,rules}` の空ディレクトリ、`scripts/` 配下のスクリプト一式（`scripts/*.sh`・`scripts/*.py` を検索方式で配布する。`scripts/vcs_finish.sh` を含み、除外リストに載ったものだけを除く）、`docs/vault-spec.md`、`CLAUDE.md`（マーカーブロックだけ））。状態は `vault/plans/<計画ID>.md`（`/plan` が作る）が持つので、キューのファイルは配らない。既存ファイルは上書きしない。

あわせて `.claude/harness-manifest.json` が作られる。配ったハーネス本体ファイルの sha256 を記録したもので、次の「ハーネスを更新する」で使う。`.claude/settings.json` は複製ではなく `scripts/merge_settings_json.py` によるマージで用意される。

ハーネスのルール本文は `.claude/ai-harness.md` にあり、`CLAUDE.md` はそれを読み込むだけのマーカー付きブロック（4行）になっている。

### 4. `.gitignore` を作る
ai-harness と同じ4行を使う。

```bash
cat > .gitignore <<'EOF'
.DS_Store
__pycache__/
*.pyc
.claude/settings.local.json
EOF
```

### 5. 初期コミットする
```bash
git add -A && git commit -m "ai-harness を導入"
```
`vault/` も含めて全部コミットする。ai-harness 自身が `vault/` 全体を git 管理している前例に合わせる。

### 6. フォルダを信頼する
```bash
claude
```
その場で一度 `claude` を対話起動し、フォルダを信頼する。`.claude/settings.json` の許可設定は信頼後にしか効かない。

### 7. 動作を検証する
```bash
bash scripts/smoke.sh
```
フックが期待どおり働くかを確認する。

### 8. 最初のゴールを入れる
`/plan <ゴール>` を打つところから始める。

以降、ハーネス側が更新されたら `bash /path/to/ai-harness/scripts/install.sh --update .` で取り込む（「ハーネスを更新する（2回目以降）」を参照）。

## パターン2: 既存リポジトリに追加する
アプリ開発中のリポジトリに、AI 開発の機能だけを足す場合。

### 1. ハーネスを複製する
```bash
bash /path/to/ai-harness/scripts/install.sh /path/to/your-project
```
2回目以降（ハーネス側の更新を取り込む時）は `--update` を付ける（「ハーネスを更新する（2回目以降）」を参照）。

既存ファイルは上書きしない。唯一の例外が `CLAUDE.md` で、ハーネスのルールを読み込む4行のブロックだけを既定でマージする（既存の本文はそのまま残る）。マージに使うのはハーネス側の `CLAUDE.md` のマーカーブロックだけで、マーカーの外の行（ハーネス本体のリポジトリだけが読む `@docs/vision.md` など）は配らない。出力は次のとおり。

| 出力 | 意味 | やること |
|---|---|---|
| `create <path>/CLAUDE.md` | `CLAUDE.md` が無かったので作成した | そのまま使う |
| `merge <path>/CLAUDE.md` | 既存の `CLAUDE.md` の末尾にハーネスのブロックを追記した（`CLAUDE.md.bak-<日時>` を残す） | 既存のルールとハーネスの規律が矛盾していないか確認する |
| `update <path>/CLAUDE.md` | 既にあったハーネスのブロックを新しい内容に置き換えた（再インストール時。`CLAUDE.md.bak-<日時>` を残す） | そのまま使う |
| `skip <path>/CLAUDE.md` | 既に最新のブロックが入っているので何もしなかった | そのまま使う |
| `skip  (exists) ...` | そのファイルが既にあるので複製しなかった（`vault/rules/README.md` など） | 既存のものをそのまま使う。ハーネスに必要な設定が足りなければ手で追記する |

マージされるのは次の4行だけで、ルール本文は `.claude/ai-harness.md` にある（`@` で読み込まれる）。ハーネスを更新した時は `install.sh` を再実行すればブロックが `update` される。

```
<!-- ai-harness:begin v1 -->
# AI協働ハーネス 共通ルール
@.claude/ai-harness.md
<!-- ai-harness:end -->
```

`CLAUDE.md` に一切触れたくない場合は `--no-claude-md` を付ける。その場合は従来どおり `note  CLAUDE.md は既にあります。...` の案内が出るだけで、ハーネスのルールはメインコンテキストに載らない。なお、`--no-claude-md` を付けない時に導入先に `CLAUDE.md` が無い時はマーカーブロックだけで作る（出力は `create <path>/CLAUDE.md`）。

```bash
bash /path/to/ai-harness/scripts/install.sh --no-claude-md /path/to/your-project
```

**`.claude/settings.json` は `merge_settings_json.py` が hooks・`permissions.deny`・`worktree.baseRef` を自動でマージする。** `install.sh` は `--update` の有無や既存ファイルの有無にかかわらず、このマージャを常に呼ぶ。導入先に無ければ ai-harness 側の内容でそのまま作成し（`create`）、既にあれば足りない hooks・`permissions.deny`・`worktree.baseRef` だけを足す（`merge`。足すものが無ければ `skip`）。マージ内容の詳細は次節「ハーネスを更新する」を参照。

### 2. 既存のワークフローとの関係を確認する
ハーネスはファイルを追加するだけで、既存のビルド設定（ビルドスクリプト、CI、lint、テスト）を変更しない。

### 3. git 管理に入れる
```bash
git add vault/ .claude/ CLAUDE.md scripts/ docs/vault-spec.md && git commit -m "ai-harness を導入"
```
`vault/` は追跡するのを勧める。ai-harness 自身が `vault/` 全体（`plans/` / `tasks/` / `verdicts/` / `log/` / `designs/` / `rules/`）を git 管理しており、作業の履歴がそのまま残る。`.gitignore` に `.claude/settings.local.json` を追加しておく。

### 4. フォルダを信頼する
```bash
claude
```
パターン1と同じく、その場で一度 `claude` を対話起動してフォルダを信頼する。`.claude/settings.json` の許可設定は信頼後にしか効かない。

### 5. 動作を検証する
```bash
bash scripts/smoke.sh
```

## ハーネスを更新する（2回目以降）
どちらのパターンでも、インストール後にハーネス側が更新されたら `--update` で取り込む。

```bash
bash /path/to/ai-harness/scripts/install.sh --update .
```

フラグ無しの `install.sh` は既存ファイルを上書きしないため、2回目以降は新しいファイルが増えるだけで、フックやスキルの修正が届かない。`--update` は `.claude/harness-manifest.json` と照合して次のように振る舞う。

- **未編集のハーネス本体ファイル**（配った時のままのもの）は最新化され、`update <path>` と表示される
- **インストール先で編集したファイル**は上書きされず、`skip (edited) <path>` として一覧報告される。取り込みたい差分があれば手で当てる
- **`.claude/settings.json`** は `scripts/merge_settings_json.py` が hooks の欠落エントリと `permissions.deny` の不足分、`worktree.baseRef`（導入先に無ければ足す。別の値が入っていれば上書きせず `note` 行で案内するだけにとどめる）を足す。インストール先で足した `permissions.allow` は変更しない。不足があれば `note` 行で案内する（後述）
- 旧版で配った役割定義のルール6本は、未編集なら削除されて `remove <path>` と表示され、編集済みなら残って `note` の行で案内される（役割定義は `.claude/agents/` にある）
- マニフェストが無いインストール先（`--update` より前に入れたもの）では、既存ファイルはすべて `skip (edited)` になる。編集していないものは一度手で消してから `--update` すれば配られる

`merge_settings_json.py` は書き換える時だけ `.claude/settings.json.bak-<日時>` を残す。不要なら消してよい（`.gitignore` に `*.bak-*` を足しておくと楽）。

**`permissions.allow` の不足案内** ハーネス側 `.claude/settings.json` の `permissions.allow` のうち導入先に無いものがあれば、`merge_settings_json.py` が `note` 行で列挙する（`permissions.allow` 自体は変更しない）。許可が入らないままだと、対話実行では確認ダイアログが出て、無人実行（`claude -p`）では拒否される。必要なら note に出た項目を手で `permissions.allow` に足す。導入先に settings.json が無い（`create`）場合は丸ごと作られるので note は出ない。

```text
note .claude/settings.json: permissions.allow にハーネスが使う許可が 2 件足りない: Bash(git *), Bash(gh pr *)。対話実行では確認ダイアログが出て、無人実行（claude -p）では拒否される。必要なら手で足すこと（このスクリプトは permissions.allow を変更しない）
```

判定は文字列の完全一致で、パターンの包含関係は見ない。たとえば導入先に `Bash(git:*)` があっても `Bash(git *)` は不足として出る。またスクリプトは利用者の個人設定を含め `~/.claude/settings.json` は読まない（そこで許可していれば実際は確認が出ないこともある）。

## サンドボックスを有効にする（任意）
Claude Code のサンドボックスは、Bash とその子プロセス（`python3`・`bash -c` を含む）の書き込みと通信を OS で制限する。ハーネスは使わなくても同じに動き、ハーネス本体（ai-harness）では使っていない（理由は `docs/vault-spec.md` 12節の「サンドボックス（使っていない）」）。導入先で、Bash の書き込みと通信を OS で絞りたい時に使う任意の追加の守り。

サンドボックスは任意の追加の守りで、ハーネスはサンドボックス無しでも同じに動く（フック・`permissions`・`agent_write_guard.py` は変わらない）。使える前提は、macOS はそのまま、Linux と WSL2 は `bubblewrap` と `socat` が要ること（導入先のパッケージマネージャで入れる。コマンドはディストリビューションごとに違う）。使えるかどうかは Claude Code の `/sandbox` で確かめる。

**導入先には既定では入れない** 新規導入でも既存でも、`install.sh`（`merge_settings_json.py`）は導入先の `.claude/settings.json` に `sandbox` を足さない。有効にしたい時は、導入先の `.claude/settings.json` に手で足す。

```json
{
  "sandbox": {
    "enabled": true,
    "allowUnsandboxedCommands": false,
    "network": {
      "allowedDomains": [
        "github.com",
        "*.github.com",
        "*.githubusercontent.com"
      ]
    }
  }
}
```

- `allowedDomains` の `github.com`・`*.github.com`・`*.githubusercontent.com` は、`gh` や `git` が GitHub に通信するために許す
- Anthropic の API のドメインは入れない。入れ子の `claude` をサンドボックスの中で動かさないため。プロジェクトで必要な通信先（パッケージのレジストリなど）があれば `allowedDomains` に足す

**既知の制約**

- ハーネス自身（`.claude/`）を変える作業には向かない：サンドボックスは `.claude/` の下（`settings.json`・`skills/`・`agents/` など）と `.git` への Bash の書き込みを止めるので、ハーネスのフック・スキル・設定を変える計画では、creator の編集・worktree の後始末・PR の作成が詰まる。そうした作業をするリポジトリ（ハーネス本体など）では有効にしない
- Windows は WSL2 だけで使える（WSL1・ネイティブの Windows では使えない）
- `gh` の認証：キーチェーンなど OS の資格情報を読めず、サンドボックスの中で `gh` が認証に失敗することがある
- ssh の remote：通信先の制限は HTTP(S) の通信が対象で、`git@github.com:` の形の remote への ssh の push は通らないことがある。その時は https の remote にするか、人がサンドボックスの外で push する
- `failIfUnavailable` を設定していないので、サンドボックスが使えない環境では制限なしで起動する。その時はフックと `permissions` だけが守りになる

設定はセッションの開始時に読まれるので、足した後は Claude Code を起動し直し、`/sandbox` で有効になっていることを確かめる。

`uninstall.sh` が取り除くのは足したもの（hooks など）だけで、手で足した `sandbox` は残る。不要になったら人が消す。

## アンインストール
複製したハーネスを取り除きたい時は `scripts/uninstall.sh`（`install.sh` の対になるスクリプト）を使う。

```bash
bash scripts/uninstall.sh /path/to/your-project
```

`.claude/harness-manifest.json` と照合し、記録済みハッシュが現状と一致する（＝未編集の）ハーネス本体ファイルだけを削除する。出力は `install.sh` の `copy`/`skip (exists)`/`skip (edited)` と対称で、次の3種類になる。

| 出力 | 意味 | やること |
|---|---|---|
| `remove <path>` | 未編集のハーネス本体ファイルだったので自動で消した | 何もしなくてよい |
| `skip (edited) <path>` | インストール後に編集済みだったので残した（利用者が手を入れたものは消さない） | 不要なら自分で消す |
| `note ...` | 自動処理の対象外・案内のみ（`vault/` の利用者資産や `settings.json` の手動確認案内など） | note の内容に従う |

`CLAUDE.md` は `scripts/unmerge_claude_md.py` が処理する。ハーネスのマーカーブロック（`<!-- ai-harness:begin ... -->` 〜 `<!-- ai-harness:end -->`）だけを取り除き、他の本文には触れない。ブロックを除いた残りが空白だけならファイルごと削除し、本文が残っていればブロックだけ除去してファイルは残す（`remove`/`delete` の時だけ `CLAUDE.md.bak-<日時>` を残す）。

`.claude/settings.json` は `.claude/harness-manifest.json` の `settings_src` キーの内容をもとに `scripts/unmerge_settings_json.py` が処理する。`merge_settings_json.py` が足した hooks の command と `permissions.deny` の項目だけを取り除き、利用者が追加した `permissions.allow` やその他の項目には触れない。**この一致判定は command / deny 文字列の完全一致でしか行わない**ため、利用者がハーネスと偶然同じ文字列を独自に `.claude/settings.json` に追加していた場合、区別できずに一緒に消える可能性がある。これは仕様上の限界として許容している。また、`settings_src` キーが無い古いマニフェスト（`--update` を使う前に入れたインストール）では `settings.json` の自動処理そのものをスキップし、案内だけを出す。その場合は `.claude/settings.json` を開き、`hooks` と `permissions.deny` からハーネス由来のエントリ（`ai-harness.md` の `## スキル`・フック節や `docs/vault-spec.md` を見比べる）を手で見つけて削除する。`merge_settings_json.py` が足した `worktree.baseRef` は `scripts/unmerge_settings_json.py` の対象外で、uninstall しても取り除かれず導入先に残る。不要なら `.claude/settings.json` を開いて手で削除する。

`vault/` の利用者資産（`plans`/`tasks`/`verdicts`/`log`/`designs` と、`vault/rules/` のルール）には一切触れない。これらは計画・タスク・検証結果・作業ログという利用者自身の作業成果であり、ハーネスを外しても消さずに残す。

## インストール後の次の一歩
どちらのパターンでも、最初に打つのは `/plan <ゴール>` になる。
人が日々やること（ゴールを入れる・blocked に答える・PR をマージする・月次で片づける）は `docs/runbook.md` にまとまっている。
