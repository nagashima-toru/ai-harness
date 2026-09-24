#!/usr/bin/env bash
# 他プロジェクトへ複製したハーネスを取り除く（install.sh の対）。
# 使い方: bash scripts/uninstall.sh <target-dir>
# .claude/harness-manifest.json と照合し、記録済みハッシュが現状と一致する（＝未編集の）
# ハーネス本体ファイルだけを削除する。編集済みのファイルはスキップして報告する。
# CLAUDE.md は scripts/unmerge_claude_md.py に、.claude/settings.json は
# .claude/harness-manifest.json の settings_src キーの内容を一時ファイルに書き出して
# scripts/unmerge_settings_json.py に委譲する（このスクリプト自身は CLAUDE.md や
# settings.json を直接パースしない）。settings_src キーが無ければ settings.json の
# 自動処理はスキップし、案内だけを出す（エラー終了はしない）。
# vault/ の利用者資産（plans/tasks/verdicts/log/designs/archive、標準4本以外の rules/）と、
# vault/plans・vault/tasks・vault/verdicts・vault/log 自体には一切触れない。
# 空になった .claude/ や vault/rules/<role>/ 等のディレクトリ自体は削除しない（ファイル削除のみ）。
USAGE="usage: bash scripts/uninstall.sh <target-dir>"
set -eu
if [ $# -ne 1 ]; then echo "$USAGE" >&2; exit 2; fi
TARGET_ARG="$1"
SRC="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$TARGET_ARG" ]; then
  echo "uninstall: target directory not found: $TARGET_ARG" >&2
  exit 1
fi
TARGET="$(cd "$TARGET_ARG" && pwd)"

MANIFEST_FILE="$TARGET/.claude/harness-manifest.json"
if [ ! -f "$MANIFEST_FILE" ]; then
  echo "uninstall: .claude/harness-manifest.json が見つかりません: $TARGET" >&2
  exit 1
fi

# マニフェストに記録されたファイルのうち、現状ハッシュが記録値と一致するものだけ削除する。
# 記録はあるが現状ファイルが既に無いものは黙って無視する（報告しない）。
python3 -c '
import hashlib, json, os, sys
target, manifest = sys.argv[1:3]
with open(manifest, encoding="utf-8") as fh:
    data = json.load(fh)
files = data.get("files") or {}
def sha(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()
for rel in sorted(files):
    p = os.path.join(target, rel)
    if not os.path.isfile(p):
        continue
    if sha(p) == files[rel]:
        os.remove(p)
        print("remove " + rel)
    else:
        print("skip (edited) " + rel)
' "$TARGET" "$MANIFEST_FILE"

# CLAUDE.md（マーカーブロックのみ除去。他の本文には触れない）
python3 "$SRC/scripts/unmerge_claude_md.py" "$TARGET/CLAUDE.md"

# .claude/settings.json（settings_src を一時ファイルへ書き出して unmerge_settings_json.py に渡す）
SETTINGS_SRC_TMP="$(mktemp)"
trap 'rm -f "$SETTINGS_SRC_TMP"' EXIT
if python3 -c '
import json, sys
manifest, out = sys.argv[1:3]
with open(manifest, encoding="utf-8") as fh:
    data = json.load(fh)
src = data.get("settings_src")
if src is None:
    sys.exit(1)
with open(out, "w", encoding="utf-8") as fh:
    json.dump(src, fh, ensure_ascii=False)
' "$MANIFEST_FILE" "$SETTINGS_SRC_TMP"; then
  python3 "$SRC/scripts/unmerge_settings_json.py" "$SETTINGS_SRC_TMP" "$TARGET/.claude/settings.json"
else
  echo "note  .claude/settings.json は手動確認してください（docs/install.md 参照）"
fi

echo "note  vault/ の利用者資産（plans/tasks/verdicts/log/designs/archive・標準4本以外の rules/）には触れていません"

# マニフェスト自体（利用者資産ではなくハーネスの記帳ファイルなので最後に消す）
rm -f "$MANIFEST_FILE"
echo "remove .claude/harness-manifest.json"
