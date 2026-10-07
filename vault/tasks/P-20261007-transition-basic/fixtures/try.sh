#!/usr/bin/env bash
# P-20261007-transition-basic（T-01・T-02）の確認用。planner が置いたフィクスチャで、成果物ではない。
# 一時 git リポジトリ（ブランチ work/p-test、承認済み計画票 P-TEST）を作り、その中で
# scripts/transition.py を1回だけ実行して、終了コード・コミット・タスク表・log を出す。
# 出力: exit / before・after（実行前後の JST）/ new_commits / subject / commit_files /
#       plan_changed・log_changed（計画票・log が実行前と違うか）/ staged / porcelain_before・porcelain /
#       plan_guard（実行後の計画票で plan_guard.py が許可するか）/ table・log・stdout・stderr の各節
#
# 使い方: bash vault/tasks/P-20261007-transition-basic/fixtures/try.sh <preset> [transition.py への引数...]
#   preset:
#     std      承認済み計画票・ブランチ work/p-test・log あり・.claude/agents あり
#     draft    計画票の status が draft（ほかは std と同じ）
#     main     ブランチが main（ほかは std と同じ）
#     nolog    vault/log/P-TEST.md が無い（ほかは std と同じ）
#     nomodel  .claude/agents/ が無い（ほかは std と同じ）
#     staged   std に加えて、無関係なファイル extra.txt を git add 済み（未コミット）にしておく
#   引数の中の @QFILE は、中身が「A|B<改行>次の行」の一時ファイルのパスに置き換える（--question-file 用）
#
# タスク表の初期状態:
#   T-01 todo 0 -        T-02 todo 0 -        T-03 todo 0 after=T-01
#   T-04 doing 1         T-05 doing 3
#   T-06 review 1（正しい PASS の verdict attempt=1）
#   T-07 review 1（FAIL の verdict attempt=1）
#   T-08 review 2（PASS の verdict だが attempt=1）
#   T-09 review 1（verdict 無し）
#   T-10 blocked 1（question あり）
#   T-11 review 3（verdict 無し）
# verdict（T-06〜T-08）は run の実際と同じく未コミット（未追跡）で置く。計画票・log・agents はコミット済み。
# モデル: .claude/agents/creator.md は model: fx-creator-model、verifier.md は model: fx-verifier-model
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PRESET="${1:-std}"
[ $# -gt 0 ] && shift
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
R="$WORK/repo"
mkdir -p "$R/vault/plans" "$R/vault/log" "$R/vault/verdicts/P-TEST"

PLAN_STATUS=approved
[ "$PRESET" = "draft" ] && PLAN_STATUS=draft
{
  echo "---"
  echo "id: P-TEST"
  echo "status: $PLAN_STATUS"
  echo "---"
  echo "# ゴール"
  echo "確認用の計画"
  echo
  echo "## タスク表（状態の正本）"
  echo "| id | status | attempt | after | title | question |"
  echo "|---|---|---|---|---|---|"
  echo "| T-01 | todo | 0 | - | A | |"
  echo "| T-02 | todo | 0 | - | B | |"
  echo "| T-03 | todo | 0 | T-01 | C | |"
  echo "| T-04 | doing | 1 | - | D | |"
  echo "| T-05 | doing | 3 | - | E | |"
  echo "| T-06 | review | 1 | - | F | |"
  echo "| T-07 | review | 1 | - | G | |"
  echo "| T-08 | review | 2 | - | H | |"
  echo "| T-09 | review | 1 | - | I | |"
  echo "| T-10 | blocked | 1 | - | J | 既存の質問 |"
  echo "| T-11 | review | 3 | - | K | |"
  echo
  echo "## 計画の受け入れ基準"
  echo "- 確認用"
} > "$R/vault/plans/P-TEST.md"

if [ "$PRESET" != "nolog" ]; then
  echo "- 2026-01-01 00:00 - draft→approved 人の指示: /plan approve P-TEST" > "$R/vault/log/P-TEST.md"
fi
if [ "$PRESET" != "nomodel" ]; then
  mkdir -p "$R/.claude/agents"
  printf -- '---\nname: creator\nmodel: fx-creator-model\n---\n本文\n' > "$R/.claude/agents/creator.md"
  printf -- '---\nname: verifier\nmodel: fx-verifier-model\n---\n本文\n' > "$R/.claude/agents/verifier.md"
fi

git -C "$R" init -q -b main
git -C "$R" config user.name fixture
git -C "$R" config user.email fixture@example.com
git -C "$R" add -A
git -C "$R" commit -q -m init
if [ "$PRESET" != "main" ]; then
  git -C "$R" checkout -q -b work/p-test
fi

OKC='{"text":"基準","ok":true,"note":"実行コマンド: x / 出力: y"}'
printf '{"task":"P-TEST/T-06","attempt":1,"result":"PASS","checked_at":"2026-01-01 00:00","criteria":[%s],"reasons":[]}\n' "$OKC" > "$R/vault/verdicts/P-TEST/T-06.json"
printf '{"task":"P-TEST/T-07","attempt":1,"result":"FAIL","checked_at":"2026-01-01 00:00","criteria":[%s],"reasons":["r"]}\n' "$OKC" > "$R/vault/verdicts/P-TEST/T-07.json"
printf '{"task":"P-TEST/T-08","attempt":1,"result":"PASS","checked_at":"2026-01-01 00:00","criteria":[%s],"reasons":[]}\n' "$OKC" > "$R/vault/verdicts/P-TEST/T-08.json"

if [ "$PRESET" = "staged" ]; then
  echo extra > "$R/extra.txt"
  git -C "$R" add extra.txt
fi

printf 'A|B\n次の行\n' > "$WORK/q.txt"
ARGS=()
for a in "$@"; do
  if [ "$a" = "@QFILE" ]; then ARGS+=("$WORK/q.txt"); else ARGS+=("$a"); fi
done

cp "$R/vault/plans/P-TEST.md" "$WORK/plan.before"
[ -f "$R/vault/log/P-TEST.md" ] && cp "$R/vault/log/P-TEST.md" "$WORK/log.before"
PORC0="$(git -C "$R" status --porcelain -uall | tr '\n' ' ')"
N0="$(git -C "$R" rev-list --count HEAD)"
BEFORE="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')"
( cd "$R" && python3 "$ROOT/scripts/transition.py" ${ARGS[@]+"${ARGS[@]}"} ) > "$WORK/out" 2> "$WORK/err"
RC=$?
AFTER="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')"
N1="$(git -C "$R" rev-list --count HEAD)"
NEW=$((N1 - N0))

echo "exit=$RC"
echo "before=$BEFORE"
echo "after=$AFTER"
echo "new_commits=$NEW"
if [ "$NEW" -gt 0 ]; then
  echo "subject=$(git -C "$R" log -1 --format=%s)"
  echo "commit_files=$(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ')"
else
  echo "subject="
  echo "commit_files="
fi
if cmp -s "$WORK/plan.before" "$R/vault/plans/P-TEST.md"; then echo "plan_changed=no"; else echo "plan_changed=yes"; fi
if [ -f "$WORK/log.before" ]; then
  if cmp -s "$WORK/log.before" "$R/vault/log/P-TEST.md"; then echo "log_changed=no"; else echo "log_changed=yes"; fi
else
  if [ -e "$R/vault/log/P-TEST.md" ]; then echo "log_changed=yes"; else echo "log_changed=no"; fi
fi
echo "staged=$(git -C "$R" diff --cached --name-only | tr '\n' ' ')"
echo "porcelain_before=$PORC0"
echo "porcelain=$(git -C "$R" status --porcelain -uall | tr '\n' ' ')"
PG="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit"}' | CLAUDE_PROJECT_DIR="$R" python3 "$ROOT/.claude/hooks/plan_guard.py" 2>&1)"
if echo "$PG" | grep -q '"decision": *"block"'; then
  echo "plan_guard=block $PG"
else
  echo "plan_guard=allow"
fi
echo "--- table"
grep '^| T-' "$R/vault/plans/P-TEST.md"
echo "--- log"
cat "$R/vault/log/P-TEST.md" 2>/dev/null || echo "(log なし)"
echo "--- stdout"
cat "$WORK/out"
echo "--- stderr"
cat "$WORK/err"
