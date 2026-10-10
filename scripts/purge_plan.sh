#!/usr/bin/env bash
# 完了した計画の一式4種を git rm で除去する。run の手順7でオーケストレーターが使う。
# 使い方: bash scripts/purge_plan.sh [--dry-run] <計画ID>
#         bash scripts/purge_plan.sh --merged (--list|--report|--apply)
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
# --merged: main にマージ済みの計画一式と vault/archive/ をまとめて扱う。
# --merged --apply は人だけが実行する。エージェントは --merged では --list・--report だけを使う。
#   対象の計画（vault/plans/*.md を LC_ALL=C のファイル名順に見て、次の全部を満たすもの）：
#     1. 計画 ID が ^P-[0-9]{8}-[a-z0-9][a-z0-9-]*$ に一致する（P-019 のような旧形式は対象外）
#     2. 現在のブランチが work/<計画IDを英小文字にしたもの> でない
#     3. 作業ツリーの計画票の frontmatter の status が done
#     4. タスク表のデータ行が1行以上あり、全行の status 列が done
#     5. main の vault/plans/<計画ID>.md の frontmatter の status が done（main が無い・その版が無い時は対象外）
#   --list   対象の計画 ID を1行1件で標準出力に出す。何も変えない。0件なら何も出さず終了コード0。
#   --report 対象の計画ごとに、log の <旧>→blocked の行を <計画ID>/<id>: blocked <補足> で、
#            続けて verdict の空でない reasons を <計画ID>/<id>: reasons <理由> で1行ずつ出す。何も変えない。
#            vault/archive/ の中身は報告しない。
#   --apply  対象の計画ごとに上の4種（存在するものだけ）を並べ、最後に vault/archive/ があれば加えて
#            git rm -r -q を1回呼び、消したパスを1行1件で標準出力に出す。コミットはしない。
#            対象パスに未コミット・未追跡・stage 済みの変更があれば何も消さず終了コード1。
#            対象が0件で vault/archive/ も無ければ標準エラーに出して終了コード0（標準出力は空）。
#            現在のブランチが main かどうかは検査しない。
#
# 終了コード:
#   0 消した／dry-run で出した
#   1 条件を満たさない（何も消さない）、または git rm の失敗
#   2 引数の誤り（--merged の組み合わせの誤りを含む）、git リポジトリの外
set -u
export LC_ALL=C

USAGE="usage: bash scripts/purge_plan.sh [--dry-run] <計画ID> | bash scripts/purge_plan.sh --merged (--list|--report|--apply)"
usage_exit() {
  echo "$USAGE" >&2
  exit 2
}

MERGED=0
MODE=""
NMODE=0
DRY=0
ID=""
NARGS=0
for a in "$@"; do
  case "$a" in
    --merged) MERGED=1 ;;
    --list | --report | --apply)
      MODE="${a#--}"
      NMODE=$((NMODE + 1))
      ;;
    --dry-run) DRY=1 ;;
    -*) usage_exit ;;
    *)
      NARGS=$((NARGS + 1))
      ID="$a"
      ;;
  esac
done
ID_RE='^P-[0-9]{8}-[a-z0-9][a-z0-9-]*$'
if [ "$MERGED" -eq 1 ]; then
  { [ "$NMODE" -eq 1 ] && [ "$NARGS" -eq 0 ] && [ "$DRY" -eq 0 ]; } || usage_exit
else
  [ "$NMODE" -eq 0 ] || usage_exit
  [ "$NARGS" -eq 1 ] || usage_exit
  [[ "$ID" =~ $ID_RE ]] || usage_exit
fi

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

# ---- --merged モード ----
if [ "$MERGED" -eq 1 ]; then
  BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
  TARGETS=()
  for f in vault/plans/*.md; do
    [ -f "$f" ] || continue
    pid="$(basename "$f" .md)"
    [[ "$pid" =~ $ID_RE ]] || continue
    [ "$BRANCH" != "work/$(printf '%s' "$pid" | tr 'A-Z' 'a-z')" ] || continue
    [ "$(fm_status < "$f")" = "done" ] || continue
    counts="$(table_counts "$f")"
    { [ "${counts% *}" -ge 1 ] && [ "${counts#* }" -eq 0 ]; } || continue
    mst="$(git show "main:vault/plans/$pid.md" 2>/dev/null | fm_status)"
    [ "$mst" = "done" ] || continue
    TARGETS+=("$pid")
  done

  case "$MODE" in
    list)
      [ "${#TARGETS[@]}" -eq 0 ] || printf '%s\n' "${TARGETS[@]}"
      exit 0
      ;;
    report)
      BLK_RE='^-[ ]+[^ ]+[ ]+[^ ]+[ ]+([^ ]+)[ ]+[^ ]*→blocked[ ]+attempt=[0-9]+(.*)$'
      for pid in "${TARGETS[@]+"${TARGETS[@]}"}"; do
        lg="vault/log/$pid.md"
        if [ -f "$lg" ]; then
          while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            if [[ "$line" =~ $BLK_RE ]]; then
              tid="${BASH_REMATCH[1]}"
              rest="${BASH_REMATCH[2]}"
              rest="${rest#"${rest%%[![:space:]]*}"}"
              if [[ "$rest" =~ ^(creator|verifier)=[^[:space:]]*(.*)$ ]]; then
                rest="${BASH_REMATCH[2]}"
              fi
              rest="${rest#"${rest%%[![:space:]]*}"}"
              rest="${rest%"${rest##*[![:space:]]}"}"
              [ -n "$rest" ] || rest="(補足なし)"
              printf '%s/%s: blocked %s\n' "$pid" "$tid" "$rest"
            fi
          done < "$lg"
        fi
        if [ -d "vault/verdicts/$pid" ]; then
          python3 - "$pid" "vault/verdicts/$pid" <<'PYEOF'
import glob, json, os, sys
pid, d = sys.argv[1], sys.argv[2]
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    tid = os.path.basename(f)[:-5]
    try:
        with open(f, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        print(f"{pid}/{tid}: reasons verdict を JSON として読めない")
        continue
    reasons = data.get("reasons") if isinstance(data, dict) else None
    if not isinstance(reasons, list):
        continue
    for r in reasons:
        text = " ".join(str(r).split())
        if text:
            print(f"{pid}/{tid}: reasons {text}")
PYEOF
        fi
      done
      exit 0
      ;;
    apply)
      MPATHS=()
      for pid in "${TARGETS[@]+"${TARGETS[@]}"}"; do
        for p in "vault/plans/$pid.md" "vault/tasks/$pid/" "vault/verdicts/$pid/" "vault/log/$pid.md"; do
          if [ -e "${p%/}" ]; then MPATHS+=("$p"); fi
        done
      done
      if [ -e vault/archive ]; then MPATHS+=("vault/archive/"); fi
      if [ "${#MPATHS[@]}" -eq 0 ]; then
        echo "purge_plan.sh: 削除するものがありません" >&2
        exit 0
      fi
      dirty="$(git status --porcelain --untracked-files=all -- "${MPATHS[@]}" 2>&1)"
      if [ -n "$dirty" ]; then
        echo "purge_plan.sh: 対象パスに未コミット・未追跡・stage 済みの変更がある" >&2
        exit 1
      fi
      if ! git rm -r -q -- "${MPATHS[@]}"; then
        echo "purge_plan.sh: git rm に失敗しました（git status で確認してください）" >&2
        exit 1
      fi
      printf '%s\n' "${MPATHS[@]}"
      exit 0
      ;;
  esac
fi

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
