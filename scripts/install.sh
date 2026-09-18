#!/usr/bin/env bash
# 他プロジェクトへハーネスを複製する。
# 使い方: bash scripts/install.sh <target-dir>
# 複製するもの: .claude/（settings.json, agents/, hooks/, skills/）、vault/（テンプレート・rules/ 雛形・役割定義の標準ルール・空の todo.md・空ディレクトリ）、scripts/smoke.sh、scripts/rules.sh
# 既存ファイルは上書きしない（.claude/settings.json と vault/todo.md が既にあれば残す）。
set -eu
if [ $# -ne 1 ]; then echo "usage: bash scripts/install.sh <target-dir>" >&2; exit 2; fi
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="$1"
mkdir -p "$DST"
DST="$(cd "$DST" && pwd)"

copy_if_absent() { # $1=src $2=dst
  if [ -e "$2" ]; then echo "skip  (exists) ${2#$DST/}"; else mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "copy  ${2#$DST/}"; fi
}

# .claude/
for f in $(cd "$SRC/.claude" && find . -type f ! -name 'settings.local.json' | sed 's|^\./||'); do
  copy_if_absent "$SRC/.claude/$f" "$DST/.claude/$f"
done
chmod +x "$DST"/.claude/hooks/*.py

# vault/（状態ファイルは初期状態で複製する）
for d in tasks plans verdicts log templates archive; do mkdir -p "$DST/vault/$d"; done
# vault/rules/ 配下は README・各役割ディレクトリの .gitkeep（雛形）と、役割定義の標準ルール4本を複製する。
# ドメイン固有のルール（コーディングルール・方式設計・テスト観点など）は複製・上書きの対象にしない。
# 標準ルールも copy_if_absent なので、インストール先で編集したものは上書きしない。
for f in tasks/.gitkeep plans/.gitkeep verdicts/.gitkeep archive/.gitkeep designs/.gitkeep templates/task.md templates/plan.md templates/rule.md templates/design.md rules/README.md rules/common/.gitkeep rules/creator/.gitkeep rules/verifier/.gitkeep rules/planner/.gitkeep rules/common/roles.md rules/creator/creator.md rules/verifier/verifier.md rules/planner/planner.md; do
  copy_if_absent "$SRC/vault/$f" "$DST/vault/$f"
done
if [ ! -e "$DST/vault/todo.md" ]; then
  cat > "$DST/vault/todo.md" <<'EOT'
# キュー

## ルール
- todo の一番上から1件だけ doing にする。doing は常に1件
- done にできるのは verdicts/<id>.json が PASS の時だけ
- 迷ったら blocked にして question を書く。勝手に決めない
- 状態を変えたら log/queue.md に1行追記する

## タスク
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|

## 計画
| id | status | title |
|---|---|---|
EOT
  echo "copy  vault/todo.md"
fi
if [ ! -e "$DST/vault/log/queue.md" ]; then
  printf '# キューログ（追記専用）\n\n形式：`- YYYY-MM-DD HH:MM T-0001 doing→review attempt=1 補足`\n\n' > "$DST/vault/log/queue.md"
  echo "copy  vault/log/queue.md"
fi

# scripts/smoke.sh、scripts/rules.sh、docs/vault-spec.md（エージェントが参照する正本）
copy_if_absent "$SRC/scripts/smoke.sh" "$DST/scripts/smoke.sh"
copy_if_absent "$SRC/scripts/rules.sh" "$DST/scripts/rules.sh"
copy_if_absent "$SRC/docs/vault-spec.md" "$DST/docs/vault-spec.md"

# CLAUDE.md（無ければ複製、あれば追記の案内）
if [ -e "$DST/CLAUDE.md" ]; then
  echo "note  CLAUDE.md は既にあります。$SRC/CLAUDE.md の内容を追記してください"
else
  copy_if_absent "$SRC/CLAUDE.md" "$DST/CLAUDE.md"
fi

echo
echo "done: $DST"
echo "next: cd \"$DST\" && bash scripts/smoke.sh && claude   # 一度対話起動してフォルダを信頼する"
