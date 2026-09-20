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
複製されるものは `scripts/install.sh` 冒頭のコメントのとおり（`.claude/`（`ai-harness.md` を含む）、`vault/` のテンプレートと標準ルールと `vault/{plans,tasks,verdicts,log,designs,archive,templates,rules}` の空ディレクトリ、`scripts/smoke.sh`、`scripts/rules.sh`、`scripts/merge_claude_md.py`、`scripts/merge_settings_json.py`、`docs/vault-spec.md`、`CLAUDE.md`）。状態は `vault/plans/<計画ID>.md`（`/plan` が作る）が持つので、キューのファイルは配らない。既存ファイルは上書きしない。

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

既存ファイルは上書きしない。唯一の例外が `CLAUDE.md` で、ハーネスのルールを読み込む4行のブロックだけを既定でマージする（既存の本文はそのまま残る）。出力は次のとおり。

| 出力 | 意味 | やること |
|---|---|---|
| `create <path>/CLAUDE.md` | `CLAUDE.md` が無かったので作成した | そのまま使う |
| `merge <path>/CLAUDE.md` | 既存の `CLAUDE.md` の末尾にハーネスのブロックを追記した（`CLAUDE.md.bak-<日時>` を残す） | 既存のルールとハーネスの規律が矛盾していないか確認する |
| `update <path>/CLAUDE.md` | 既にあったハーネスのブロックを新しい内容に置き換えた（再インストール時。`CLAUDE.md.bak-<日時>` を残す） | そのまま使う |
| `skip <path>/CLAUDE.md` | 既に最新のブロックが入っているので何もしなかった | そのまま使う |
| `skip  (exists) ...` | そのファイルが既にあるので複製しなかった（標準ルール4本など） | 既存のものをそのまま使う。ハーネスに必要な設定が足りなければ手で追記する |

マージされるのは次の4行だけで、ルール本文は `.claude/ai-harness.md` にある（`@` で読み込まれる）。ハーネスを更新した時は `install.sh` を再実行すればブロックが `update` される。

```
<!-- ai-harness:begin v1 -->
# AI協働ハーネス 共通ルール
@.claude/ai-harness.md
<!-- ai-harness:end -->
```

`CLAUDE.md` に一切触れたくない場合は `--no-claude-md` を付ける。その場合は従来どおり `note  CLAUDE.md は既にあります。...` の案内が出るだけで、ハーネスのルールはメインコンテキストに載らない。

```bash
bash /path/to/ai-harness/scripts/install.sh --no-claude-md /path/to/your-project
```

**`.claude/settings.json` は自動マージされない。** 既にある場合は `skip  (exists)` と出るだけなので、ai-harness 側の `hooks`（Stop / PreToolUse / PostToolUse）と `permissions` を既存の設定に手で足すこと。ここが入っていないとフックが1つも働かない。

### 2. 既存のワークフローとの関係を確認する
ハーネスはファイルを追加するだけで、既存のビルド設定（ビルドスクリプト、CI、lint、テスト）を変更しない。

### 3. git 管理に入れる
```bash
git add vault/ .claude/ CLAUDE.md scripts/rules.sh scripts/smoke.sh docs/vault-spec.md && git commit -m "ai-harness を導入"
```
`vault/` は追跡するのを勧める。ai-harness 自身が `vault/` 全体（`plans/` / `tasks/` / `verdicts/` / `log/` / `designs/` / `archive/` / `rules/`）を git 管理しており、作業の履歴がそのまま残る。`.gitignore` に `.claude/settings.local.json` を追加しておく。

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
- **`.claude/settings.json`** は `scripts/merge_settings_json.py` が hooks の欠落エントリと `permissions.deny` の不足分だけを足す。インストール先で足した `permissions.allow` は変更しない
- マニフェストが無いインストール先（`--update` より前に入れたもの）では、既存ファイルはすべて `skip (edited)` になる。編集していないものは一度手で消してから `--update` すれば配られる

`merge_settings_json.py` は書き換える時だけ `.claude/settings.json.bak-<日時>` を残す。不要なら消してよい（`.gitignore` に `*.bak-*` を足しておくと楽）。

## インストール後の次の一歩
どちらのパターンでも、最初に打つのは `/plan <ゴール>` になる。
人が日々やること（ゴールを入れる・計画を承認する・blocked に答える・月次で片づける）は `docs/runbook.md` にまとまっている。
