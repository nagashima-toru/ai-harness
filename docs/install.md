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
複製されるものは `scripts/install.sh` 冒頭のコメントのとおり（`.claude/`、`vault/` のテンプレートと標準ルールと空の `todo.md`、`scripts/smoke.sh`、`scripts/rules.sh`、`docs/vault-spec.md`、`CLAUDE.md`）。既存ファイルは上書きしない。

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

## パターン2: 既存リポジトリに追加する
アプリ開発中のリポジトリに、AI 開発の機能だけを足す場合。

### 1. ハーネスを複製する
```bash
bash /path/to/ai-harness/scripts/install.sh /path/to/your-project
```
`scripts/install.sh` は既存ファイルを上書きしない。出力に次の2種類が出る。

| 出力 | 意味 | やること |
|---|---|---|
| `note  CLAUDE.md は既にあります。...` | 既存の `CLAUDE.md` を残した（複製していない） | ai-harness の `CLAUDE.md` の内容を、既存の `CLAUDE.md` に自分で追記する |
| `skip  (exists) ...` | そのファイルが既にあるので複製しなかった（`.claude/settings.json`、`vault/todo.md` など） | 既存のものをそのまま使う。ハーネスに必要な設定が足りなければ手で追記する |

`.claude/settings.json` が既にある場合は、ai-harness 側の `hooks`（Stop / PreToolUse / PostToolUse）と `permissions` を既存の設定にマージする。ここが入っていないとフックが働かない。

### 2. 既存のワークフローとの関係を確認する
ハーネスはファイルを追加するだけで、既存のビルド設定（ビルドスクリプト、CI、lint、テスト）を変更しない。

### 3. git 管理に入れる
```bash
git add vault/ .claude/ CLAUDE.md scripts/rules.sh scripts/smoke.sh docs/vault-spec.md && git commit -m "ai-harness を導入"
```
`vault/` は追跡するのを勧める。ai-harness 自身が `vault/` 全体（`todo.md` / `tasks/` / `plans/` / `verdicts/` / `log/` / `archive/` / `rules/`）を git 管理しており、作業の履歴がそのまま残る。`.gitignore` に `.claude/settings.local.json` を追加しておく。

### 4. フォルダを信頼する
```bash
claude
```
パターン1と同じく、その場で一度 `claude` を対話起動してフォルダを信頼する。`.claude/settings.json` の許可設定は信頼後にしか効かない。

### 5. 動作を検証する
```bash
bash scripts/smoke.sh
```

## インストール後の次の一歩
どちらのパターンでも、最初に打つのは `/plan <ゴール>` になる。
人が日々やること（ゴールを入れる・計画を承認する・blocked に答える・月次で片づける）は `docs/runbook.md` にまとまっている。
