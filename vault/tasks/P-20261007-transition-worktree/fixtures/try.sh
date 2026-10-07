#!/usr/bin/env bash
# P-20261007-transition-worktree（T-01〜T-03）の確認用。planner が置いたフィクスチャで、成果物ではない。
# 一時 git リポジトリ（ブランチ work/p-test、承認済み計画票 P-TEST、タスク票 T-01）と、
# 計画ブランチの HEAD（plan_head）から切った worktree（ブランチ worktree-agent-fx）を作り、
# メインの作業ツリーで scripts/transition.py を1回だけ実行して、結果を出す。
#
# 使い方: bash vault/tasks/P-20261007-transition-worktree/fixtures/try.sh <preset> [transition.py への引数...]
#   transition.py の引数の先頭の `P-TEST T-01` はこのスクリプトが付ける（<遷移先> から書く）。
#   引数の中の置き換え:
#     @WT    worktree のパス（mktemp の下。macOS では realpath と違う形のことがある）
#     @BR    worktree のブランチ名（worktree-agent-fx）
#     @PH    plan_head（worktree を切った時の計画ブランチの HEAD の40桁の sha）
#     @WORK  一時ディレクトリ（存在しない worktree のパスを作る時に使う。例：@WORK/nowhere）
#     @QFILE 中身が「質問A|B<改行>次の行」の一時ファイルのパス（--question-file 用）
#   例: bash .../try.sh rev review --worktree @WT --branch @BR --plan-head @PH
#
# preset（T-01 の status attempt / verdict / worktree の中身）:
#   rev       doing 1  / 無し       / 未コミット: src/ok.txt の変更とタスク票の「進捗」への追記
#   revc      doing 1  / 無し       / rev と同じ変更を creator がコミット済み（未コミット無し）
#   revx      doing 1  / 無し       / 未コミット: rev の変更 + 宣言外の extra.txt
#   revx3     doing 3  / 無し       / revx と同じ
#   rev0      doing 1  / 無し       / 変更なし（新規コミット無し）
#   pass      review 1 / PASS att=1 / rev の変更をコミット済み + 未追跡の verifier-out.txt（verifier の生成物の想定）
#   pass0     review 1 / PASS att=1 / 変更なし（新規コミット無し）
#   passx     review 1 / PASS att=1 / rev の変更 + extra.txt をコミット済み
#   conflict  review 1 / PASS att=1 / rev の変更をコミット済み。計画ブランチも plan_head の後で src/ok.txt を別の中身にコミット済み
#   nopass    review 1 / FAIL att=1 / rev の変更をコミット済み
#   fail      review 1 / FAIL att=1 / rev の変更をコミット済み（reasons は長い2件。下記）
#   fail3     review 3 / FAIL att=3 / fail と同じ
#   blk       doing 1  / 無し       / 未コミット: src/ok.txt の変更
# タスク表: T-01（preset の値）と T-02 todo 0 after=T-01。タスク票 T-01 の「成果物」は `src/ok.txt` だけ。
# verdict は run の実際と同じく未追跡で置く。モデルは creator=fx-creator-model・verifier=fx-verifier-model。
# FAIL の reasons: 1つ目「一つ目の理由|縦棒」+「あ」100個、2つ目「二つ目の理由」+「い」150個。
#   expect_note・expect_question は、決定済みの規則（`|`→`／`・改行→空白にしてから
#   1つ目を80文字／`／` でつないだものを200文字で切る）で計算した期待値。
#
# 出力（key=value の行、続いて節）:
#   wt_path（@WT の realpath）/ plan_head / expect_note / expect_question / exit
#   new_commits（計画ブランチに増えたコミット数）/ commit=<親の数> <件名> :: <変わったファイル>（増えた分、古い順）
#   merge_in_progress / porcelain（メインの作業ツリー、-uall）
#   wt_registered（git worktree list に @BR がある）/ wt_dir（@WT がある）/ branch_exists
#   wt_new_commits（plan_head..@BR の件数）/ wt_subject（@BR の先頭の件名）/ wt_porcelain
#   plan_guard（実行後の計画票で plan_guard.py が許可するか）
#   --- table / --- log_new（実行で増えた log の行）/ --- progress_tail（メインのタスク票の末尾2行）
#   --- worktrees（git worktree list --porcelain）/ --- stdout / --- stderr
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PRESET="${1:-rev}"
[ $# -gt 0 ] && shift
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
R="$WORK/repo"
WT="$WORK/wt"
BR="worktree-agent-fx"

ST=doing; AT=1; VD=none; WMODE=mod; WCOMMIT=no; EXTRA=no; ARTIFACT=no; PLANSIDE=no
case "$PRESET" in
  rev) ;;
  revc) WCOMMIT=yes ;;
  revx) EXTRA=yes ;;
  revx3) EXTRA=yes; AT=3 ;;
  rev0) WMODE=none ;;
  pass) ST=review; VD=pass; WCOMMIT=yes; ARTIFACT=yes ;;
  pass0) ST=review; VD=pass; WMODE=none ;;
  passx) ST=review; VD=pass; WCOMMIT=yes; EXTRA=yes ;;
  conflict) ST=review; VD=pass; WCOMMIT=yes; PLANSIDE=yes ;;
  nopass) ST=review; VD=fail; WCOMMIT=yes ;;
  fail) ST=review; VD=fail; WCOMMIT=yes ;;
  fail3) ST=review; AT=3; VD=fail; WCOMMIT=yes ;;
  blk) WMODE=ok ;;
  *) echo "unknown preset: $PRESET" >&2; exit 2 ;;
esac

mkdir -p "$R/vault/plans" "$R/vault/log" "$R/vault/verdicts/P-TEST" "$R/vault/tasks/P-TEST" "$R/src" "$R/.claude/agents"
{
  echo "---"
  echo "id: P-TEST"
  echo "status: approved"
  echo "---"
  echo "# ゴール"
  echo "確認用の計画"
  echo
  echo "## タスク表（状態の正本）"
  echo "| id | status | attempt | after | title | question |"
  echo "|---|---|---|---|---|---|"
  echo "| T-01 | $ST | $AT | - | A | |"
  echo "| T-02 | todo | 0 | T-01 | B | |"
  echo
  echo "## 計画の受け入れ基準"
  echo "- 確認用"
} > "$R/vault/plans/P-TEST.md"
{
  echo "# T-01 確認用"
  echo
  echo "## 目的"
  echo "確認用"
  echo
  echo "## 入力"
  echo "- なし"
  echo
  echo "## 成果物"
  echo '- `src/ok.txt`（1ファイル）'
  echo
  echo "## 受け入れ基準"
  echo "- 基準"
  echo
  echo "## 決定済み"
  echo "- なし"
  echo
  echo "## 進捗"
} > "$R/vault/tasks/P-TEST/T-01.md"
echo "- 2026-01-01 00:00 - draft→approved 人の指示: /plan approve P-TEST" > "$R/vault/log/P-TEST.md"
echo "base" > "$R/src/ok.txt"
printf -- '---\nname: creator\nmodel: fx-creator-model\n---\n本文\n' > "$R/.claude/agents/creator.md"
printf -- '---\nname: verifier\nmodel: fx-verifier-model\n---\n本文\n' > "$R/.claude/agents/verifier.md"

git -C "$R" init -q -b main
git -C "$R" config user.name fixture
git -C "$R" config user.email fixture@example.com
git -C "$R" add -A
git -C "$R" commit -q -m init
git -C "$R" checkout -q -b work/p-test
PH="$(git -C "$R" rev-parse HEAD)"
git -C "$R" worktree add -q -b "$BR" "$WT" "$PH"

if [ "$WMODE" != "none" ]; then
  echo "changed" > "$WT/src/ok.txt"
  if [ "$WMODE" = "mod" ]; then
    printf -- '- 進捗の追記\n' >> "$WT/vault/tasks/P-TEST/T-01.md"
  fi
fi
[ "$EXTRA" = "yes" ] && echo "extra" > "$WT/extra.txt"
if [ "$WCOMMIT" = "yes" ]; then
  git -C "$WT" add -A
  git -C "$WT" commit -q -m "creator のコミット"
fi
[ "$ARTIFACT" = "yes" ] && echo "out" > "$WT/verifier-out.txt"
if [ "$PLANSIDE" = "yes" ]; then
  echo "plan side" > "$R/src/ok.txt"
  git -C "$R" add src/ok.txt
  git -C "$R" commit -q -m "計画ブランチ側の変更"
fi

python3 - "$R" "$VD" "$AT" "$WORK" <<'PY'
import json, os, re, sys
root, vd, at, work = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
r1 = "一つ目の理由|縦棒" + "あ" * 100
r2 = "二つ目の理由" + "い" * 150
def clean(s):
    s = s.replace("|", "／")
    s = re.sub(r"\r\n|\r|\n", " ", s)
    return s.strip()
with open(os.path.join(work, "expect"), "w", encoding="utf-8") as f:
    f.write("expect_note=%s\n" % clean(r1)[:80])
    f.write("expect_question=%s\n" % clean("／".join([r1, r2]))[:200])
if vd != "none":
    v = {
        "task": "P-TEST/T-01",
        "attempt": at if vd == "fail" else 1,
        "result": "PASS" if vd == "pass" else "FAIL",
        "checked_at": "2026-01-01 00:00",
        "criteria": [{"text": "基準", "ok": vd == "pass", "note": "実行コマンド: x / 出力: y"}],
        "reasons": [] if vd == "pass" else [r1, r2],
    }
    with open(os.path.join(root, "vault/verdicts/P-TEST/T-01.json"), "w", encoding="utf-8") as f:
        json.dump(v, f, ensure_ascii=False)
        f.write("\n")
PY

printf '質問A|B\n次の行\n' > "$WORK/q.txt"
ARGS=()
for a in "$@"; do
  case "$a" in
    @WT) ARGS+=("$WT") ;;
    @BR) ARGS+=("$BR") ;;
    @PH) ARGS+=("$PH") ;;
    @QFILE) ARGS+=("$WORK/q.txt") ;;
    @WORK*) ARGS+=("$WORK${a#@WORK}") ;;
    *) ARGS+=("$a") ;;
  esac
done

L0="$(wc -l < "$R/vault/log/P-TEST.md" | tr -d ' ')"
N0="$(git -C "$R" rev-parse HEAD)"
( cd "$R" && python3 "$ROOT/scripts/transition.py" P-TEST T-01 ${ARGS[@]+"${ARGS[@]}"} ) > "$WORK/out" 2> "$WORK/err"
RC=$?

echo "wt_path=$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$WT")"
echo "plan_head=$PH"
cat "$WORK/expect"
echo "exit=$RC"
echo "new_commits=$(git -C "$R" rev-list --count "$N0..HEAD")"
for c in $(git -C "$R" rev-list --reverse "$N0..HEAD"); do
  np="$(git -C "$R" rev-list --parents -n 1 "$c" | wc -w | tr -d ' ')"
  np=$((np - 1))
  files="$(git -C "$R" diff --name-only "$c^1" "$c" | sort | tr '\n' ' ' | sed 's/ $//')"
  echo "commit=$np $(git -C "$R" log -1 --format=%s "$c") :: $files"
done
if [ -e "$(git -C "$R" rev-parse --git-path MERGE_HEAD)" ] || [ -e "$R/$(git -C "$R" rev-parse --git-path MERGE_HEAD)" ]; then
  echo "merge_in_progress=yes"
else
  echo "merge_in_progress=no"
fi
echo "porcelain=$(git -C "$R" status --porcelain -uall | tr '\n' ' ' | sed 's/ $//')"
if git -C "$R" worktree list --porcelain | grep -qx "branch refs/heads/$BR"; then echo "wt_registered=yes"; else echo "wt_registered=no"; fi
if [ -d "$WT" ]; then echo "wt_dir=yes"; else echo "wt_dir=no"; fi
if git -C "$R" show-ref --verify --quiet "refs/heads/$BR"; then
  echo "branch_exists=yes"
  echo "wt_new_commits=$(git -C "$R" rev-list --count "$PH..$BR")"
  echo "wt_subject=$(git -C "$R" log -1 --format=%s "$BR")"
else
  echo "branch_exists=no"
  echo "wt_new_commits="
  echo "wt_subject="
fi
if [ -d "$WT" ]; then
  echo "wt_porcelain=$(git -C "$WT" status --porcelain -uall | tr '\n' ' ' | sed 's/ $//')"
else
  echo "wt_porcelain="
fi
PG="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit"}' | CLAUDE_PROJECT_DIR="$R" python3 "$ROOT/.claude/hooks/plan_guard.py" 2>&1)"
if echo "$PG" | grep -q '"decision": *"block"'; then
  echo "plan_guard=block $PG"
else
  echo "plan_guard=allow"
fi
echo "--- table"
grep '^| T-' "$R/vault/plans/P-TEST.md"
echo "--- log_new"
tail -n +"$((L0 + 1))" "$R/vault/log/P-TEST.md"
echo "--- progress_tail"
tail -n 2 "$R/vault/tasks/P-TEST/T-01.md"
echo "--- worktrees"
git -C "$R" worktree list --porcelain
echo "--- stdout"
cat "$WORK/out"
echo "--- stderr"
cat "$WORK/err"
