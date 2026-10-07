#!/usr/bin/env bash
# P-20261007-transition-worktree（T-06）の確認用。planner が置いたフィクスチャで、成果物ではない。
# 一時 git リポジトリ（ブランチ work/p-test、計画票 P-TEST、タスク T-01〜T-05）に次の件名のコミットを
# 古い順に作り、scripts/pr_body.py P-TEST を1回実行して、出力と期待するコミットの短縮ハッシュを出す。
#   c1  P-TEST/T-01: done                 （従来の run の件名）
#   c2  P-TEST/T-02: review→done          （transition.py の件名）
#   c3  P-TEST/T-03,T-04: review→done     （transition.py の複数 id の件名）
#   c4  P-TEST/T-05: マージ               （done ではない）
#   c5  P-TEST/T-05: review→doing         （done ではない）
#   c6  P-TEST/T-050: review→done         （別の id。T-05 に当たってはいけない）
#   c7  P-TEST/T-01,T-050: done           （T-01 の2回目の done。T-01 は最新の c7 が出る）
#   c8  P-TEST/T-02: review→done (x)      （行末が違う。T-02 に当たってはいけない）
# 出力: want_T-01〜want_T-05（期待するハッシュ。無ければ -）/ exit / --- stdout / --- stderr
# 使い方: bash vault/tasks/P-20261007-transition-worktree/fixtures/pr_body.sh
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
R="$WORK/repo"
mkdir -p "$R/vault/plans"
{
  echo "---"; echo "id: P-TEST"; echo "status: approved"; echo "---"
  echo "# ゴール"; echo "確認用"; echo
  echo "## タスク表（状態の正本）"
  echo "| id | status | attempt | after | title | question |"
  echo "|---|---|---|---|---|---|"
  echo "| T-01 | done | 1 | - | A | |"
  echo "| T-02 | done | 1 | - | B | |"
  echo "| T-03 | done | 1 | - | C | |"
  echo "| T-04 | done | 1 | - | D | |"
  echo "| T-05 | doing | 2 | - | E | |"
} > "$R/vault/plans/P-TEST.md"
git -C "$R" init -q -b work/p-test
git -C "$R" config user.name fixture
git -C "$R" config user.email fixture@example.com
git -C "$R" add -A
git -C "$R" commit -q -m init
mk() { git -C "$R" commit -q --allow-empty -m "$1"; git -C "$R" log -1 --format=%h; }
C1="$(mk 'P-TEST/T-01: done')"
C2="$(mk 'P-TEST/T-02: review→done')"
C3="$(mk 'P-TEST/T-03,T-04: review→done')"
mk 'P-TEST/T-05: マージ' > /dev/null
mk 'P-TEST/T-05: review→doing' > /dev/null
mk 'P-TEST/T-050: review→done' > /dev/null
C7="$(mk 'P-TEST/T-01,T-050: done')"
mk 'P-TEST/T-02: review→done (x)' > /dev/null
echo "want_T-01=$C7"
echo "want_T-02=$C2"
echo "want_T-03=$C3"
echo "want_T-04=$C3"
echo "want_T-05=-"
( cd "$R" && python3 "$ROOT/scripts/pr_body.py" P-TEST ) > "$WORK/out" 2> "$WORK/err"
echo "exit=$?"
echo "--- stdout"
cat "$WORK/out"
echo "--- stderr"
cat "$WORK/err"
