#!/usr/bin/env bash
# 他プロジェクトへハーネスを複製する。
# 使い方: bash scripts/install.sh [--no-claude-md] <target-dir>
# 複製するもの: .claude/（settings.json, agents/, hooks/, skills/, ai-harness.md）、vault/（テンプレート・rules/ 雛形・役割定義の標準ルール・空の todo.md・空ディレクトリ）、scripts/smoke.sh、scripts/rules.sh、scripts/merge_claude_md.py
# 既存ファイルは上書きしない（.claude/settings.json と vault/todo.md が既にあれば残す）。
# 例外は CLAUDE.md で、既定では merge_claude_md.py がマーカー付きブロックだけをマージする（既存本文は残し、書き換え時はバックアップを作る）。
# --no-claude-md を付けると CLAUDE.md には触れず、既存があれば案内だけを出す。
set -eu
NO_CLAUDE_MD=0
ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-claude-md) NO_CLAUDE_MD=1 ;;
    -*) echo "usage: bash scripts/install.sh [--no-claude-md] <target-dir>" >&2; exit 2 ;;
    *) if [ -n "$ARGS" ]; then echo "usage: bash scripts/install.sh [--no-claude-md] <target-dir>" >&2; exit 2; fi; ARGS="$1" ;;
  esac
  shift
done
if [ -z "$ARGS" ]; then echo "usage: bash scripts/install.sh [--no-claude-md] <target-dir>" >&2; exit 2; fi
set -- "$ARGS"
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
copy_if_absent "$SRC/scripts/merge_claude_md.py" "$DST/scripts/merge_claude_md.py"
copy_if_absent "$SRC/docs/vault-spec.md" "$DST/docs/vault-spec.md"

# CLAUDE.md（既定はマーカー付きブロックのマージ。--no-claude-md なら従来どおり案内だけ）
if [ "$NO_CLAUDE_MD" -eq 1 ]; then
  if [ -e "$DST/CLAUDE.md" ]; then
    echo "note  CLAUDE.md は既にあります。$SRC/CLAUDE.md の内容を追記してください"
  else
    copy_if_absent "$SRC/CLAUDE.md" "$DST/CLAUDE.md"
  fi
else
  python3 "$SRC/scripts/merge_claude_md.py" "$SRC/CLAUDE.md" "$DST/CLAUDE.md"
fi

echo
echo "done: $DST"
if [ "$NO_CLAUDE_MD" -eq 0 ]; then
  echo "check: 既存の CLAUDE.md にハーネスと矛盾するルールが残っていないか確認してください（マージは追記するだけで、矛盾は解消しません）"
fi
echo "next: cd \"$DST\" && bash scripts/smoke.sh && claude   # 一度対話起動してフォルダを信頼する"
