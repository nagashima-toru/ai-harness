#!/usr/bin/env bash
# 完了した計画の一式4種を git rm で除去する。run の手順7でオーケストレーターが使う。
# 使い方: bash scripts/purge_plan.sh [--dry-run] <計画ID>
#
# 消す前に次を全部満たすことを確かめる（外れた条件ごとに purge_plan.sh: <理由> を標準エラーに1行出す）。
#   1. 現在のブランチが work/<計画IDを英小文字にしたもの>
#   2. vault/plans/<計画ID>.md があり、frontmatter の status が done
#   3. タスク表のデータ行が1行以上あり、全行の status 列が done
#   4. 対象パスに未コミット・未追跡・stage 済みの変更が無い
# 対象パス（存在するものだけ。この順）：
#   vault/plans/<計画ID>.md, vault/tasks/<計画ID>/, vault/verdicts/<計画ID>/, vault/log/<計画ID>.md
# --dry-run は消す予定のパスを1行1件で標準出力に出すだけ（作業ツリーとインデックスを変えない）。
# 実行時は git rm -r -q を1回呼び、消したパスを同じ形で標準出力に出す。
# コミットはしない（コミットはオーケストレーターが行う）。verdict の PASS 検査もしない。
#
# 終了コード:
#   0 消した／dry-run で出した
#   1 条件を満たさない（何も消さない）、または git rm の失敗
#   2 引数の誤り、git リポジトリの外
set -u
export LC_ALL=C

USAGE="usage: bash scripts/purge_plan.sh [--dry-run] <計画ID>"
usage_exit() {
  echo "$USAGE" >&2
  exit 2
}

DRY=0
ID=""
NARGS=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*) usage_exit ;;
    *)
      NARGS=$((NARGS + 1))
      ID="$a"
      ;;
  esac
done
[ "$NARGS" -eq 1 ] || usage_exit
ID_RE='^P-[0-9]{8}-[a-z0-9][a-z0-9-]*$'
[[ "$ID" =~ $ID_RE ]] || usage_exit

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "purge_plan.sh: git リポジトリの外では実行できません" >&2
  exit 2
fi
cd "$ROOT" || exit 2

fm_status() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") { exit 0 } ; next }
    {
      if ($0 == "---") { exit 0 }
      line = $0
      if (line ~ /^status:[ \t]*[^ \t]+/) {
        sub(/^status:[ \t]*/, "", line)
        sub(/[ \t].*$/, "", line)
        gsub(/^["\047]+|["\047]+$/, "", line)
        print line
        exit 0
      }
    }
  '
}

table_counts() {
  awk -F'|' '
    {
      sub(/\r$/, "")
      sub(/^[ \t]+/, "")
      if ($0 !~ /^\|/) next
      c1 = $2; gsub(/^[ \t]+|[ \t]+$/, "", c1)
      if (c1 !~ /^T-/) next
      c2 = $3; gsub(/^[ \t]+|[ \t]+$/, "", c2)
      total++
      if (c2 != "done") notdone++
    }
    END { printf "%d %d\n", total + 0, notdone + 0 }
  ' "$1"
}

PLAN="vault/plans/$ID.md"
NG=0
ng() {
  echo "purge_plan.sh: $1" >&2
  NG=1
}

BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
WANT="work/$(printf '%s' "$ID" | tr 'A-Z' 'a-z')"
if [ "$BRANCH" != "$WANT" ]; then
  ng "条件1 現在のブランチが $WANT でない（'$BRANCH'）"
fi

if [ ! -f "$PLAN" ]; then
  ng "計画票が無い: $PLAN"
else
  st="$(fm_status < "$PLAN")"
  if [ "$st" != "done" ]; then
    ng "条件2 frontmatter の status が done でない（'$st'）"
  fi
  counts="$(table_counts "$PLAN")"
  total="${counts% *}"
  notdone="${counts#* }"
  if [ "$total" -lt 1 ]; then
    ng "条件3 タスク表のデータ行が無い"
  elif [ "$notdone" -gt 0 ]; then
    ng "条件3 タスク表に done でない行がある（$notdone 行）"
  fi
fi

PATHS=()
for p in "$PLAN" "vault/tasks/$ID/" "vault/verdicts/$ID/" "vault/log/$ID.md"; do
  if [ -e "${p%/}" ]; then
    PATHS+=("$p")
  fi
done

if [ "${#PATHS[@]}" -gt 0 ]; then
  dirty="$(git status --porcelain --untracked-files=all -- "${PATHS[@]}" 2>&1)"
  if [ -n "$dirty" ]; then
    ng "条件4 対象パスに未コミット・未追跡・stage 済みの変更がある"
  fi
fi

[ "$NG" -eq 0 ] || exit 1

if [ "$DRY" -eq 1 ]; then
  printf '%s\n' "${PATHS[@]}"
  exit 0
fi

if ! git rm -r -q -- "${PATHS[@]}"; then
  echo "purge_plan.sh: git rm に失敗しました（git status で確認してください）" >&2
  exit 1
fi
printf '%s\n' "${PATHS[@]}"
exit 0
