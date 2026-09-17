#!/usr/bin/env bash
# ルール解決スクリプト：役割名を受け取り、その役割に渡すべき vault/rules/ 配下の
# ファイルを決定的順序（common/ → 役割ディレクトリ、各ディレクトリ内はファイル名順）で
# 標準出力に列挙する。1行1パス（リポジトリルートからの相対パス）。
# 使い方: bash scripts/rules.sh <creator|verifier|planner>
set -u
export LC_ALL=C

usage() {
  echo "usage: bash scripts/rules.sh <creator|verifier|planner>" >&2
}

role="${1:-}"
case "$role" in
  creator|verifier|planner) ;;
  *) usage; exit 2 ;;
esac

if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  ROOT="$CLAUDE_PROJECT_DIR"
else
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

list_dir() { # $1 = vault/rules/ 直下のディレクトリ名
  local name="$1" dir="$ROOT/vault/rules/$1" f
  [ -d "$dir" ] || return 0
  shopt -s nullglob
  for f in "$dir"/*.md; do
    printf 'vault/rules/%s/%s\n' "$name" "$(basename "$f")"
  done
  shopt -u nullglob
}

list_dir common
list_dir "$role"
