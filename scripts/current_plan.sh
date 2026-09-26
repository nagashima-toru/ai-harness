#!/usr/bin/env bash
# vault/plans/*.md の frontmatter を見て、status: approved の計画票の計画IDだけを
# 1行1件、ファイル名順で標準出力に出す。
# frontmatter の判定規則は .claude/hooks/plan_guard.py の plan_id_and_status と同じ：
# ファイルの1行目が厳密に "---" で、その次に現れる "---" 行までの間だけを frontmatter
# として扱う。frontmatter を閉じる "---" 行より後（本文）は一切見ない。
# id が無ければファイル名（.md を除いたもの）を使う。
# 使い方: bash scripts/current_plan.sh
set -u
export LC_ALL=C

if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
else
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

plans_dir="$ROOT/vault/plans"
[ -d "$plans_dir" ] || exit 0

shopt -s nullglob
for f in "$plans_dir"/*.md; do
  base="$(basename "$f")"
  fallback="${base%.md}"
  awk -v fallback="$fallback" '
    {
      sub(/\r$/, "")
    }
    NR == 1 {
      if ($0 != "---") { exit 0 }
      next
    }
    {
      if ($0 == "---") { exit 0 }
      if (!gotid) {
        line = $0
        if (line ~ /^id:[ \t]*[^ \t]+[ \t]*$/) {
          sub(/^id:[ \t]*/, "", line)
          sub(/[ \t]*$/, "", line)
          id = line
          gotid = 1
        }
      }
      if (!gotstatus) {
        line = $0
        if (line ~ /^status:[ \t]*[^ \t]+[ \t]*$/) {
          sub(/^status:[ \t]*/, "", line)
          sub(/[ \t]*$/, "", line)
          status = line
          gotstatus = 1
        }
      }
      next
    }
    END {
      if (status == "approved") {
        if (gotid) { print id } else { print fallback }
      }
    }
  ' "$f"
done
shopt -u nullglob
exit 0
