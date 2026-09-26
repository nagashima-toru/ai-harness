#!/usr/bin/env bash
# 他プロジェクトへハーネスを複製する。
# 使い方: bash scripts/install.sh [--update] [--no-claude-md] <target-dir>
# 複製するもの: .claude/（agents/, hooks/, skills/, ai-harness.md）、vault/（テンプレート・rules/ 雛形・役割定義の標準ルール・空ディレクトリ）、scripts/*.sh・scripts/*.py（scripts/ 直下を検索。除外リスト SCRIPTS_EXCLUDE にあるものは除く）、docs/vault-spec.md
# 状態は vault/plans/<計画ID>.md が持つ（キューは無い）。既存ファイルは上書きしない。
# .claude/settings.json は複製せず、merge_settings_json.py が hooks の欠落エントリと
# permissions.deny の不足分、worktree.baseRef（導入先に無ければ足す。別の値が入っていれば
# 上書きせず note で案内する）を足す（インストール先が足した permissions.allow は消さない）。
# 複製の最後に .claude/harness-manifest.json を書く。記録するのは「この install で配った内容」＝
# src 側の実ファイルの sha256 であり、dst の現状ではない（dst を記録すると、利用者が編集済みの
# ファイルが「未編集」と誤判定され、次の更新で編集が黙って上書きされるため）。
# 例外は CLAUDE.md で、既定では merge_claude_md.py がマーカー付きブロックだけをマージする（既存本文は残し、書き換え時はバックアップを作る）。
# --no-claude-md を付けると CLAUDE.md には触れず、既存があれば案内だけを出す。
# --update を付けると、マニフェストと照合してハーネス本体を更新する。dst のハッシュがマニフェストと
# 一致（＝配った時のまま）なら上書きし、一致しなければ利用者が編集したとみなしてスキップし報告する。
USAGE="usage: bash scripts/install.sh [--update] [--no-claude-md] <target-dir>"
set -eu
NO_CLAUDE_MD=0
UPDATE=0
ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-claude-md) NO_CLAUDE_MD=1 ;;
    --update) UPDATE=1 ;;
    -*) echo "$USAGE" >&2; exit 2 ;;
    *) if [ -n "$ARGS" ]; then echo "$USAGE" >&2; exit 2; fi; ARGS="$1" ;;
  esac
  shift
done
if [ -z "$ARGS" ]; then echo "$USAGE" >&2; exit 2; fi
set -- "$ARGS"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="$1"
mkdir -p "$DST"
DST="$(cd "$DST" && pwd)"

MANIFEST_FILE="$DST/.claude/harness-manifest.json"
HANDLED_LIST="$(mktemp)"   # --update で処理済みの相対パス（通常の複製から除外する）
SKIPPED_LIST="$(mktemp)"   # 編集済みとみなしてスキップした相対パス（マニフェストを据え置く）
trap 'rm -f "$HANDLED_LIST" "$SKIPPED_LIST"' EXIT

copy_if_absent() { # $1=src $2=dst
  rel="${2#$DST/}"
  if [ -s "$HANDLED_LIST" ] && grep -Fxq "$rel" "$HANDLED_LIST"; then return 0; fi
  if [ -e "$2" ]; then echo "skip  (exists) $rel"; else mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "copy  $rel"; fi
}

# scripts/ 直下で配らないファイル名（スペース区切り、当面は空）。manifest_paths() と
# 通常複製の両方がこの変数を見る。
SCRIPTS_EXCLUDE=""

scripts_list() { # SRC の scripts/ 直下にある *.sh・*.py を SCRIPTS_EXCLUDE を除いて列挙する
  (
    cd "$SRC" || exit 0
    find scripts -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null
  ) | while read -r p; do
    name="$(basename "$p")"
    keep=1
    for ex in $SCRIPTS_EXCLUDE; do
      [ "$name" = "$ex" ] && keep=0
    done
    [ "$keep" -eq 1 ] && echo "$p"
  done
}

# ハーネス本体として配る（＝マニフェストに記録し、--update の対象にする）パスの列挙。
# 利用者の資産（vault/plans, tasks, verdicts, log, archive, designs の中身、標準4本以外の
# vault/rules/、settings.local.json）は含めない。.claude/settings.json は専用マージャの対象。
manifest_paths() { # SRC からの相対パスを1行1つで列挙する（存在するものだけ）
  {
    (
      cd "$SRC" || exit 0
      find .claude/hooks -name '*.py' -type f 2>/dev/null
      find .claude/agents -name '*.md' -type f 2>/dev/null
      find .claude/skills -name 'SKILL.md' -type f 2>/dev/null
      find vault/templates -name '*.md' -type f 2>/dev/null
      for p in .claude/ai-harness.md docs/vault-spec.md \
               vault/rules/README.md vault/rules/common/roles.md \
               vault/rules/common/git.md vault/rules/creator/creator.md \
               vault/rules/creator/git-workflow.md vault/rules/verifier/verifier.md \
               vault/rules/planner/planner.md; do
        [ -f "$p" ] && echo "$p"
      done
    ) | sed 's|^\./||'
    scripts_list
  } | sort -u
}

# --update：マニフェストと照合して、未編集なら上書き・編集済みならスキップして報告する。
# 通常の複製ループより先に走らせ、ここで処理したパスは copy_if_absent の対象から外す。
if [ "$UPDATE" -eq 1 ]; then
  UPDATE_LIST="$(mktemp)"
  manifest_paths > "$UPDATE_LIST"
  python3 -c '
import hashlib, json, os, shutil, sys
src, dst, manifest, listfile, handled, skipped = sys.argv[1:7]
old = {}
if os.path.isfile(manifest):
    try:
        with open(manifest, encoding="utf-8") as fh:
            old = json.load(fh).get("files") or {}
    except Exception:
        old = {}
def sha(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()
h_out, s_out = [], []
with open(listfile, encoding="utf-8") as fh:
    rels = [l.strip() for l in fh if l.strip()]
for rel in rels:
    sp, dp = os.path.join(src, rel), os.path.join(dst, rel)
    if not os.path.isfile(sp):
        continue
    h_out.append(rel)
    if not os.path.exists(dp):
        os.makedirs(os.path.dirname(dp), exist_ok=True)
        shutil.copyfile(sp, dp)
        print("copy " + rel)
        continue
    recorded = old.get(rel)
    if recorded is not None and recorded == sha(dp):
        shutil.copyfile(sp, dp)
        print("update " + rel)
    else:
        print("skip (edited) " + rel)
        s_out.append(rel)
with open(handled, "w", encoding="utf-8") as fh:
    fh.write("".join(r + "\n" for r in h_out))
with open(skipped, "w", encoding="utf-8") as fh:
    fh.write("".join(r + "\n" for r in s_out))
' "$SRC" "$DST" "$MANIFEST_FILE" "$UPDATE_LIST" "$HANDLED_LIST" "$SKIPPED_LIST"
  rm -f "$UPDATE_LIST"
fi

# .claude/（settings.json は専用マージャで扱うのでこのループから外す）
for f in $(cd "$SRC/.claude" && find . -path './worktrees' -prune -o -type f ! -name 'settings.local.json' ! -name 'settings.json' -print | sed 's|^\./||'); do
  copy_if_absent "$SRC/.claude/$f" "$DST/.claude/$f"
done
chmod +x "$DST"/.claude/hooks/*.py

# vault/（空ディレクトリ構成のみ作る。計画票は /plan が作るので配らない）
for d in plans tasks verdicts log designs archive templates rules; do mkdir -p "$DST/vault/$d"; done
# vault/rules/ 配下は README・各役割ディレクトリの .gitkeep（雛形）と、役割定義の標準ルール4本を複製する。
# ドメイン固有のルール（コーディングルール・方式設計・テスト観点など）は複製・上書きの対象にしない。
# 標準ルールも copy_if_absent なので、インストール先で編集したものは上書きしない。
for f in tasks/.gitkeep plans/.gitkeep verdicts/.gitkeep archive/.gitkeep designs/.gitkeep templates/task.md templates/plan.md templates/rule.md templates/design.md rules/README.md rules/common/.gitkeep rules/creator/.gitkeep rules/verifier/.gitkeep rules/planner/.gitkeep rules/common/roles.md rules/common/git.md rules/creator/creator.md rules/creator/git-workflow.md rules/verifier/verifier.md rules/planner/planner.md; do
  copy_if_absent "$SRC/vault/$f" "$DST/vault/$f"
done

# scripts/ 直下の *.sh・*.py（SCRIPTS_EXCLUDE を除く）、docs/vault-spec.md（エージェントが参照する正本）
for rel in $(scripts_list); do
  copy_if_absent "$SRC/$rel" "$DST/$rel"
done
copy_if_absent "$SRC/docs/vault-spec.md" "$DST/docs/vault-spec.md"

# .claude/settings.json（専用マージャ。--update の有無や既存の有無にかかわらず常に呼ぶ）
python3 "$SRC/scripts/merge_settings_json.py" "$SRC/.claude/settings.json" "$DST/.claude/settings.json"

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

# ハーネス本体のマニフェスト（配ったファイルの sha256 を記録する）。
# 記録するのは src の実ファイルのハッシュ。ただし --update で「編集済み」としてスキップした
# パスは、今回配っていないので既存の記録を据え置く。
MANIFEST_LIST="$(mktemp)"
manifest_paths > "$MANIFEST_LIST"
python3 -c '
import hashlib, json, os, sys
src, out, version, listfile, skipped = sys.argv[1:6]
prev = {}
if os.path.isfile(out):
    try:
        with open(out, encoding="utf-8") as fh:
            prev = json.load(fh).get("files") or {}
    except Exception:
        prev = {}
keep = set()
if os.path.isfile(skipped):
    with open(skipped, encoding="utf-8") as fh:
        keep = {l.strip() for l in fh if l.strip()}
files = {}
with open(listfile, encoding="utf-8") as fh:
    for line in fh:
        rel = line.strip()
        if not rel:
            continue
        p = os.path.join(src, rel)
        if not os.path.isfile(p):
            continue
        if rel in keep and rel in prev:
            files[rel] = prev[rel]
            continue
        with open(p, "rb") as g:
            files[rel] = hashlib.sha256(g.read()).hexdigest()
settings_src = None
settings_path = os.path.join(src, ".claude", "settings.json")
if os.path.isfile(settings_path):
    with open(settings_path, encoding="utf-8") as fh:
        settings_src = json.load(fh)
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as fh:
    json.dump({"version": version, "files": files, "settings_src": settings_src}, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
print("manifest  .claude/harness-manifest.json (%d files)" % len(files))
' "$SRC" "$MANIFEST_FILE" "$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')" "$MANIFEST_LIST" "$SKIPPED_LIST"
rm -f "$MANIFEST_LIST"

echo
echo "done: $DST"
if [ "$NO_CLAUDE_MD" -eq 0 ]; then
  echo "check: 既存の CLAUDE.md にハーネスと矛盾するルールが残っていないか確認してください（マージは追記するだけで、矛盾は解消しません）"
fi
echo "next: cd \"$DST\" && bash scripts/smoke.sh && claude   # 一度対話起動してフォルダを信頼する"
