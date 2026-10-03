#!/usr/bin/env bash
# 古い計画（done かつ PR がマージ済み）の一式を vault/archive/<年-月>/ に git mv で移す。
# 使い方: bash scripts/archive_plans.sh (--list|--dry-run|--apply) [--keep <N>] [--base <ref>] [--from-file <path>] [<計画ID> ...]
#
# 注意：--apply は人が手元で実行する。エージェント（creator を含む）は --list・--dry-run だけを使う。
# creator は vault/plans/・vault/log/ に書き込めず、スクリプト経由の移動はその禁止を回避することに
# なるため。
#
# 候補（移すか残すかを決める母集団）は vault/plans/*.md のうち次を全部満たすもの。
#   1. 計画 ID が ^P-[0-9]{8}-[a-z0-9][a-z0-9-]*$ に一致する
#   2. 現在のブランチ名が work/<計画 ID を英小文字にしたもの> でない
#   3. frontmatter の status が done（読み方は scripts/current_plan.sh と同じ）
#   4. タスク表のデータ行が1行以上あり、全行の status 列が done
#   5. <base> の版の計画票も frontmatter の status が done（PR がマージ済み）
#   6. vault/log/<ID>.md に "- YYYY-MM-DD HH:MM " で始まる行が1行以上ある
# 候補を「log の最初の日時行、同じなら計画 ID の文字列順」で古い順に並べ、新しい方から --keep 件
# （既定5）を残す。それより前の全部が移す対象。
# 配置は vault/ と同じ形：vault/archive/<年-月>/{plans,tasks,verdicts,log}/<計画ID>[.md]
# NG が1件でもあれば何も移さず終了コード1。--apply でもコミットはしない。
set -eu
export LC_ALL=C

USAGE="usage: bash scripts/archive_plans.sh (--list|--dry-run|--apply) [--keep <N>] [--base <ref>] [--from-file <path>] [<計画ID> ...]"

usage_exit() {
  echo "$USAGE" >&2
  exit 2
}

MODE=""
KEEP=5
BASE="main"
FROM_FILE=""
ARGS_IDS=()

set_mode() {
  [ -z "$MODE" ] || usage_exit
  MODE="$1"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --list) set_mode list ;;
    --dry-run) set_mode dry-run ;;
    --apply) set_mode apply ;;
    --keep)
      [ $# -ge 2 ] || usage_exit
      KEEP="$2"
      shift
      ;;
    --base)
      [ $# -ge 2 ] || usage_exit
      BASE="$2"
      shift
      ;;
    --from-file)
      [ $# -ge 2 ] || usage_exit
      FROM_FILE="$2"
      shift
      ;;
    -*) usage_exit ;;
    *) ARGS_IDS+=("$1") ;;
  esac
  shift
done

[ -n "$MODE" ] || usage_exit
case "$KEEP" in
  ''|*[!0-9]*) usage_exit ;;
esac

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "archive_plans: git リポジトリの外では実行できません" >&2
  exit 2
fi
cd "$ROOT"

# 渡された計画 ID を集める（引数 + --from-file）
GIVEN=()
if [ "${#ARGS_IDS[@]}" -gt 0 ]; then
  GIVEN=("${ARGS_IDS[@]}")
fi
if [ -n "$FROM_FILE" ]; then
  if [ ! -f "$FROM_FILE" ] || [ ! -r "$FROM_FILE" ]; then
    echo "archive_plans: --from-file を読めません: $FROM_FILE" >&2
    exit 2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    GIVEN+=("$line")
  done < "$FROM_FILE"
fi

# frontmatter の status を標準入力から読む（current_plan.sh と同じ規則）
fm_status() {
  awk '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") { exit 0 } ; next }
    {
      if ($0 == "---") { exit 0 }
      line = $0
      if (line ~ /^status:[ \t]*[^ \t]+[ \t]*$/) {
        sub(/^status:[ \t]*/, "", line)
        sub(/[ \t]*$/, "", line)
        print line
        exit 0
      }
    }
  '
}

# タスク表のデータ行数と、done でない行数を "<total> <notdone>" で出す
table_counts() {
  awk -F'|' '
    {
      sub(/\r$/, "")
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

CURRENT_BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
ID_RE='^P-[0-9]{8}-[a-z0-9][a-z0-9-]*$'

# 候補の条件を検査する。満たさない条件を ; 区切りで REASON に入れる（空なら候補）。
# 最初の日時行は FIRST_TS に入れる。
REASON=""
FIRST_TS=""
check_candidate() {
  local id="$1" plan="vault/plans/$1.md" log="vault/log/$1.md"
  local r="" st counts total notdone base_st
  REASON=""
  FIRST_TS=""
  if ! [[ "$id" =~ $ID_RE ]]; then
    REASON="条件1 計画 ID の形式が違う"
    return 0
  fi
  if [ ! -f "$plan" ]; then
    REASON="$plan が無い"
    return 0
  fi
  if [ "$CURRENT_BRANCH" = "work/$(printf '%s' "$id" | tr 'A-Z' 'a-z')" ]; then
    r="${r:+$r; }条件2 現在のブランチの計画"
  fi
  st="$(fm_status < "$plan")"
  if [ "$st" != "done" ]; then
    r="${r:+$r; }条件3 status が done でない"
  fi
  counts="$(table_counts "$plan")"
  total="${counts% *}"
  notdone="${counts#* }"
  if [ "$total" -lt 1 ] || [ "$notdone" -gt 0 ]; then
    r="${r:+$r; }条件4 タスク表が全行 done でない"
  fi
  if base_st="$(git show "$BASE:$plan" 2>/dev/null | fm_status)" && [ "$base_st" = "done" ]; then
    :
  else
    r="${r:+$r; }条件5 $BASE の版が done でない（マージ済みでない）"
  fi
  if [ -f "$log" ]; then
    FIRST_TS="$(grep -m1 -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} ' "$log" | sed -e 's/^- //' -e 's/ $//' || true)"
  fi
  if [ -z "$FIRST_TS" ]; then
    r="${r:+$r; }条件6 log に日時行が無い"
  fi
  REASON="$r"
}

# 候補を集めて古い順に並べる
CAND_FILE="$(mktemp)"
trap 'rm -f "$CAND_FILE"' EXIT
shopt -s nullglob
for f in vault/plans/*.md; do
  b="$(basename "$f")"
  id="${b%.md}"
  check_candidate "$id"
  if [ -z "$REASON" ]; then
    printf '%s\t%s\n' "$FIRST_TS" "$id" >> "$CAND_FILE"
  fi
done
shopt -u nullglob

SORTED=()
while IFS= read -r l; do
  SORTED+=("${l#*$'\t'}")
done < <(sort "$CAND_FILE")

N="${#SORTED[@]}"
TARGETS=()
if [ "$N" -gt "$KEEP" ]; then
  for ((i = 0; i < N - KEEP; i++)); do
    TARGETS+=("${SORTED[$i]}")
  done
fi

in_list() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    [ "$x" = "$needle" ] && return 0
  done
  return 1
}

NG=0
ng() {
  echo "archive_plans: NG $1: $2" >&2
  NG=1
}

SELECTED=()
if [ "${#GIVEN[@]}" -gt 0 ]; then
  SEEN=()
  for id in "${GIVEN[@]}"; do
    if [ "${#SEEN[@]}" -gt 0 ] && in_list "$id" "${SEEN[@]}"; then
      ng "$id" "同じ ID が2回以上渡された"
      continue
    fi
    SEEN+=("$id")
    if [ "${#TARGETS[@]}" -gt 0 ] && in_list "$id" "${TARGETS[@]}"; then
      SELECTED+=("$id")
      continue
    fi
    check_candidate "$id"
    if [ -n "$REASON" ]; then
      ng "$id" "$REASON"
    else
      ng "$id" "新しい $KEEP 件に入る"
    fi
  done
elif [ "${#TARGETS[@]}" -gt 0 ]; then
  SELECTED=("${TARGETS[@]}")
fi

if [ "$NG" -ne 0 ]; then
  exit 1
fi

if [ "${#SELECTED[@]}" -eq 0 ]; then
  echo "archive_plans: 移す計画がありません" >&2
  exit 0
fi

# 移動の組を作る（"移動元<TAB>移動先"）。存在しない移動元は飛ばす。
MOVES=()
for id in "${SELECTED[@]}"; do
  ym="${id:2:4}-${id:6:2}"
  dst_base="vault/archive/$ym"
  pairs=(
    "vault/plans/$id.md	$dst_base/plans/$id.md"
    "vault/tasks/$id	$dst_base/tasks/$id"
    "vault/verdicts/$id	$dst_base/verdicts/$id"
    "vault/log/$id.md	$dst_base/log/$id.md"
  )
  for p in "${pairs[@]}"; do
    src="${p%%$'\t'*}"
    dst="${p#*$'\t'}"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      ng "$id" "移動先が既に存在する: $dst"
    fi
    [ -e "$src" ] || continue
    if [ -n "$(git status --porcelain -- "$src")" ]; then
      ng "$id" "未コミットの変更または未追跡ファイルがある: $src"
    fi
    MOVES+=("$p")
  done
done

if [ "$NG" -ne 0 ]; then
  exit 1
fi

case "$MODE" in
  list)
    printf '%s\n' "${SELECTED[@]}"
    ;;
  dry-run)
    for p in "${MOVES[@]}"; do
      echo "git mv ${p%%$'\t'*} ${p#*$'\t'}"
    done
    ;;
  apply)
    for p in "${MOVES[@]}"; do
      src="${p%%$'\t'*}"
      dst="${p#*$'\t'}"
      echo "git mv $src $dst"
      mkdir -p "$(dirname "$dst")"
      if ! git mv "$src" "$dst"; then
        echo "archive_plans: git mv に失敗しました: $src -> $dst（それまでの移動は戻していません。git status で確認してください）" >&2
        exit 1
      fi
    done
    ;;
esac
exit 0
