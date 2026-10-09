#!/usr/bin/env bash
# フックの動作検証。疑似 stdin を渡して stop_gate.py / agent_write_guard.py の判定を確かめる。
# 使い方: bash scripts/smoke.sh   （install 先でも同じ。.claude/hooks/ が同階層にあればよい）
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOP_HOOK="$ROOT/.claude/hooks/stop_gate.py"
PLAN_GUARD_HOOK="$ROOT/.claude/hooks/plan_guard.py"
GUARD_HOOK="$ROOT/.claude/hooks/agent_write_guard.py"
RULES_SH="$ROOT/scripts/rules.sh"
CURRENT_PLAN_SH="$ROOT/scripts/current_plan.sh"
smoke_tmpdir() { mktemp -d "${TMPDIR:-/tmp}/smoke.XXXXXX"; }
abort_tmp() { echo "smoke: 一時ディレクトリを作れません（TMPDIR=${TMPDIR:-}）。中断します" >&2; exit 2; }
TMP="$(smoke_tmpdir)" || abort_tmp
trap 'rm -rf "$TMP"' EXIT
unset HARNESS_CREATOR_MODEL
PASS_N=0; FAIL_N=0

make_plan() { # $1=planID $2=planStatus $3...=「## タスク表」のデータ行（複数可）
  local plan_id="$1" plan_status="$2"
  mkdir -p "$TMP/vault/plans"
  shift 2
  {
    echo "---"
    echo "id: $plan_id"
    echo "status: $plan_status"
    echo "---"
    echo "# ゴール"
    echo
    echo "## タスク表（状態の正本）"
    echo "| id | status | attempt | after | title | question |"
    echo "|---|---|---|---|---|---|"
    for r in "$@"; do echo "$r"; done
  } > "$TMP/vault/plans/$plan_id.md"
}
make_plan_task() { # $1=id $2=status $3=attempt （旧 make_todo と同じ引数3つの形）
  make_plan "P-TEST" "approved" "| $1 | $2 | $3 | - | テスト | |"
}
make_verdict() { # $1=id $2=attempt $3=result （計画 ID は P-TEST 固定。task は "P-TEST/<id>" 形式）
  mkdir -p "$TMP/vault/verdicts/P-TEST"
  printf '{"task":"P-TEST/%s","attempt":%s,"result":"%s","checked_at":"2026-01-01 00:00","criteria":[],"reasons":["r1"]}\n' "$1" "$2" "$3" > "$TMP/vault/verdicts/P-TEST/$1.json"
}
DEFAULT_STDIN='{"hook_event_name":"Stop","stop_hook_active":false}'
make_task() { # $1=id $2=受け入れ基準の箇条書き行数
  mkdir -p "$TMP/vault/tasks/P-TEST"
  {
    echo "# $1 テスト"
    echo
    echo "## 受け入れ基準"
    for i in $(seq 1 "$2"); do echo "- 基準$i"; done
    echo
    echo "## 決定済み"
  } > "$TMP/vault/tasks/P-TEST/$1.md"
}
write_verdict() { # $1=id $2=json 文字列（形式検証のテスト用。保存先は P-TEST スコープ）
  mkdir -p "$TMP/vault/verdicts/P-TEST"
  printf '%s' "$2" > "$TMP/vault/verdicts/P-TEST/$1.json"
}
run_stop() { # $1=stdin json（省略時は DEFAULT_STDIN）
  printf '%s' "${1:-$DEFAULT_STDIN}" \
    | CLAUDE_PROJECT_DIR="$TMP" HARNESS_MAX_ATTEMPTS="${HARNESS_MAX_ATTEMPTS:-3}" python3 "$STOP_HOOK"
}
expect() { # $1=name $2=block|allow $3=output $4=substring(optional)
  local name="$1" want="$2" out="$3" sub="${4:-}"
  local got="allow"
  echo "$out" | grep -q '"decision": *"block"' && got="block"
  if [ "$got" = "$want" ] && { [ -z "$sub" ] || echo "$out" | grep -q -- "$sub"; }; then
    echo "  ok   $name"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $name (want=$want got=$got sub='$sub')"; echo "       out: $out"; FAIL_N=$((FAIL_N+1))
  fi
}

echo "== stop_gate.py =="
make_plan_task T-0001 doing 1;                        expect "doing あり・verdict なし → ブロック" block "$(run_stop)" "verifier"
make_plan_task T-0001 review 1; make_verdict T-0001 1 FAIL; expect "FAIL・attempt=1 → ブロック（doing に戻す）" block "$(run_stop)" "doing に戻し"
make_plan_task T-0001 doing 3;  make_verdict T-0001 3 FAIL; expect "FAIL・attempt=3・doing → ブロック（blocked にする）" block "$(run_stop)" "blocked"
make_plan_task T-0001 blocked 3; make_verdict T-0001 3 FAIL; expect "FAIL・attempt=3・blocked → 許可" allow "$(run_stop)"
make_plan_task T-0001 review 1; make_verdict T-0001 1 PASS; expect "PASS・review → ブロック（done にする）" block "$(run_stop)" "done"
make_plan_task T-0001 done 1;   make_verdict T-0001 1 PASS; expect "PASS・done → 許可" allow "$(run_stop)"
make_plan_task T-0001 todo 0;   rm -f "$TMP/vault/verdicts/P-TEST/T-0001.json"; expect "doing/review なし → 許可" allow "$(run_stop)"
make_plan_task T-0001 review 2; make_verdict T-0001 1 PASS; expect "PASS だが attempt 不一致（古い verdict）→ ブロック（verifier）" block "$(run_stop)" "古い"
make_plan_task T-0001 review 1; rm -f "$TMP/vault/verdicts/P-TEST/T-0001.json"; expect "stop_hook_active=true → 許可（既定）" allow "$(run_stop '{"hook_event_name":"Stop","stop_hook_active":true}')"
make_plan_task T-0001 review 1; expect "stop_hook_active=true + HARNESS_STRICT_STOP=1 → ブロック" block "$(printf '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$TMP" HARNESS_STRICT_STOP=1 python3 "$STOP_HOOK")" "verifier"
make_plan_task T-0001 review 2; make_verdict T-0001 2 FAIL; expect "HARNESS_MAX_ATTEMPTS=2 で attempt=2 FAIL → blocked 指示" block "$(HARNESS_MAX_ATTEMPTS=2 run_stop)" "blocked"

rm -rf "$TMP/vault/verdicts"; mkdir -p "$TMP/vault/verdicts/P-TEST"
make_plan "P-TEST" "approved" "| T-0001 | review | 1 | - | A | |" "| T-0002 | doing | 1 | - | B | |"
make_verdict T-0001 1 PASS
expect "(複数行-1) 1件目 verdict あり(PASS)・2件目 verdict 無し → ブロック（見落とさず検査。1件目の理由で block）" block "$(run_stop)" "T-0001"
rm -rf "$TMP/vault/verdicts"; mkdir -p "$TMP/vault/verdicts/P-TEST"
make_plan "P-TEST" "approved" "| T-0001 | review | 1 | - | A | |" "| T-0002 | review | 1 | - | B | |"
make_verdict T-0001 1 PASS; make_verdict T-0002 1 PASS
expect "(複数行-2) 複数行が全て PASS だが done でない → ブロック（done にする指示）" block "$(run_stop)" "done"
rm -rf "$TMP/vault/verdicts"; mkdir -p "$TMP/vault/verdicts/P-TEST"
make_plan "P-TEST" "approved" "| T-0001 | todo | 0 | - | A | |" "| T-0002 | todo | 0 | - | B | |"
expect "(複数行-3) doing/review 行が無い（複数 todo）→ 許可" allow "$(run_stop)"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
make_plan "P-A" "approved" "| T-0001 | doing | 1 | - | A | |"; make_plan "P-B" "approved" "| T-0001 | doing | 1 | - | B | |"
expect "approved な計画票が2件以上 → ブロック" block "$(run_stop)" "approved"
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
expect "approved な計画票が0件 → 許可" allow "$(run_stop)"

OK_C='{"text":"基準","ok":true,"note":"実行コマンド: x / 出力: y"}'
make_plan_task T-0001 review 1; write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"FOO","checked_at":"","criteria":['"$OK_C"'],"reasons":[]}'
expect "(a) result が PASS/FAIL 以外 → ブロック（不正）" block "$(run_stop)" "不正"
make_plan_task T-0001 review 1; write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":[{"text":"基準","ok":true}],"reasons":[]}'
expect "(b) criteria の要素に note が無い → ブロック（不正）" block "$(run_stop)" "不正"
make_plan_task T-0001 review 1; make_task T-0001 3; write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":['"$OK_C"','"$OK_C"'],"reasons":[]}'
expect "(c) criteria 2件 vs タスク票の基準 3行 → ブロック（不正）" block "$(run_stop)" "一致しません"
rm -f "$TMP/vault/tasks/P-TEST/T-0001.md"
make_plan_task T-0001 review 1; write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":[{"text":"基準","ok":true,"note":"  "}],"reasons":[]}'
expect "(d) note が空白のみ → ブロック（不正）" block "$(run_stop)" "不正"
make_plan_task T-0001 review 1; write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":['"$OK_C"'],"reasons":"none"}'
expect "(e) reasons が配列でない → ブロック（不正）" block "$(run_stop)" "不正"

sg_plan() { # $1=dir $2=planID: approved の計画票（タスク表は todo の1行）を置く（stop_gate 用）
  mkdir -p "$1/vault/plans"
  printf -- '---\nid: %s\nstatus: approved\n---\n# ゴール\n\n## タスク表（状態の正本）\n| id | status | attempt | after | title | question |\n|---|---|---|---|---|---|\n| T-0001 | todo | 0 | - | A | |\n' "$2" > "$1/vault/plans/$2.md"
}
SGTMP="$(smoke_tmpdir)" || abort_tmp
mkdir -p "$SGTMP/vault/plans"
git -C "$SGTMP" init -q -b main
sg_plan "$SGTMP" P-SG
git -C "$SGTMP" add -A
git -C "$SGTMP" -c user.email=t@example.com -c user.name=t commit -q -m init
echo dirty > "$SGTMP/x.txt"
expect "(f) 未コミットの変更がある・doing/review の行が無い → 許可" allow \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$SGTMP" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")"
rm -f "$SGTMP/x.txt"
expect "(g) 未コミットの変更が無い → 許可（既存判定へ進む）" allow \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$SGTMP" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")"
rm -rf "$SGTMP"

# 未コミットの変更があっても doing の行の verdict の判定へ進む
SGTMP="$(smoke_tmpdir)" || abort_tmp
mkdir -p "$SGTMP/vault/plans"
git -C "$SGTMP" init -q -b main
printf -- '---\nid: P-SG\nstatus: approved\n---\n# ゴール\n\n## タスク表（状態の正本）\n| id | status | attempt | after | title | question |\n|---|---|---|---|---|---|\n| T-0001 | doing | 1 | - | A | |\n' > "$SGTMP/vault/plans/P-SG.md"
git -C "$SGTMP" add -A
git -C "$SGTMP" -c user.email=t@example.com -c user.name=t commit -q -m init
echo dirty > "$SGTMP/x.txt"
expect "(f2) 未コミットの変更がある・doing の行の verdict が無い → ブロック（verdict の判定）" block \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$SGTMP" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")" "verdict が無い"
rm -rf "$SGTMP"

# approved な計画票が0件・2件の git リポジトリ（未コミットの変更があっても件数だけで判定する）
SGTMP="$(smoke_tmpdir)" || abort_tmp
mkdir -p "$SGTMP/vault/plans"
git -C "$SGTMP" init -q -b main
touch "$SGTMP/vault/plans/.gitkeep"
git -C "$SGTMP" add -A
git -C "$SGTMP" -c user.email=t@example.com -c user.name=t commit -q -m init
echo dirty > "$SGTMP/x.txt"
expect "(stop-scope-1) approved な計画票が0件・未コミットの変更あり → 許可" allow \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$SGTMP" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")"
rm -rf "$SGTMP"
SGTMP="$(smoke_tmpdir)" || abort_tmp
mkdir -p "$SGTMP/vault/plans"
git -C "$SGTMP" init -q -b main
sg_plan "$SGTMP" P-SG-A; sg_plan "$SGTMP" P-SG-B
git -C "$SGTMP" add -A
git -C "$SGTMP" -c user.email=t@example.com -c user.name=t commit -q -m init
echo dirty > "$SGTMP/x.txt"
expect "(stop-scope-2) approved な計画票が2件・未コミットの変更あり → 件数でブロック" block \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$SGTMP" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")" "approved な計画票が2件"
rm -rf "$SGTMP"

# worktree 委譲（issue #56 / D-008 フェーズ2）。agent_write_guard.py の (delegate) テスト・
# plan_guard.py の (delegate plan_guard) テストと同じ型：一時 worktree に判定結果が変わる
# 差し替えスクリプトを置き、cwd をその worktree に向けたペイロードをメインリポジトリ側の
# stop_gate.py に渡す。stop_gate.py はローカル判定に
# フォールバックさせるテスト（二重委譲防止・委譲失敗）では、CLAUDE_PROJECT_DIR 側のリポジトリを
# 事前に commit してクリーンな状態にしておく。
DWSMAIN="$(smoke_tmpdir)" || abort_tmp
git -C "$DWSMAIN" init -q -b main
git -C "$DWSMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
mkdir -p "$DWSMAIN/vault/plans"
{
  echo "---"; echo "id: P-TEST"; echo "status: approved"; echo "---"
  echo "# ゴール"; echo; echo "## タスク表（状態の正本）"
  echo "| id | status | attempt | after | title | question |"
  echo "|---|---|---|---|---|---|"
  echo "| T-0001 | done | 1 | - | A | |"
} > "$DWSMAIN/vault/plans/P-TEST.md"
mkdir -p "$DWSMAIN/vault/verdicts/P-TEST"
printf '%s\n' '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"2026-01-01 00:00","criteria":[],"reasons":["r1"]}' > "$DWSMAIN/vault/verdicts/P-TEST/T-0001.json"
git -C "$DWSMAIN" add -A
git -C "$DWSMAIN" -c user.email=t@example.com -c user.name=t commit -q -m plan
DWSLEAF="$(smoke_tmpdir)" || abort_tmp; rmdir "$DWSLEAF"
git -C "$DWSMAIN" worktree add -q -b work/p-delegate-stop "$DWSLEAF" >/dev/null 2>&1
mkdir -p "$DWSLEAF/.claude/hooks"
cat > "$DWSLEAF/.claude/hooks/stop_gate.py" <<'PYEOF'
#!/usr/bin/env python3
import json, sys
json.load(sys.stdin)
print(json.dumps({"decision": "block", "reason": "(delegate stop_gate) worktree override"}))
PYEOF
expect "(delegate stop_gate) worktree 側が常に block を返す差し替え → 通常なら許可される正常な計画票でも委譲先の判定（block）が採用される" block \
  "$(printf '%s' '{"cwd":"'"$DWSLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWSMAIN" python3 "$STOP_HOOK")" "(delegate stop_gate)"

expect "(delegate stop_gate) 呼び出し前に _HOOK_DELEGATED が既にセット済み → 二重委譲を防止しローカル判定にフォールバック（正常な計画票は許可）" allow \
  "$(printf '%s' '{"cwd":"'"$DWSLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWSMAIN" _HOOK_DELEGATED=1 python3 "$STOP_HOOK")"

git -C "$DWSMAIN" worktree remove -q --force "$DWSLEAF" >/dev/null 2>&1
rm -rf "$DWSMAIN" "$DWSLEAF"

DWSMAIN2="$(smoke_tmpdir)" || abort_tmp
git -C "$DWSMAIN2" init -q -b main
git -C "$DWSMAIN2" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
mkdir -p "$DWSMAIN2/vault/plans"
{
  echo "---"; echo "id: P-TEST"; echo "status: approved"; echo "---"
  echo "# ゴール"; echo; echo "## タスク表（状態の正本）"
  echo "| id | status | attempt | after | title | question |"
  echo "|---|---|---|---|---|---|"
  echo "| T-0001 | doing | 1 | - | A | |"
} > "$DWSMAIN2/vault/plans/P-TEST.md"
git -C "$DWSMAIN2" add -A
git -C "$DWSMAIN2" -c user.email=t@example.com -c user.name=t commit -q -m plan
DWSLEAF2="$(smoke_tmpdir)" || abort_tmp; rmdir "$DWSLEAF2"
git -C "$DWSMAIN2" worktree add -q -b work/p-delegate-stop-fail "$DWSLEAF2" >/dev/null 2>&1
mkdir -p "$DWSLEAF2/.claude/hooks"
cat > "$DWSLEAF2/.claude/hooks/stop_gate.py" <<'PYEOF'
#!/usr/bin/env python3
import sys
sys.exit(1)
PYEOF
expect "(delegate stop_gate) 委譲先 subprocess が非0で終了 → フェイルオープンでメインリポジトリ側のローカル判定にフォールバック（verdict 無しのブロックが引き続き効く）" block \
  "$(printf '%s' '{"cwd":"'"$DWSLEAF2"'"}' | CLAUDE_PROJECT_DIR="$DWSMAIN2" python3 "$STOP_HOOK")" "verifier"
git -C "$DWSMAIN2" worktree remove -q --force "$DWSLEAF2" >/dev/null 2>&1
rm -rf "$DWSMAIN2" "$DWSLEAF2"

echo "== agent_write_guard.py =="
run_guard() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TMP" python3 "$GUARD_HOOK"; }
expect_guard() { # $1=name $2=deny|allow $3=output
  local got="allow"; echo "$3" | grep -q '"permissionDecision": *"deny"' && got="deny"
  if [ "$got" = "$2" ]; then echo "  ok   $1"; PASS_N=$((PASS_N+1)); else echo "  NG   $1 (want=$2 got=$got)"; echo "       out: $3"; FAIL_N=$((FAIL_N+1)); fi
}
expect_guard "verifier が vault/verdicts/ に Write → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/verdicts/T-0001.json"}}')"
expect_guard "verifier が README.md に Edit → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Edit","tool_input":{"file_path":"'"$TMP"'/README.md"}}')"
expect_guard "verifier が Bash でテスト実行 → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"python3 -m pytest -q"}}')"
expect_guard "planner が vault/tasks/ に Write → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/tasks/T-0002.md"}}')"
expect_guard "メインエージェントが README.md に Edit → 許可" allow \
  "$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP"'/README.md"}}')"

GTMP="$(smoke_tmpdir)" || abort_tmp
git -C "$GTMP" init -q -b main
git -C "$GTMP" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
expect_guard "(guard3-b) main で git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard3-b) main で && 連結の git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git add a && git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard3-b) main で ; 連結の git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo x; git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard3-b) main で改行区切りの git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo a\ngit commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard3-b) main で git -C . commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -C . commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard-b2-1) main で grep の引数の git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep -n \"git commit\" scripts/smoke.sh"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard-b2-2) main で引用符の中の区切りと git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo '"'"'a; git commit -m x'"'"'"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard-b2-3) main で git log --grep commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git log --grep commit"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard-b2-4) main で || 連結の git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"true || git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard-b2-5) main で | 連結の git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"true | git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard-b2-6) main で git -C /tmp/x commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -C /tmp/x commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard-b2-7) main で git -c user.name=a commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -c user.name=a commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(i) main で git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
git -C "$GTMP" checkout -q -b work/p-test
expect_guard "(j) work ブランチで git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(guard3-b) work/p-test で git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
git -C "$GTMP" checkout -q main
git -C "$GTMP" checkout -q -b design/d-999
expect_guard "(k) design/d-999 ブランチで git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(l) design/d-999 ブランチで vault/designs/D-999.md へ Write → 許可" allow \
  "$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$GTMP"'/vault/designs/D-999.md"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
git -C "$GTMP" checkout -q --detach
expect_guard "(guard3-b) detached HEAD で git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
rm -rf "$GTMP"

expect_guard "creator が README.md に Write → 許可" allow \
  "$(run_guard '{"agent_type":"creator","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/README.md"}}')"

WMAIN="$(smoke_tmpdir)" || abort_tmp
git -C "$WMAIN" init -q -b main
git -C "$WMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
WLEAF="$(smoke_tmpdir)" || abort_tmp; rmdir "$WLEAF"
git -C "$WMAIN" worktree add -q -b work/p-wt "$WLEAF" >/dev/null 2>&1
mkdir -p "$WLEAF/vault/verdicts"
expect_guard "(worktree) verifier が worktree 内の vault/verdicts/ に Write（CLAUDE_PROJECT_DIR はメインチェックアウト側のまま）→ 許可" allow \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$WLEAF"'/vault/verdicts/T-1.json"}}' | CLAUDE_PROJECT_DIR="$WMAIN" python3 "$GUARD_HOOK")"
git -C "$WMAIN" worktree remove -q --force "$WLEAF" >/dev/null 2>&1
rm -rf "$WMAIN" "$WLEAF"

WMAIN2="$(smoke_tmpdir)" || abort_tmp
git -C "$WMAIN2" init -q -b main
git -C "$WMAIN2" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
WLEAF2="$(smoke_tmpdir)" || abort_tmp; rmdir "$WLEAF2"
git -C "$WMAIN2" worktree add -q -b work/p-wt-nested "$WLEAF2" >/dev/null 2>&1
expect_guard "(worktree nested) verifier が worktree 内の未作成ネストディレクトリ vault/verdicts/P-NEW/ に Write（事前 mkdir なし）→ 許可" allow \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$WLEAF2"'/vault/verdicts/P-NEW/T-1.json"}}' | CLAUDE_PROJECT_DIR="$WMAIN2" python3 "$GUARD_HOOK")"
git -C "$WMAIN2" worktree remove -q --force "$WLEAF2" >/dev/null 2>&1
rm -rf "$WMAIN2" "$WLEAF2"

# 委譲判定を確認するテストでは、verifier の worktree 内 README.md への Write をローカル判定の目印にする
# （委譲されなければ (c) の規則で拒否される）。
DWTMAIN="$(smoke_tmpdir)" || abort_tmp
git -C "$DWTMAIN" init -q -b main
git -C "$DWTMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
DWTLEAF="$(smoke_tmpdir)" || abort_tmp; rmdir "$DWTLEAF"
git -C "$DWTMAIN" worktree add -q -b work/p-delegate "$DWTLEAF" >/dev/null 2>&1
mkdir -p "$DWTLEAF/.claude/hooks"
cat > "$DWTLEAF/.claude/hooks/agent_write_guard.py" <<'PYEOF'
#!/usr/bin/env python3
import json, sys
json.load(sys.stdin)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}))
PYEOF
expect_guard "(delegate) worktree 側が常に allow を返す差し替え → 通常なら拒否される verifier の README.md への Write も委譲先の判定（allow）が採用される" allow \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$DWTLEAF"'/README.md"},"cwd":"'"$DWTLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWTMAIN" python3 "$GUARD_HOOK")"

expect_guard "(delegate) 呼び出し前に _HOOK_DELEGATED が既にセット済み → 二重委譲を防止しローカル判定にフォールバック（verifier の書き込み先制限が効く）" deny \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$DWTLEAF"'/README.md"},"cwd":"'"$DWTLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWTMAIN" _HOOK_DELEGATED=1 python3 "$GUARD_HOOK")"

git -C "$DWTMAIN" worktree remove -q --force "$DWTLEAF" >/dev/null 2>&1
rm -rf "$DWTMAIN" "$DWTLEAF"

DWTMAIN2="$(smoke_tmpdir)" || abort_tmp
git -C "$DWTMAIN2" init -q -b main
git -C "$DWTMAIN2" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
DWTLEAF2="$(smoke_tmpdir)" || abort_tmp; rmdir "$DWTLEAF2"
git -C "$DWTMAIN2" worktree add -q -b work/p-delegate-fail "$DWTLEAF2" >/dev/null 2>&1
mkdir -p "$DWTLEAF2/.claude/hooks"
cat > "$DWTLEAF2/.claude/hooks/agent_write_guard.py" <<'PYEOF'
#!/usr/bin/env python3
import sys
sys.exit(1)
PYEOF
expect_guard "(delegate) 委譲先 subprocess が非0で終了 → フェイルオープンでメインリポジトリ側のローカル判定にフォールバック（verifier の書き込み先制限が引き続き効く）" deny \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$DWTLEAF2"'/README.md"},"cwd":"'"$DWTLEAF2"'"}' | CLAUDE_PROJECT_DIR="$DWTMAIN2" python3 "$GUARD_HOOK")"
git -C "$DWTMAIN2" worktree remove -q --force "$DWTLEAF2" >/dev/null 2>&1
rm -rf "$DWTMAIN2" "$DWTLEAF2"

# done タスクへの書き込み拒否（issue #76 / D-010 フェーズ2）。expect_guard を拡張し、4番目の
# 引数で reason に含むべき部分文字列も確認できるようにする。
expect_guard() { # $1=name $2=deny|allow $3=output $4=reason に含むべき部分文字列(optional)
  local name="$1" want="$2" out="$3" sub="${4:-}"
  local got="allow"; echo "$out" | grep -q '"permissionDecision": *"deny"' && got="deny"
  if [ "$got" = "$want" ] && { [ -z "$sub" ] || echo "$out" | grep -q -- "$sub"; }; then
    echo "  ok   $name"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $name (want=$want got=$got sub='$sub')"; echo "       out: $out"; FAIL_N=$((FAIL_N+1))
  fi
}
make_plan "P-FIX" "approved" "| T-01 | done | 1 | - | done task | |" "| T-02 | doing | 1 | - | doing task | |" "| T-03 | review | 1 | - | review task | |"
expect_guard "(done-write) done のタスク票への Write → 拒否（reason に done を含む）" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"vault/tasks/P-FIX/T-01.md"}}')" "done"
expect_guard "(done-write) done の verdict への Write（agent_type=verifier でも）→ 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(done-write) doing のタスク票への Write → 許可（従来どおり）" allow \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"vault/tasks/P-FIX/T-02.md"}}')"
expect_guard "(done-write) review の verdict への Write（agent_type=verifier）→ 許可（従来どおり）" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"vault/verdicts/P-FIX/T-03.json"}}')"
expect_guard "(done-write) 計画票が存在しない計画 ID 配下のタスク票への Write → 許可（fail-open）" allow \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"vault/tasks/P-NOPLAN/T-01.md"}}')"
# (guard3-a) done のタスク票・verdict への Write 系の拒否（Bash は見ない）
expect_guard "(guard3-a) メインの done のタスク票への Edit → 拒否（reason に done）" deny \
  "$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"vault/tasks/P-FIX/T-01.md"}}')" "done"
expect_guard "(guard3-a) verifier の done の verdict への Write → 拒否（reason に done）" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(guard3-a) メインの doing のタスク票への Edit → 許可" allow \
  "$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"vault/tasks/P-FIX/T-02.md"}}')"
expect_guard "(guard3-a) メインの Bash で done のタスク票へ追記 → 許可（Bash は見ない）" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"printf x >> vault/tasks/P-FIX/T-01.md"}}')"

# (guard3-c) verifier の書き込み先は vault/verdicts/ に限る（Write 系のみ。Bash は制限しない）
expect_guard "(guard3-c) verifier の vault/verdicts/ への Write → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/verdicts/P-X/T-01.json"}}')"
expect_guard "(guard3-c) verifier の README.md への Write → 拒否（reason に verifier）" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/README.md"}}')" "verifier"
expect_guard "(guard3-c) verifier の README.md への Edit → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Edit","tool_input":{"file_path":"'"$TMP"'/README.md"}}')"
expect_guard "(guard3-c) verifier の Bash echo x > README.md → 許可（verifier の Bash は制限しない）" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"echo x > README.md"}}')"

# (guard3-free) 削った判定が効かないこと（すべて許可）
expect_guard "(guard3-free) creator の vault/rules/ への Write → 許可" allow \
  "$(run_guard '{"agent_type":"creator","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
expect_guard "(guard3-free) メインの vault/rules/ への Write → 許可" allow \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
expect_guard "(guard3-free) creator の Bash python3 -c で vault/rules/ へ書く → 許可" allow \
  "$(run_guard '{"agent_type":"creator","tool_name":"Bash","tool_input":{"command":"python3 -c \"open('"'"'vault/rules/a.md'"'"','"'"'w'"'"')\""}}')"
expect_guard "(guard3-free) メインの Bash echo x > vault/rules/a.md → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"echo x > vault/rules/a.md"}}')"
expect_guard "(guard3-free) creator の vault/plans/ への Write → 許可" allow \
  "$(run_guard '{"agent_type":"creator","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/plans/P-X.md"}}')"
expect_guard "(guard3-free) planner の README.md への Write → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/README.md"}}')"
expect_guard "(guard3-free) メインの gh api で vault/rules/ へ PUT → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"gh api -X PUT repos/o/r/contents/vault/rules/common/roles.md -f content=Zm9v"}}')"
FREE_HOME="$TMP/free-home"
mkdir -p "$FREE_HOME/.claude/projects/x"
run_guard_home() { printf '%s' "$1" | HOME="$FREE_HOME" CLAUDE_PROJECT_DIR="$TMP" python3 "$GUARD_HOOK"; }
expect_guard "(guard3-free) HOME 配下 .claude/projects/ への Write → 許可" allow \
  "$(run_guard_home '{"tool_name":"Write","tool_input":{"file_path":"'"$FREE_HOME"'/.claude/projects/x/s.jsonl"}}')"

# 計画票の承認（draft→approved）は判定しない（D-015 フェーズ2。/plan が自動で承認する）
# make_transcript は後ろの節でも流用する。パスは $TMP 配下（実行ごとに一意。引数の各行を JSONL として書く）
AP_TRANSCRIPT="$TMP/approve-transcript.jsonl"
AP_NONEXIST="$TMP/approve-nonexistent.jsonl"
make_transcript() { printf '%s\n' "$@" > "$AP_TRANSCRIPT"; }
T_CHAT='{"type":"user","message":{"role":"user","content":"こんにちは"}}'
TP='"transcript_path":"'"$AP_TRANSCRIPT"'"'
make_plan "P-TEST" "draft" "| T-01 | todo | 0 | - | A | |"
make_transcript "$T_CHAT"
expect_guard "(approve-free-1) /plan approve 無し・メインの Edit で draft→approved → 許可" allow "$(run_guard '{'"$TP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"status: draft","new_string":"status: approved"}}')"
expect_guard "(approve-free-2) /plan approve 無し・メインの MultiEdit で draft→approved → 許可" allow "$(run_guard '{'"$TP"',"tool_name":"MultiEdit","tool_input":{"file_path":"vault/plans/P-TEST.md","edits":[{"old_string":"# ゴール","new_string":"# ゴール2"},{"old_string":"status: draft","new_string":"status: approved"}]}}')"
expect_guard "(approve-free-3) /plan approve 無し・メインの Write で approved の計画票 → 許可" allow "$(run_guard '{'"$TP"',"tool_name":"Write","tool_input":{"file_path":"vault/plans/P-TEST.md","content":"---\nid: P-TEST\nstatus: approved\n---\n# ゴール\n"}}')"
rm -f "$AP_TRANSCRIPT"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"

WDSMAIN="$(smoke_tmpdir)" || abort_tmp
git -C "$WDSMAIN" init -q -b main
git -C "$WDSMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
WDSLEAF="$(smoke_tmpdir)" || abort_tmp; rmdir "$WDSLEAF"
git -C "$WDSMAIN" worktree add -q -b work/p-wds "$WDSLEAF" >/dev/null 2>&1
mkdir -p "$WDSMAIN/vault/rules" "$WDSLEAF/.claude/hooks"
cat > "$WDSLEAF/.claude/hooks/agent_write_guard.py" <<'PYEOF'
#!/usr/bin/env python3
import json, sys
json.load(sys.stdin)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "(wds-stub)"}}))
PYEOF
expect_guard "(wds-1) verifier のメインリポジトリの README.md（worktree の外）への Write → 委譲せず拒否" deny \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$WDSMAIN"'/README.md"},"cwd":"'"$WDSLEAF"'"}' | CLAUDE_PROJECT_DIR="$WDSMAIN" python3 "$GUARD_HOOK")" "verifier"
expect_guard "(wds-2) verifier の worktree 内の README.md への Write → 委譲される" allow \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$WDSLEAF"'/README.md"},"cwd":"'"$WDSLEAF"'"}' | CLAUDE_PROJECT_DIR="$WDSMAIN" python3 "$GUARD_HOOK")" "(wds-stub)"
expect_guard "(wds-3) Bash ls → 委譲される" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"'"$WDSLEAF"'"}' | CLAUDE_PROJECT_DIR="$WDSMAIN" python3 "$GUARD_HOOK")" "(wds-stub)"
expect_guard "(wds-4) Bash touch <メインリポジトリ>/x.txt → 常に委譲される" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"touch '"$WDSMAIN"'/x.txt"},"cwd":"'"$WDSLEAF"'"}' | CLAUDE_PROJECT_DIR="$WDSMAIN" python3 "$GUARD_HOOK")" "(wds-stub)"
git -C "$WDSMAIN" worktree remove -q --force "$WDSLEAF" >/dev/null 2>&1
rm -rf "$WDSMAIN" "$WDSLEAF"

echo "== plan_guard.py =="
run_plan_guard() { printf '{"hook_event_name":"PostToolUse","tool_name":"Edit"}' | CLAUDE_PROJECT_DIR="$TMP" python3 "$PLAN_GUARD_HOOK"; }

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
make_plan "P-TEST" "approved" "| T-0001 | doing | 1 | - | A | |" "| T-0002 | doing | 1 | - | B | |"
expect "(a-1) doing が2件、依存無し → 許可（着手可能集合なら複数可）" allow "$(run_plan_guard)"
make_plan "P-TEST" "approved" "| T-0001 | todo | 0 | - | A | |" "| T-0002 | doing | 1 | T-0001 | B | |"
expect "(a-2) doing の after が未完了の他タスクを指す → ブロック" block "$(run_plan_guard)" "未完了の依存"
make_plan "P-TEST" "approved" "| T-0001 | doing | 1 | T-0002 | A | |" "| T-0002 | doing | 1 | T-0001 | B | |"
expect "(a-3) doing 同士が相互に after で参照し合う → ブロック" block "$(run_plan_guard)" "未完了の依存"
make_plan "P-TEST" "approved" "| T-0001 | doing | 1 | - | A | |"
expect "(a-4) doing が単一（依存無し）→ 許可（既存シナリオの回帰確認）" allow "$(run_plan_guard)"
make_plan "P-TEST" "approved" "| T-0001 | done | 1 | - | A | |" "| T-0002 | doing | 1 | T-0001 | B | |"
make_verdict T-0001 1 PASS
expect "(a-5) doing の after が done なタスクを指す → 許可" allow "$(run_plan_guard)"
make_plan "P-TEST" "approved" "| T-0001 | blocked | 1 | - | A | |"
expect "(b) blocked なのに question が空 → ブロック" block "$(run_plan_guard)" "question"
make_plan "P-TEST" "approved" "| T-0001 | pending | 0 | - | A | |"
expect "(c) status が5値以外 → ブロック" block "$(run_plan_guard)" "status"
make_plan "P-TEST" "approved" "| T-0001 | todo | 0 | - | A | |" "| T-0001 | done | 1 | - | B | |"
expect "(d) id が重複 → ブロック" block "$(run_plan_guard)" "重複"
make_plan "P-TEST" "approved" "| T-0001 | todo | 0 | - | A |"
expect "(e) データ行の列数が6でない → ブロック" block "$(run_plan_guard)" "列数"
make_plan "P-TEST" "approved" "| T-0001 | done | 1 | - | A | |" "| T-0002 | doing | 2 | T-0001 | B | |" "| T-0003 | blocked | 1 | - | C | 方針を決めてほしい |"
make_verdict T-0001 1 PASS
expect "正常な計画票（doing 1件・blocked に question あり）→ 許可" allow "$(run_plan_guard)"
make_plan "P-TEST" "approved"
expect "データ行が無い → 許可" allow "$(run_plan_guard)"
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
expect "(f) approved な計画票が0件 → 許可" allow "$(run_plan_guard)"
make_plan "P-A" "approved" "| T-0001 | todo | 0 | - | A | |"
make_plan "P-B" "approved" "| T-0001 | todo | 0 | - | B | |"
expect "(f) approved な計画票が2件以上 → ブロック" block "$(run_plan_guard)" "approved"
rm -rf "$TMP/vault/plans"
EMPTY_DIR="$(smoke_tmpdir)" || abort_tmp
expect "vault/plans が無い → 許可" allow "$(printf '{}' | CLAUDE_PROJECT_DIR="$EMPTY_DIR" python3 "$PLAN_GUARD_HOOK")"
rm -rf "$EMPTY_DIR"
mkdir -p "$TMP/vault/plans"

# タスク票の粒度検査（D-010 フェーズ3）
run_plan_guard_file() { # $1=tool_name $2=file_path
  printf '{"hook_event_name":"PostToolUse","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" \
    | CLAUDE_PROJECT_DIR="$TMP" python3 "$PLAN_GUARD_HOOK"
}
make_plan "P-TEST" "draft" "| T-01 | todo | 0 | - | A | |"
make_task T-01 2; expect "(granularity-task) draft・基準2行 → ブロック（行数2）" block "$(run_plan_guard_file Write "$TMP/vault/tasks/P-TEST/T-01.md")" "2行"
make_task T-01 8; expect "(granularity-task) draft・基準8行 → ブロック（行数8）" block "$(run_plan_guard_file Edit "$TMP/vault/tasks/P-TEST/T-01.md")" "8行"
make_task T-01 8; expect "(granularity-task) draft・基準8行・相対パス → ブロック" block "$(run_plan_guard_file Write "vault/tasks/P-TEST/T-01.md")" "8行"
make_task T-01 3; expect "(granularity-task) draft・基準3行 → 許可" allow "$(run_plan_guard_file Write "$TMP/vault/tasks/P-TEST/T-01.md")"
make_task T-01 7; expect "(granularity-task) draft・基準7行 → 許可" allow "$(run_plan_guard_file Write "$TMP/vault/tasks/P-TEST/T-01.md")"
make_task T-01 8; cp "$TMP/vault/tasks/P-TEST/T-01.md" "$TMP/vault/tasks/P-TEST/T-01-proposal.md"
expect "(granularity-task) T-01-proposal.md は対象外 → 許可" allow "$(run_plan_guard_file Write "$TMP/vault/tasks/P-TEST/T-01-proposal.md")"
expect "(granularity-task) Bash による書き込みは対象外 → 許可" allow "$(run_plan_guard_file Bash "$TMP/vault/tasks/P-TEST/T-01.md")"
make_plan "P-TEST" "approved" "| T-01 | doing | 1 | - | A | |"
expect "(granularity-task) approved・基準8行 → 許可（検査しない）" allow "$(run_plan_guard_file Write "$TMP/vault/tasks/P-TEST/T-01.md")"
rm -f "$TMP/vault/plans/P-TEST.md"
expect "(granularity-task) 計画票が無い・基準8行 → 許可（fail-open）" allow "$(run_plan_guard_file Write "$TMP/vault/tasks/P-TEST/T-01.md")"
rm -rf "$TMP/vault/tasks"

# 計画票のタスク表行数検査（D-010 フェーズ3）
make_plan_n() { # $1=planStatus $2=データ行数
  local rows=() i
  for i in $(seq 1 "$2"); do rows+=("| T-$i | todo | 0 | - | A$i | |"); done
  make_plan "P-TEST" "$1" "${rows[@]}"
}
make_plan_n draft 8; expect "(granularity-plan) draft・タスク表8行 → ブロック（行数8・上限7）" block "$(run_plan_guard_file Write "$TMP/vault/plans/P-TEST.md")" "8行"
printf '%s' "$(run_plan_guard_file Edit "$TMP/vault/plans/P-TEST.md")" | grep -q '7タスク' \
  && expect "(granularity-plan) reason に上限7を含む" block "$(run_plan_guard_file Edit "$TMP/vault/plans/P-TEST.md")" "7タスク" \
  || expect "(granularity-plan) reason に上限7を含む" block "" "7タスク"
make_plan_n draft 8; expect "(granularity-plan) draft・8行・相対パス → ブロック" block "$(run_plan_guard_file Write "vault/plans/P-TEST.md")" "8行"
make_plan_n draft 7; expect "(granularity-plan) draft・タスク表7行 → 許可" allow "$(run_plan_guard_file Write "$TMP/vault/plans/P-TEST.md")"
make_plan_n approved 8; expect "(granularity-plan) approved・タスク表8行 → 粒度検査ではブロックしない" allow "$(run_plan_guard_file Write "$TMP/vault/plans/P-TEST.md")"
make_plan_n draft 8; expect "(granularity-plan) Bash による書き込みは対象外 → 許可" allow "$(run_plan_guard_file Bash "$TMP/vault/plans/P-TEST.md")"
rm -f "$TMP/vault/plans/P-TEST.md"
expect "(granularity-plan) 計画票が無い → 許可（fail-open）" allow "$(run_plan_guard_file Write "$TMP/vault/plans/P-TEST.md")"

# 承認の裏付け検査（PostToolUse・D-010 フェーズ4 / T-04）。HEAD と作業ツリーの計画票を比べる。
# git フィクスチャは $TMP 配下（実行ごとに一意）。git init し直した上で HEAD と index を空にして使う（rm -rf は使わない）
AP_REPO="$TMP/approve-post-repo"
ap_git() { git -C "$AP_REPO" -c user.name=t -c user.email=t@example.com "$@"; }
ap_reset() {
  mkdir -p "$AP_REPO/vault/plans"
  git -C "$AP_REPO" init -q
  git -C "$AP_REPO" update-ref -d HEAD 2>/dev/null
  git -C "$AP_REPO" rm -r --cached -q --ignore-unmatch . >/dev/null 2>&1
  rm -f "$AP_REPO"/vault/plans/*.md "$AP_REPO"/other.txt
}
ap_plan() { # $1=status  作業ツリーに P-TEST を書く
  printf -- '---\nid: P-TEST\nstatus: %s\n---\n# ゴール\n\n## タスク表（状態の正本）\n| id | status | attempt | after | title | question |\n|---|---|---|---|---|---|\n| T-01 | todo | 0 | - | A | |\n' "$1" > "$AP_REPO/vault/plans/P-TEST.md"
}
ap_commit_plan() { ap_plan "$1"; ap_git add vault/plans/P-TEST.md; ap_git commit -q -m "plan $1"; }
run_ap_post() { # $1=transcript_path（空なら省略）
  local tp=""; [ -n "${1:-}" ] && tp=',"transcript_path":"'"$1"'"'
  printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"sed -i x"}%s}' "$tp" \
    | CLAUDE_PROJECT_DIR="$AP_REPO" python3 "$PLAN_GUARD_HOOK"
}
# 承認と unblock の裏付けの検査はしない（D-015 フェーズ2）
NC_TRANSCRIPT="$TMP/no-check-transcript.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"こんにちは"}}' > "$NC_TRANSCRIPT"
ap_reset; ap_commit_plan draft; ap_plan approved
if [ -z "$(run_ap_post "$NC_TRANSCRIPT")" ]; then echo "  ok   (no-approve-check-1) HEAD は draft・作業ツリーは approved・/plan approve 無し → 出力なし)"; PASS_N=$((PASS_N+1)); else echo "  NG   (no-approve-check-1) 出力あり)"; FAIL_N=$((FAIL_N+1)); fi
if [ -z "$(run_ap_post "")" ]; then echo "  ok   (no-approve-check-2) 会話記録が無い → 出力なし（警告も出さない）)"; PASS_N=$((PASS_N+1)); else echo "  NG   (no-approve-check-2) 出力あり)"; FAIL_N=$((FAIL_N+1)); fi
sed -i.bak 's/| T-01 | todo | 0 | - | A | |/| T-01 | todo | 0 | - | A |/' "$AP_REPO/vault/plans/P-TEST.md"; rm -f "$AP_REPO/vault/plans/P-TEST.md.bak"
expect "(no-approve-check-3) 列数の不正は今どおりブロック" block "$(run_ap_post "$NC_TRANSCRIPT")" "列数"

# blocked の解除の裏付け検査（PostToolUse・D-010 フェーズ5 / T-02）。HEAD の blocked 行が作業ツリーで変わったかを見る
UP_REPO="$TMP/unblock-post-repo"
up_git() { git -C "$UP_REPO" -c user.name=t -c user.email=t@example.com "$@"; }
up_reset() {
  mkdir -p "$UP_REPO/vault/plans"
  git -C "$UP_REPO" init -q
  git -C "$UP_REPO" update-ref -d HEAD 2>/dev/null
  git -C "$UP_REPO" rm -r --cached -q --ignore-unmatch . >/dev/null 2>&1
  rm -f "$UP_REPO"/vault/plans/*.md "$UP_REPO"/other.txt
}
up_plan() { # $1=T-01 の行の status  $2=T-02 の行の status（T-02 が blocked の時だけ question を入れる）
  local q=""; [ "$2" = blocked ] && q="どうする"
  printf -- '---\nid: P-TEST\nstatus: %s\n---\n# ゴール\n\n## タスク表（状態の正本）\n| id | status | attempt | after | title | question |\n|---|---|---|---|---|---|\n| T-01 | %s | 0 | - | A | |\n| T-02 | %s | 1 | - | B | %s |\n' "${UP_STATUS:-approved}" "$1" "$2" "$q" > "$UP_REPO/vault/plans/P-TEST.md"
}
up_commit() { up_plan "$1" "$2"; up_git add vault/plans/P-TEST.md; up_git commit -q -m plan; }
run_up_post() { # $1=transcript_path（空なら省略）
  local tp=""; [ -n "${1:-}" ] && tp=',"transcript_path":"'"$1"'"'
  printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"sed -i x"}%s}' "$tp" \
    | CLAUDE_PROJECT_DIR="$UP_REPO" python3 "$PLAN_GUARD_HOOK"
}
up_reset; up_commit todo blocked; up_plan todo todo
if [ -z "$(run_up_post "$NC_TRANSCRIPT")" ]; then echo "  ok   (no-unblock-check-1) HEAD で blocked の T-02 が作業ツリーで todo・/plan unblock 無し → 出力なし)"; PASS_N=$((PASS_N+1)); else echo "  NG   (no-unblock-check-1) 出力あり)"; FAIL_N=$((FAIL_N+1)); fi
if [ -z "$(run_up_post "")" ]; then echo "  ok   (no-unblock-check-2) 会話記録が無い → 出力なし（警告も出さない）)"; PASS_N=$((PASS_N+1)); else echo "  NG   (no-unblock-check-2) 出力あり)"; FAIL_N=$((FAIL_N+1)); fi
rm -f "$NC_TRANSCRIPT"

# worktree 委譲（issue #56 / D-008 フェーズ2）。agent_write_guard.py の (delegate) テストと同じ型：
# 一時 worktree に判定結果が変わる差し替えスクリプトを置き、cwd をその worktree に向けたペイロードを
# メインリポジトリ側の plan_guard.py に渡す。
DWPMAIN="$(smoke_tmpdir)" || abort_tmp
git -C "$DWPMAIN" init -q -b main
git -C "$DWPMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
mkdir -p "$DWPMAIN/vault/plans"
{
  echo "---"; echo "id: P-TEST"; echo "status: approved"; echo "---"
  echo "# ゴール"; echo; echo "## タスク表（状態の正本）"
  echo "| id | status | attempt | after | title | question |"
  echo "|---|---|---|---|---|---|"
  echo "| T-0001 | done | 1 | - | A | |"
} > "$DWPMAIN/vault/plans/P-TEST.md"
mkdir -p "$DWPMAIN/vault/verdicts/P-TEST"
printf '%s\n' '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"2026-01-01 00:00","criteria":[],"reasons":["r1"]}' > "$DWPMAIN/vault/verdicts/P-TEST/T-0001.json"
DWPLEAF="$(smoke_tmpdir)" || abort_tmp; rmdir "$DWPLEAF"
git -C "$DWPMAIN" worktree add -q -b work/p-delegate-plan "$DWPLEAF" >/dev/null 2>&1
mkdir -p "$DWPLEAF/.claude/hooks"
cat > "$DWPLEAF/.claude/hooks/plan_guard.py" <<'PYEOF'
#!/usr/bin/env python3
import json, sys
json.load(sys.stdin)
print(json.dumps({"decision": "block", "reason": "(delegate plan_guard) worktree override"}))
PYEOF
expect "(delegate plan_guard) worktree 側が常に block を返す差し替え → 通常なら許可される正常な計画票でも委譲先の判定（block）が採用される" block \
  "$(printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Edit","cwd":"'"$DWPLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWPMAIN" python3 "$PLAN_GUARD_HOOK")" "(delegate plan_guard)"

expect "(delegate plan_guard) 呼び出し前に _HOOK_DELEGATED が既にセット済み → 二重委譲を防止しローカル判定にフォールバック（正常な計画票は許可）" allow \
  "$(printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Edit","cwd":"'"$DWPLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWPMAIN" _HOOK_DELEGATED=1 python3 "$PLAN_GUARD_HOOK")"

git -C "$DWPMAIN" worktree remove -q --force "$DWPLEAF" >/dev/null 2>&1
rm -rf "$DWPMAIN" "$DWPLEAF"

DWPMAIN2="$(smoke_tmpdir)" || abort_tmp
git -C "$DWPMAIN2" init -q -b main
git -C "$DWPMAIN2" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
mkdir -p "$DWPMAIN2/vault/plans"
{
  echo "---"; echo "id: P-TEST"; echo "status: approved"; echo "---"
  echo "# ゴール"; echo; echo "## タスク表（状態の正本）"
  echo "| id | status | attempt | after | title | question |"
  echo "|---|---|---|---|---|---|"
  echo "| T-0001 | pending | 0 | - | A | |"
} > "$DWPMAIN2/vault/plans/P-TEST.md"
DWPLEAF2="$(smoke_tmpdir)" || abort_tmp; rmdir "$DWPLEAF2"
git -C "$DWPMAIN2" worktree add -q -b work/p-delegate-plan-fail "$DWPLEAF2" >/dev/null 2>&1
mkdir -p "$DWPLEAF2/.claude/hooks"
cat > "$DWPLEAF2/.claude/hooks/plan_guard.py" <<'PYEOF'
#!/usr/bin/env python3
import sys
sys.exit(1)
PYEOF
expect "(delegate plan_guard) 委譲先 subprocess が非0で終了 → フェイルオープンでメインリポジトリ側のローカル判定にフォールバック（不正な status のブロックが引き続き効く）" block \
  "$(printf '%s' '{"hook_event_name":"PostToolUse","tool_name":"Edit","cwd":"'"$DWPLEAF2"'"}' | CLAUDE_PROJECT_DIR="$DWPMAIN2" python3 "$PLAN_GUARD_HOOK")" "status"
git -C "$DWPMAIN2" worktree remove -q --force "$DWPLEAF2" >/dev/null 2>&1
rm -rf "$DWPMAIN2" "$DWPLEAF2"

echo "== done-verdict（D-012 フェーズ1） =="
rm -rf "$TMP/vault/plans" "$TMP/vault/verdicts" "$TMP/vault/tasks"; mkdir -p "$TMP/vault/plans"
make_plan_task T-0001 done 1; rm -f "$TMP/vault/verdicts/P-TEST/T-0001.json"
expect "(done-verdict stop_gate) done・verdict 無し → ブロック" block "$(run_stop)" "P-TEST/T-0001 は done ですが"
make_plan_task T-0001 done 1; make_verdict T-0001 1 FAIL
expect "(done-verdict stop_gate) done・FAIL → ブロック" block "$(run_stop)" "P-TEST/T-0001 は done ですが"
make_plan_task T-0001 done 2; make_verdict T-0001 1 PASS
expect "(done-verdict stop_gate) done・attempt 不一致 → ブロック" block "$(run_stop)" "P-TEST/T-0001 は done ですが"
make_plan_task T-0001 done 1; make_task T-0001 3; write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":['"$OK_C"','"$OK_C"'],"reasons":[]}'
expect "(done-verdict stop_gate) done・criteria の行数不一致 → ブロック" block "$(run_stop)" "P-TEST/T-0001 は done ですが"
rm -f "$TMP/vault/tasks/P-TEST/T-0001.md"
make_plan_task T-0001 done 1; make_verdict T-0001 1 PASS
expect "(done-verdict stop_gate) done・正しい PASS → 許可" allow "$(run_stop)"
make_plan_task T-0001 done 1; rm -f "$TMP/vault/verdicts/P-TEST/T-0001.json"
expect "(done-verdict plan_guard) done・verdict 無し → ブロック" block "$(run_plan_guard)" "P-TEST/T-0001 は done ですが"
make_plan_task T-0001 done 1; make_verdict T-0001 1 FAIL
expect "(done-verdict plan_guard) done・FAIL → ブロック" block "$(run_plan_guard)" "P-TEST/T-0001 は done ですが"
make_plan_task T-0001 done 2; make_verdict T-0001 1 PASS
expect "(done-verdict plan_guard) done・attempt 不一致 → ブロック" block "$(run_plan_guard)" "P-TEST/T-0001 は done ですが"
make_plan_task T-0001 done 1; make_task T-0001 3; write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":['"$OK_C"','"$OK_C"'],"reasons":[]}'
expect "(done-verdict plan_guard) done・criteria の行数不一致 → ブロック" block "$(run_plan_guard)" "P-TEST/T-0001 は done ですが"
rm -f "$TMP/vault/tasks/P-TEST/T-0001.md"
make_plan_task T-0001 done 1; make_verdict T-0001 1 PASS
expect "(done-verdict plan_guard) done・正しい PASS → 許可" allow "$(run_plan_guard)"
rm -rf "$TMP/vault/plans" "$TMP/vault/verdicts" "$TMP/vault/tasks"; mkdir -p "$TMP/vault/plans"

echo "== rules.sh =="
reset_rules() { rm -rf "$TMP/vault/rules"; }
make_rules_file() { mkdir -p "$TMP/vault/rules/$1"; echo x > "$TMP/vault/rules/$1/$2"; } # $1=dir $2=filename
run_rules() { CLAUDE_PROJECT_DIR="$TMP" bash "$RULES_SH" "$1" 2>/dev/null; } # $1=role
expect_rules() { # $1=name $2=want_rc $3=want_out $4=got_rc $5=got_out
  local name="$1" want_rc="$2" want_out="$3" got_rc="$4" got_out="$5"
  if [ "$got_rc" = "$want_rc" ] && [ "$got_out" = "$want_out" ]; then
    echo "  ok   $name"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $name (want_rc=$want_rc got_rc=$got_rc)"; echo "       want_out: $want_out"; echo "       got_out : $got_out"; FAIL_N=$((FAIL_N+1))
  fi
}

reset_rules
make_rules_file common a-common.md
make_rules_file common b-common.md
make_rules_file creator c-creator.md
make_rules_file verifier d-verifier.md
make_rules_file planner e-planner.md

out="$(run_rules creator)"; rc=$?
expect_rules "(a) creator → common(a,b)→creator(c) の順で列挙" 0 \
  "$(printf 'vault/rules/common/a-common.md\nvault/rules/common/b-common.md\nvault/rules/creator/c-creator.md')" "$rc" "$out"

out="$(run_rules verifier)"; rc=$?
expect_rules "(b) verifier → creator/ を含まず common+verifier のみ" 0 \
  "$(printf 'vault/rules/common/a-common.md\nvault/rules/common/b-common.md\nvault/rules/verifier/d-verifier.md')" "$rc" "$out"

out="$(run_rules planner)"; rc=$?
expect_rules "(c) planner → common+planner のみ（creator/・verifier/ を含まない）" 0 \
  "$(printf 'vault/rules/common/a-common.md\nvault/rules/common/b-common.md\nvault/rules/planner/e-planner.md')" "$rc" "$out"

reset_rules
out="$(run_rules creator)"; rc=$?
expect_rules "(d) ルール未配置 → 無出力・exit 0" 0 "" "$rc" "$out"

out="$(bash "$RULES_SH" foo 2>/dev/null)"; rc=$?
expect_rules "(e) 不正な引数 → exit 2" 2 "" "$rc" "$out"
out="$(bash "$RULES_SH" 2>/dev/null)"; rc=$?
expect_rules "(e) 引数なし → exit 2" 2 "" "$rc" "$out"

echo "== merge_claude_md.py =="
MERGE_PY="$ROOT/scripts/merge_claude_md.py"
MTMP="$TMP/merge"
mkdir -p "$MTMP"
expect_eq() { # $1=name $2=want $3=got
  if [ "$3" = "$2" ]; then
    echo "  ok   $1"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $1 (want='$2' got='$3')"; FAIL_N=$((FAIL_N+1))
  fi
}

out="$(python3 "$MERGE_PY" "$ROOT/CLAUDE.md" "$MTMP/new/CLAUDE.md")"
expect_eq "(a) dst が無い → create" "create" "${out%% *}"
expect_eq "(a) 作成された CLAUDE.md が @import を含む" "1" "$(grep -c '@\.claude/ai-harness\.md' "$MTMP/new/CLAUDE.md")"

printf '# 既存プロジェクト\n\n- 既存のルール\n' > "$MTMP/CLAUDE.md"
out="$(python3 "$MERGE_PY" "$ROOT/CLAUDE.md" "$MTMP/CLAUDE.md")"
expect_eq "(b) 既存本文あり → merge" "merge" "${out%% *}"
expect_eq "(b) 既存行がそのまま残る" "1" "$(grep -c '^- 既存のルール$' "$MTMP/CLAUDE.md")"
expect_eq "(b) 末尾にブロックが付く" "1" "$(grep -c 'ai-harness:end' "$MTMP/CLAUDE.md")"
expect_eq "(b) バックアップが1つできる" "1" "$(ls "$MTMP" | grep -c '^CLAUDE\.md\.bak-')"

out="$(python3 "$MERGE_PY" "$ROOT/CLAUDE.md" "$MTMP/CLAUDE.md")"
expect_eq "(c) 同じ内容で再実行 → skip" "skip" "${out%% *}"
expect_eq "(c) begin の出現は1回のまま" "1" "$(grep -c 'ai-harness:begin' "$MTMP/CLAUDE.md")"

printf '<!-- ai-harness:begin v1 -->\n# 変更後の見出し\n@.claude/ai-harness.md\n<!-- ai-harness:end -->\n' > "$MTMP/src2.md"
out="$(python3 "$MERGE_PY" "$MTMP/src2.md" "$MTMP/CLAUDE.md")"
expect_eq "(d) ブロック本文が変わった → update" "update" "${out%% *}"
expect_eq "(d) 新しいブロックに置き換わる" "1" "$(grep -c '^# 変更後の見出し$' "$MTMP/CLAUDE.md")"
expect_eq "(d) 旧ブロックの行は消える" "0" "$(grep -c '^# AI協働ハーネス 共通ルール$' "$MTMP/CLAUDE.md")"
expect_eq "(d) マーカー外の既存本文は無傷" "1" "$(grep -c '^- 既存のルール$' "$MTMP/CLAUDE.md")"
expect_eq "(d) begin の出現は1回のまま" "1" "$(grep -c 'ai-harness:begin' "$MTMP/CLAUDE.md")"

echo "== install.sh の CLAUDE.md 扱い =="
ITMP="$(smoke_tmpdir)" || abort_tmp
printf '# 既存プロジェクト\n\n- 既存のルール\n' > "$ITMP/CLAUDE.md"
before="$(cat "$ITMP/CLAUDE.md")"
bash "$ROOT/scripts/install.sh" --no-claude-md "$ITMP" >/dev/null 2>&1
expect_eq "(e) --no-claude-md → CLAUDE.md は変更されない" "$before" "$(cat "$ITMP/CLAUDE.md")"
expect_eq "(e) --no-claude-md → バックアップも作られない" "0" "$(ls "$ITMP" | grep -c '^CLAUDE\.md\.bak-')"
out="$(bash "$ROOT/scripts/install.sh" "$ITMP" 2>&1)"
expect_eq "(f) 既定 → merge され既存行は残る" "1" "$(grep -c '^- 既存のルール$' "$ITMP/CLAUDE.md")"
expect_eq "(f) 既定 → ブロックが1つ入る" "1" "$(grep -c 'ai-harness:begin' "$ITMP/CLAUDE.md")"
expect_eq "(f) 既定 → merge_claude_md.py も複製される" "1" "$(ls "$ITMP/scripts" | grep -c '^merge_claude_md\.py$')"
bash "$ROOT/scripts/install.sh" "$ITMP" >/dev/null 2>&1
expect_eq "(f) 2回目の install → ブロックは1つのまま" "1" "$(grep -c 'ai-harness:begin' "$ITMP/CLAUDE.md")"
bash "$ROOT/scripts/install.sh" >/dev/null 2>&1; rc=$?
expect_eq "(g) 引数なし → exit 2" "2" "$rc"
bash "$ROOT/scripts/install.sh" --unknown "$ITMP" >/dev/null 2>&1; rc=$?
expect_eq "(g) 不正なオプション → exit 2" "2" "$rc"
rm -rf "$ITMP"

echo "== install.sh のマニフェスト =="
NTMP="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$NTMP" >/dev/null 2>&1
NMAN="$NTMP/.claude/harness-manifest.json"
expect_eq "(h) マニフェストが作られる" "1" "$([ -f "$NMAN" ] && echo 1 || echo 0)"
expect_eq "(h) files が1件以上" "True" \
  "$(python3 -c "import json;print(len(json.load(open('$NMAN'))['files']) >= 1)")"
expect_eq "(h) 代表2パスのハッシュが64桁16進" "True" \
  "$(python3 -c "import json,re;d=json.load(open('$NMAN'))['files'];print(bool(re.fullmatch('[0-9a-f]{64}',d['.claude/hooks/stop_gate.py'])) and bool(re.fullmatch('[0-9a-f]{64}',d['docs/vault-spec.md'])))")"
expect_eq "(h) 利用者の資産は含まれない" "False" \
  "$(python3 -c "import json;d=json.load(open('$NMAN'))['files'];print(any(k.startswith(('vault/plans/','vault/tasks/','vault/verdicts/','vault/log/','vault/archive/','vault/designs/')) for k in d))")"
printf -- '- 独自ルール\n' >> "$NTMP/vault/rules/README.md"
bash "$ROOT/scripts/install.sh" "$NTMP" >/dev/null 2>&1
expect_eq "(i) 記録は src のハッシュで dst とは一致しない" "True" \
  "$(python3 -c "
import hashlib, json
h = lambda p: hashlib.sha256(open(p,'rb').read()).hexdigest()
rel = 'vault/rules/README.md'
m = json.load(open('$NMAN'))['files'][rel]
print(m == h('$ROOT/' + rel) and m != h('$NTMP/' + rel))")"
expect_eq "(i) 編集した行はそのまま残る" "1" "$(grep -c '^- 独自ルール$' "$NTMP/vault/rules/README.md")"
rm -rf "$NTMP"

echo "== 参照される scripts の存在チェック =="
RSTMP="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$RSTMP" >/dev/null 2>&1
missing_referenced_scripts() { # $1=target dir。参照されているが <target>/scripts/ に無い名前を1行1つで返す（無ければ空）
  local target="$1" f name
  {
    find "$target/.claude" -path "$target/.claude/worktrees" -prune -o -type f -print 2>/dev/null
    find "$target/vault/rules" -type f 2>/dev/null
    find "$target/vault/templates" -type f 2>/dev/null
    [ -f "$target/docs/vault-spec.md" ] && echo "$target/docs/vault-spec.md"
    [ -f "$target/CLAUDE.md" ] && echo "$target/CLAUDE.md"
  } | while read -r f; do
    grep -Eo 'scripts/[A-Za-z0-9_.-]+\.(sh|py)' "$f" 2>/dev/null
  done | sed 's#^scripts/##' | sort -u | while read -r name; do
    [ -f "$target/scripts/$name" ] || echo "$name"
  done
}
expect_eq "新規インストール先で参照される scripts がすべて揃っている" "" "$(missing_referenced_scripts "$RSTMP")"
rm -rf "$RSTMP"

echo "== discard_worktree.sh =="
DWMAIN="$(smoke_tmpdir)" || abort_tmp
git -C "$DWMAIN" init -q -b main
git -C "$DWMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
dw_run() { ( cd "$DWMAIN" && bash "$ROOT/scripts/discard_worktree.sh" "$1" "$2" ) >/dev/null 2>&1; } # $1=path $2=branch

D_A="$(smoke_tmpdir)" || abort_tmp; rmdir "$D_A"
git -C "$DWMAIN" worktree add -q -b worktree-agent-test "$D_A"
dw_run "$D_A" worktree-agent-test; rc_a=$?
list_a="$(cd "$DWMAIN" && git worktree list --porcelain)"
verify_rc=0
(cd "$DWMAIN" && git rev-parse --verify worktree-agent-test) >/dev/null 2>&1; verify_rc=$?
result_a="False"
if [ "$rc_a" -eq 0 ] && ! printf '%s' "$list_a" | grep -q "$D_A" && [ "$verify_rc" -ne 0 ]; then result_a="True"; fi
expect_eq "(a) discard_worktree.sh 正常系: worktree/ブランチとも削除されrc0（git worktree list から消え rev-parse --verify worktree-agent-test が失敗）" "True" "$result_a"

D_B="$(smoke_tmpdir)" || abort_tmp; rmdir "$D_B"
git -C "$DWMAIN" worktree add -q -b other-branch "$D_B"
dw_run "$D_B" other-branch; rc_b=$?
list_b="$(cd "$DWMAIN" && git worktree list --porcelain)"
result_b="False"
if [ "$rc_b" -ne 0 ] && printf '%s' "$list_b" | grep -q "$D_B" && [ -d "$D_B" ]; then result_b="True"; fi
expect_eq "(b) discard_worktree.sh 拒否系: ブランチ名がworktree-agent-で始まらない場合は削除されずworktreeが残存" "True" "$result_b"
git -C "$DWMAIN" worktree remove --force "$D_B" >/dev/null 2>&1
git -C "$DWMAIN" branch -D other-branch >/dev/null 2>&1

D_C="$(smoke_tmpdir)" || abort_tmp; rmdir "$D_C"
dw_run "$D_C" worktree-agent-x; rc_c=$?
list_c="$(cd "$DWMAIN" && git worktree list --porcelain)"
result_c="False"
if [ "$rc_c" -ne 0 ] && ! printf '%s' "$list_c" | grep -q "$D_C" && [ ! -d "$D_C" ]; then result_c="True"; fi
expect_eq "(c) discard_worktree.sh 拒否系: 未登録パスは削除されず何も変更されない" "True" "$result_c"

D_D="$(smoke_tmpdir)" || abort_tmp; rmdir "$D_D"
git -C "$DWMAIN" worktree add -q -b worktree-agent-real "$D_D"
dw_run "$D_D" worktree-agent-fake; rc_d=$?
list_d="$(cd "$DWMAIN" && git worktree list --porcelain)"
result_d="False"
if [ "$rc_d" -ne 0 ] && printf '%s' "$list_d" | grep -q "$D_D" && [ -d "$D_D" ]; then result_d="True"; fi
expect_eq "(d) discard_worktree.sh 拒否系: パスのブランチが指定と不一致の場合は削除されずworktreeが残存" "True" "$result_d"
git -C "$DWMAIN" worktree remove --force "$D_D" >/dev/null 2>&1
git -C "$DWMAIN" branch -D worktree-agent-real >/dev/null 2>&1

rm -rf "$DWMAIN" "$D_A" "$D_B" "$D_C" "$D_D"

D_E_TARGET="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$D_E_TARGET" >/dev/null 2>&1
result_e_file="False"
[ -f "$D_E_TARGET/scripts/discard_worktree.sh" ] && result_e_file="True"
result_e_manifest="$(python3 -c "
import json, re
d = json.load(open('$D_E_TARGET/.claude/harness-manifest.json'))['files']
v = d.get('scripts/discard_worktree.sh', '')
print(bool(re.fullmatch('[0-9a-f]{64}', v)))
")"
result_e="False"
if [ "$result_e_file" = "True" ] && [ "$result_e_manifest" = "True" ]; then result_e="True"; fi
expect_eq "(e) discard_worktree.sh install先に配置されharness-manifest.jsonのfilesにハッシュ付きで載る" "True" "$result_e"
rm -rf "$D_E_TARGET"

echo "== install.sh --update =="
UTMP="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$UTMP" >/dev/null 2>&1
uout="$(bash "$ROOT/scripts/install.sh" --update "$UTMP" 2>&1)"
expect_eq "(j) 未編集は update として報告される" "1" \
  "$(echo "$uout" | grep -c '^update \.claude/hooks/stop_gate\.py$')"
expect_eq "(j) 未編集ファイルが src と一致する" "0" \
  "$(diff "$ROOT/.claude/hooks/stop_gate.py" "$UTMP/.claude/hooks/stop_gate.py" >/dev/null 2>&1; echo $?)"
expect_eq "(j) 上書き後のマニフェストが dst と一致する" "True" \
  "$(python3 -c "
import hashlib, json
m = json.load(open('$UTMP/.claude/harness-manifest.json'))['files']['docs/vault-spec.md']
print(m == hashlib.sha256(open('$UTMP/docs/vault-spec.md','rb').read()).hexdigest())")"
printf -- '- 独自ルール2\n' >> "$UTMP/vault/rules/README.md"
uout="$(bash "$ROOT/scripts/install.sh" --update "$UTMP" 2>&1)"
expect_eq "(k) 編集済みは skip (edited) で報告される" "1" \
  "$(echo "$uout" | grep -c '^skip (edited) vault/rules/README\.md$')"
expect_eq "(k) 編集した行は残る" "1" "$(grep -c '^- 独自ルール2$' "$UTMP/vault/rules/README.md")"
rm -f "$UTMP/.claude/harness-manifest.json"
ubefore="$(shasum "$UTMP/.claude/hooks/stop_gate.py" | cut -d' ' -f1)"
uout="$(bash "$ROOT/scripts/install.sh" --update "$UTMP" 2>&1)"
expect_eq "(l) マニフェスト無し → 既存は update されない" "0" "$(echo "$uout" | grep -c '^update ')"
expect_eq "(l) マニフェスト無し → 既存ファイルは上書きされない" "$ubefore" \
  "$(shasum "$UTMP/.claude/hooks/stop_gate.py" | cut -d' ' -f1)"
rm -rf "$UTMP"

echo "== merge_settings_json.py =="
SMERGE="$ROOT/scripts/merge_settings_json.py"
STMP="$(smoke_tmpdir)" || abort_tmp
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/new/settings.json")"
expect_eq "(m) dst が無い → create" "create" "${out%% *}"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/new/settings.json")"
expect_eq "(m) 同じ内容で再実行 → skip" "skip" "${out%% *}"
python3 -c "
import json, pathlib
d = json.load(open('$ROOT/.claude/settings.json'))
d['permissions']['allow'].append('Bash(独自コマンド *)')
d['permissions']['deny'].remove('Bash(sudo *)')
del d['hooks']['PostToolUse']
pathlib.Path('$STMP/settings.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/settings.json")"
expect_eq "(n) 欠けている要素がある → merge" "merge" "${out%% *}"
expect_eq "(n) allow の独自要素は残る" "True" \
  "$(python3 -c "import json;print('Bash(独自コマンド *)' in json.load(open('$STMP/settings.json'))['permissions']['allow'])")"
expect_eq "(n) 欠落した hooks エントリが復元される" "True" \
  "$(python3 -c "import json;d=json.load(open('$STMP/settings.json'));print(any('plan_guard.py' in h['command'] for e in d['hooks'].get('PostToolUse',[]) for h in e.get('hooks',[])))")"
expect_eq "(n) 欠落した deny 要素が復元される" "True" \
  "$(python3 -c "import json;print('Bash(sudo *)' in json.load(open('$STMP/settings.json'))['permissions']['deny'])")"
expect_eq "(n) バックアップが1つできる" "1" "$(ls "$STMP" | grep -c '^settings\.json\.bak-')"

python3 -c "
import json, pathlib
d = json.load(open('$ROOT/.claude/settings.json'))
del d['worktree']
pathlib.Path('$STMP/v.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/v.json")"
expect_eq "(v) worktree キー無し → merge かつ baseRef が head になる" "merge True" \
  "${out%% *} $(python3 -c "import json;print(json.load(open('$STMP/v.json'))['worktree']['baseRef'] == 'head')")"

python3 -c "
import json, pathlib
d = json.load(open('$ROOT/.claude/settings.json'))
d['worktree'] = {'baseRef': 'fresh'}
pathlib.Path('$STMP/w.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/w.json")"
expect_eq "(w) baseRef が別の値 → note 行が出て値は変わらない" "1 fresh" \
  "$(echo "$out" | grep -c '^note.*worktree\.baseRef') $(python3 -c "import json;print(json.load(open('$STMP/w.json'))['worktree']['baseRef'])")"

cp "$ROOT/.claude/settings.json" "$STMP/x.json"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/x.json")"
expect_eq "(x) baseRef が既に head で hooks・deny も揃っている → skip" "skip" "${out%% *}"

# permissions.allow の不足は note 行で案内するだけで、allow は変更しない
python3 -c "
import json, pathlib
d = json.load(open('$ROOT/.claude/settings.json'))
a = d['permissions']['allow']
a.remove('Bash(jq *)')
a[a.index('Bash(git *)')] = 'Bash(git:*)'
pathlib.Path('$STMP/al1.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/al1.json")"
first="$(echo "$out" | head -n 1)"
last="$(echo "$out" | tail -n 1)"
expect_eq "(al-1) allow だけ不足 → 1行目が permissions.allow の note" "1" \
  "$(echo "$first" | grep -c '^note .*permissions\.allow')"
expect_eq "(al-1) note に Bash(git *) と Bash(jq *) の両方が入る（完全一致判定）" "1 1" \
  "$(echo "$first" | grep -cF 'Bash(git *)') $(echo "$first" | grep -cF 'Bash(jq *)')"
expect_eq "(al-1) 最終行が skip" "skip" "${last%% *}"
expect_eq "(al-1) dst の allow は変更されない" "True False" \
  "$(python3 -c "import json;a=json.load(open('$STMP/al1.json'))['permissions']['allow'];print('Bash(git:*)' in a, 'Bash(jq *)' in a)")"
expect_eq "(al-1) バックアップが作られない" "0" "$(ls "$STMP" | grep -c '^al1\.json\.bak-')"

python3 -c "
import json, pathlib
d = json.load(open('$ROOT/.claude/settings.json'))
d['permissions']['allow'].remove('Bash(jq *)')
d['permissions']['deny'].pop()
pathlib.Path('$STMP/al2.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/al2.json")"
expect_eq "(al-2) allow と deny の両方が不足 → note が merge より前に出る" "note merge" \
  "$(echo "$out" | sed -n 1p | cut -d' ' -f1) $(echo "$out" | sed -n 2p | cut -d' ' -f1)"
expect_eq "(al-2) merge 後も不足していた allow は足されない" "False" \
  "$(python3 -c "import json;print('Bash(jq *)' in json.load(open('$STMP/al2.json'))['permissions']['allow'])")"

out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/al3/settings.json")"
expect_eq "(al-3) dst が無い（create）→ note 行が無い" "0" "$(echo "$out" | grep -c '^note')"

cp "$ROOT/.claude/settings.json" "$STMP/al4.json"
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/al4.json")"
expect_eq "(al-4) allow が揃っている → permissions.allow の note が無い" "0" \
  "$(echo "$out" | grep -c '^note.*permissions\.allow')"

python3 -c "
import json, pathlib
d = json.load(open('$ROOT/.claude/settings.json'))
d['permissions']['allow'] = 'Bash(git *)'
pathlib.Path('$STMP/al5.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
rc=0
out="$(python3 "$SMERGE" "$ROOT/.claude/settings.json" "$STMP/al5.json")" || rc=$?
expect_eq "(al-5) allow が文字列 → 終了コード0" "0" "$rc"
expect_eq "(al-5) 型不正の note 行が1行" "1" "$(echo "$out" | grep -c '^note.*permissions\.allow の型が不正')"

rm -rf "$STMP"

for ent in 'Bash(gh pr merge*)' 'Bash(glab mr merge*)'; do
  expect_eq "(approve-settings) deny に $ent がある" "true" \
    "$(jq --arg e "$ent" '.permissions.deny | index($e) != null' "$ROOT/.claude/settings.json")"
done

for ent in 'Bash(git reset --hard*)' 'Bash(git clean *)' 'Bash(git branch -D *)' 'Bash(curl *)' 'Bash(wget *)' 'Bash(claude *)'; do
  expect_eq "(deny-1) deny に $ent が無い" "false" \
    "$(jq --arg e "$ent" '.permissions.deny | index($e) != null' "$ROOT/.claude/settings.json")"
done
expect_eq "(deny-2) ハーネス本体の settings.json に sandbox が無い" "false" \
  "$(jq 'has("sandbox")' "$ROOT/.claude/settings.json")"

echo "== install.sh の settings.json 扱い =="
WTMP="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$WTMP" >/dev/null 2>&1
expect_eq "(o) merge_settings_json.py が複製される" "1" \
  "$([ -f "$WTMP/scripts/merge_settings_json.py" ] && echo 1 || echo 0)"
expect_eq "(o) settings.json が作られる" "1" "$([ -f "$WTMP/.claude/settings.json" ] && echo 1 || echo 0)"
expect_eq "(o) settings.json に copy_if_absent を使っていない" "0" \
  "$(grep -c 'copy_if_absent.*settings\.json' "$ROOT/scripts/install.sh")"
python3 -c "
import json, pathlib
d = json.load(open('$WTMP/.claude/settings.json'))
d['permissions']['allow'].append('Bash(独自コマンド *)')
del d['hooks']['PostToolUse']
pathlib.Path('$WTMP/.claude/settings.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
bash "$ROOT/scripts/install.sh" --update "$WTMP" >/dev/null 2>&1
expect_eq "(p) --update 後も独自の allow が残る" "True" \
  "$(python3 -c "import json;print('Bash(独自コマンド *)' in json.load(open('$WTMP/.claude/settings.json'))['permissions']['allow'])")"
expect_eq "(p) --update で欠落 hooks が足される" "True" \
  "$(python3 -c "import json;d=json.load(open('$WTMP/.claude/settings.json'));print(any('plan_guard.py' in h['command'] for e in d['hooks'].get('PostToolUse',[]) for h in e.get('hooks',[])))")"
python3 -c "
import json, pathlib
d = json.load(open('$WTMP/.claude/settings.json'))
d['permissions']['allow'].remove('Bash(jq *)')
pathlib.Path('$WTMP/.claude/settings.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
out="$(bash "$ROOT/scripts/install.sh" --update "$WTMP" 2>/dev/null)"
expect_eq "(al-6) install.sh --update の出力に allow 不足の note 行が1行ある" "1" \
  "$(echo "$out" | grep -c '^note .*permissions\.allow にハーネスが使う許可が')"
expect_eq "(al-6) --update 後も allow に削除した項目は戻らない" "False" \
  "$(python3 -c "import json;print('Bash(jq *)' in json.load(open('$WTMP/.claude/settings.json'))['permissions']['allow'])")"
rm -rf "$WTMP"

echo "== sandbox を導入先に入れない =="
SBTMP="$(smoke_tmpdir)" || abort_tmp
python3 -c "
import json, pathlib
d = json.load(open('$ROOT/.claude/settings.json'))
d['sandbox'] = {'enabled': True}
pathlib.Path('$SBTMP/src.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
d.pop('sandbox', None)
pathlib.Path('$SBTMP/nosb.json').write_text(json.dumps(d, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
"
expect_eq "(sb-1) フィクスチャの src に sandbox.enabled が入っている" "True" \
  "$(python3 -c "import json;print(json.load(open('$SBTMP/src.json'))['sandbox']['enabled'])")"
cp "$SBTMP/nosb.json" "$SBTMP/dst.json"
python3 "$SMERGE" "$SBTMP/src.json" "$SBTMP/dst.json" >/dev/null
expect_eq "(sb-2) sandbox 無しの既存 dst に merge しても sandbox が入らない" "False" \
  "$(python3 -c "import json;print('sandbox' in json.load(open('$SBTMP/dst.json')))")"
mkdir -p "$SBTMP/inst/.claude"
cp "$SBTMP/nosb.json" "$SBTMP/inst/.claude/settings.json"
bash "$ROOT/scripts/install.sh" "$SBTMP/inst" >/dev/null 2>&1
expect_eq "(sb-3) 既存の settings.json に install.sh しても sandbox が入らない" "False" \
  "$(python3 -c "import json;print('sandbox' in json.load(open('$SBTMP/inst/.claude/settings.json')))")"
bash "$ROOT/scripts/install.sh" --update "$SBTMP/inst" >/dev/null 2>&1
expect_eq "(sb-4) install.sh --update しても sandbox が入らない" "False" \
  "$(python3 -c "import json;print('sandbox' in json.load(open('$SBTMP/inst/.claude/settings.json')))")"
mkdir -p "$SBTMP/fresh"
bash "$ROOT/scripts/install.sh" "$SBTMP/fresh" >/dev/null 2>&1
expect_eq "(sb-5) 新規導入の settings.json に sandbox が入らない" "False" \
  "$(python3 -c "import json;print('sandbox' in json.load(open('$SBTMP/fresh/.claude/settings.json')))")"
out="$(python3 "$SMERGE" "$SBTMP/src.json" "$SBTMP/new/settings.json")"
expect_eq "(sb-6) 存在しない dst への merge は create で sandbox が入らない" "create False" \
  "${out%% *} $(python3 -c "import json;print('sandbox' in json.load(open('$SBTMP/new/settings.json')))")"
rm -rf "$SBTMP"

echo "== current_plan.sh =="
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
make_plan "P-CUR" "approved"
out="$(CLAUDE_PROJECT_DIR="$TMP" bash "$CURRENT_PLAN_SH")"
expect_eq "current_plan.sh: (a) approved 1件 → id が1行" "P-CUR" "$out"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
{
  echo "---"
  echo "id: P-CUR-DONE"
  echo "status: done"
  echo "---"
  echo "# 本文"
  echo "status: approved"
} > "$TMP/vault/plans/P-CUR-DONE.md"
out="$(CLAUDE_PROJECT_DIR="$TMP" bash "$CURRENT_PLAN_SH")"
expect_eq "current_plan.sh: (b) 本文中の status: approved は無視される" "" "$out"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
{
  echo "---"
  echo "status: approved"
  echo "---"
  echo "# 本文"
} > "$TMP/vault/plans/noidplan.md"
out="$(CLAUDE_PROJECT_DIR="$TMP" bash "$CURRENT_PLAN_SH")"
expect_eq "current_plan.sh: (c) id 無し → ファイル名フォールバック" "noidplan" "$out"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
out="$(CLAUDE_PROJECT_DIR="$TMP" bash "$CURRENT_PLAN_SH")"
expect_eq "current_plan.sh: (d) approved が0件 → 出力なし" "" "$out"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
{
  echo "---"
  echo "id: P-CUR-AA"
  echo "status: approved"
  echo "---"
} > "$TMP/vault/plans/p-aa.md"
{
  echo "---"
  echo "id: P-CUR-BB"
  echo "status: approved"
  echo "---"
} > "$TMP/vault/plans/p-bb.md"
out="$(CLAUDE_PROJECT_DIR="$TMP" bash "$CURRENT_PLAN_SH")"
expect_eq "current_plan.sh: (e) approved が2件以上 → ファイル名順に複数行" "$(printf 'P-CUR-AA\nP-CUR-BB')" "$out"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"

echo "== uninstall.sh =="
UNTMP="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$UNTMP" >/dev/null 2>&1
printf -- '- 独自ルール3\n' >> "$UNTMP/vault/rules/README.md"
mkdir -p "$UNTMP/vault/plans"
echo "dummy" > "$UNTMP/vault/plans/P-DUMMY.md"
uout="$(bash "$ROOT/scripts/uninstall.sh" "$UNTMP" 2>&1)"; urc=$?
expect_eq "(q) uninstall.sh の終了コードが0" "0" "$urc"
expect_eq "(q) 未編集ファイル(stop_gate.py)は削除される" "0" "$([ -f "$UNTMP/.claude/hooks/stop_gate.py" ] && echo 1 || echo 0)"
expect_eq "(q) 編集済みファイル(README.md)は残る" "1" "$([ -f "$UNTMP/vault/rules/README.md" ] && echo 1 || echo 0)"
expect_eq "(q) 編集した行は保持される" "1" "$(grep -c '^- 独自ルール3$' "$UNTMP/vault/rules/README.md")"
expect_eq "(q) skip (edited) が報告される" "1" "$(echo "$uout" | grep -c '^skip (edited) vault/rules/README\.md$')"
expect_eq "(r) vault/plans のダミーファイルは無傷" "1" "$([ -f "$UNTMP/vault/plans/P-DUMMY.md" ] && echo 1 || echo 0)"
expect_eq "(r) ダミーファイルの内容は変わらない" "dummy" "$(cat "$UNTMP/vault/plans/P-DUMMY.md")"
expect_eq "(s) CLAUDE.md はブロックのみの内容だったため削除される（unmerge_claude_md.py）" "0" "$([ -f "$UNTMP/CLAUDE.md" ] && echo 1 || echo 0)"
expect_eq "(s) unmerge_claude_md.py の remove/delete 報告がある" "1" "$(echo "$uout" | grep -Ec '^(remove|delete) .*CLAUDE\.md$')"
expect_eq "(t) settings.json からハーネス由来の hooks が除去される（unmerge_settings_json.py）" "False" \
  "$(python3 -c "import json;d=json.load(open('$UNTMP/.claude/settings.json'));print(any('plan_guard.py' in h.get('command','') for e in d.get('hooks',{}).get('PostToolUse',[]) for h in e.get('hooks',[])))")"
expect_eq "(t) unmerge_settings_json.py の unmerge 報告がある" "1" "$(echo "$uout" | grep -c '^unmerge .*settings\.json$')"
expect_eq "(u) マニフェストファイル自体も削除される" "0" "$([ -f "$UNTMP/.claude/harness-manifest.json" ] && echo 1 || echo 0)"
rm -rf "$UNTMP"

echo "== 標準ルール6本を配らない（install / --update / uninstall） =="
SR_RULES="vault/rules/common/roles.md vault/rules/common/git.md vault/rules/creator/creator.md vault/rules/creator/git-workflow.md vault/rules/verifier/verifier.md vault/rules/planner/planner.md"
sr_count_existing() { # $1=導入先。6本のうち存在する数
  local n=0 rel
  for rel in $SR_RULES; do [ -e "$1/$rel" ] && n=$((n+1)); done
  echo "$n"
}
sr_legacy_fixture() { # $1=導入先。新版で install した後、旧版の状態（6本があり、マニフェストにハッシュが記録されている）にする
  local d="$1" rel
  bash "$ROOT/scripts/install.sh" "$d" >/dev/null 2>&1
  for rel in $SR_RULES; do
    mkdir -p "$d/$(dirname "$rel")"
    printf 'legacy rule %s\n' "$rel" > "$d/$rel"
  done
  python3 -c "
import hashlib, json, sys
d = sys.argv[1]
rules = sys.argv[2:]
mp = d + '/.claude/harness-manifest.json'
m = json.load(open(mp))
for rel in rules:
    m['files'][rel] = hashlib.sha256(open(d + '/' + rel, 'rb').read()).hexdigest()
json.dump(m, open(mp, 'w'), ensure_ascii=False, indent=2)
" "$d" $SR_RULES
}
sr_manifest_count() { # $1=導入先。マニフェストの files にある6本の数
  python3 -c "
import json, sys
f = json.load(open(sys.argv[1] + '/.claude/harness-manifest.json'))['files']
print(sum(1 for r in sys.argv[2:] if r in f))
" "$1" $SR_RULES
}
SR_EDITED="vault/rules/creator/creator.md"

SRTMP="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$SRTMP" >/dev/null 2>&1
expect_eq "(sr-1) 新規 install で6本がどれも複製されない" "0" "$(sr_count_existing "$SRTMP")"
expect_eq "(sr-2) 新規 install のマニフェストの files に6本が無い" "0" "$(sr_manifest_count "$SRTMP")"
rm -rf "$SRTMP"

SRTMP="$(smoke_tmpdir)" || abort_tmp
sr_legacy_fixture "$SRTMP"
printf -- '- 独自ルール4\n' >> "$SRTMP/$SR_EDITED"
sout="$(bash "$ROOT/scripts/install.sh" --update "$SRTMP" 2>&1)"
sr_removed=0; sr_gone=0
for rel in $SR_RULES; do
  [ "$rel" = "$SR_EDITED" ] && continue
  echo "$sout" | grep -Fxq "remove $rel" && sr_removed=$((sr_removed+1))
  [ -e "$SRTMP/$rel" ] || sr_gone=$((sr_gone+1))
done
expect_eq "(sr-3) --update で未編集の5本が削除され remove の行が出る" "5 5" "$sr_removed $sr_gone"
expect_eq "(sr-4) 編集済みの1本は残る" "1" "$([ -f "$SRTMP/$SR_EDITED" ] && echo 1 || echo 0)"
expect_eq "(sr-4) 編集した行が保たれる" "1" "$(grep -c '^- 独自ルール4$' "$SRTMP/$SR_EDITED")"
expect_eq "(sr-4) 編集済みのパスを含む note の行が出る" "1" "$(echo "$sout" | grep -c "^note  $SR_EDITED ")"
expect_eq "(sr-4) 編集済みでないパスの note は出ない" "1" "$(echo "$sout" | grep -c '^note  vault/rules/')"
expect_eq "(sr-5) --update 後のマニフェストの files に6本が無い" "0" "$(sr_manifest_count "$SRTMP")"
rm -rf "$SRTMP"

SRTMP="$(smoke_tmpdir)" || abort_tmp
sr_legacy_fixture "$SRTMP"
printf -- '- 独自ルール5\n' >> "$SRTMP/$SR_EDITED"
printf 'my rule\n' > "$SRTMP/vault/rules/common/my-rule.md"
bash "$ROOT/scripts/uninstall.sh" "$SRTMP" >/dev/null 2>&1; srrc=$?
sr_left=""
for rel in $SR_RULES; do [ -e "$SRTMP/$rel" ] && sr_left="$sr_left $rel"; done
expect_eq "(sr-6) 旧版のマニフェストで uninstall.sh が終了コード0" "0" "$srrc"
expect_eq "(sr-6) 未編集の5本は削除され、編集済みの1本だけ残る" " $SR_EDITED" "$sr_left"
expect_eq "(sr-6) 利用者が置いたルールは残る" "my rule" "$(cat "$SRTMP/vault/rules/common/my-rule.md" 2>/dev/null)"
rm -rf "$SRTMP"

SRTMP="$(smoke_tmpdir)" || abort_tmp
bash "$ROOT/scripts/install.sh" "$SRTMP" >/dev/null 2>&1
printf 'my rule\n' > "$SRTMP/vault/rules/common/my-rule.md"
bash "$ROOT/scripts/uninstall.sh" "$SRTMP" >/dev/null 2>&1; srrc=$?
expect_eq "(sr-7) 6本が無い導入先で uninstall.sh が終了コード0" "0" "$srrc"
expect_eq "(sr-7) 利用者が置いたルールは残る" "my rule" "$(cat "$SRTMP/vault/rules/common/my-rule.md" 2>/dev/null)"
rm -rf "$SRTMP"

echo "== run_unattended.py =="
RU_PY="$ROOT/scripts/run_unattended.py"
RU_PID="$TMP/run-unattended.pid"
RU_ERR="$TMP/run-unattended.err"
rm -f "$RU_PID" "$RU_ERR"
HARNESS_RUN_CMD='sleep 30' HARNESS_RUN_TIMEOUT=1 python3 "$RU_PY" 2>"$RU_ERR"; rurc=$?
expect_eq "(ru-1) タイムアウトの終了コードが124" "124" "$rurc"
expect_eq "(ru-1) タイムアウト時の標準エラーに 'run_unattended: timeout 1s'" "1" "$(grep -c '^run_unattended: timeout 1s$' "$RU_ERR")"
HARNESS_RUN_CMD='sh -c "exit 3"' HARNESS_RUN_TIMEOUT=5 python3 "$RU_PY" 2>/dev/null; rurc=$?
expect_eq "(ru-2) 子の終了コード3が透過される" "3" "$rurc"
rm -f "$RU_PID" "$RU_ERR"
HARNESS_RUN_CMD="sh -c 'sleep 60 & echo \$! > $RU_PID; wait'" HARNESS_RUN_TIMEOUT=1 python3 "$RU_PY" 2>"$RU_ERR"; rurc=$?
expect_eq "(ru-3) 孫プロセス構成でもタイムアウトは124" "124" "$rurc"
ru_gpid="$(cat "$RU_PID" 2>/dev/null)"
expect_eq "(ru-3) 孫の PID が記録されている" "1" "$([ -n "$ru_gpid" ] && echo 1 || echo 0)"
ru_i=0
while [ -n "$ru_gpid" ] && kill -0 "$ru_gpid" 2>/dev/null && [ "$ru_i" -lt 20 ]; do
  sleep 0.1; ru_i=$((ru_i+1))
done
kill -0 "$ru_gpid" 2>/dev/null; rurc=$?
expect_eq "(ru-3) タイムアウト後に孫プロセスが生きていない（kill -0 が失敗）" "1" "$rurc"
expect_eq "(ru-4) HARNESS_STRICT_STOP 未設定なら子に 1 が渡る" "1" "$(env -u HARNESS_STRICT_STOP HARNESS_RUN_CMD='printenv HARNESS_STRICT_STOP' HARNESS_RUN_TIMEOUT=5 python3 "$RU_PY")"
expect_eq "(ru-5) HARNESS_STRICT_STOP=0 なら値を変えず 0 が渡る" "0" "$(env HARNESS_STRICT_STOP=0 HARNESS_RUN_CMD='printenv HARNESS_STRICT_STOP' HARNESS_RUN_TIMEOUT=5 python3 "$RU_PY")"
rm -f "$RU_PID" "$RU_ERR"

echo "== model_stats.py =="
MS_PY="$ROOT/scripts/model_stats.py"
MS_DIR="$(smoke_tmpdir)" || abort_tmp
cat > "$MS_DIR/P-MS.md" <<'MSEOF'
# log
- 2026-10-01 10:00 T-01 todo→doing attempt=1
- 2026-10-01 10:01 T-01 worktree path=/tmp/wt-T-01
- 2026-10-01 10:05 T-01 doing→review attempt=1 creator=sonnet
- 2026-10-01 10:10 T-01 review→done attempt=1 verifier=opus
- 2026-10-01 11:00 T-02 todo→doing attempt=1
- 2026-10-01 11:05 T-02 doing→review attempt=1 creator=haiku
- 2026-10-01 11:10 T-02 review→doing attempt=2 verifier=opus 理由
- 2026-10-01 11:15 T-02 doing→review attempt=2 creator=haiku
- 2026-10-01 11:20 T-02 review→done attempt=2 verifier=opus
- 2026-10-01 12:00 T-03 todo→doing attempt=1
- 2026-10-01 12:05 T-03 doing→review attempt=1 creator=haiku
- 2026-10-01 12:10 T-03 review→blocked attempt=1 verifier=opus 質問
- 2026-10-01 13:00 T-04 todo→doing attempt=1
- 2026-10-01 13:05 T-04 doing→review attempt=1
- 2026-10-01 13:10 T-04 review→done attempt=1
- 2026-10-01 14:00 T-05 todo→doing attempt=1
- 2026-10-01 14:05 T-05 doing→blocked attempt=1 creator=haiku 質問
- 2026-10-01 15:00 T-06 todo→doing attempt=1
- 2026-10-01 15:05 T-06 doing→review attempt=1 creator=sonnet
- 2026-10-01 15:10 T-06 review→doing attempt=2 verifier=opus 理由
- 2026-10-01 15:15 T-06 doing→blocked attempt=2 creator=haiku 質問
MSEOF
ms_want="$(printf 'model\ttasks\tfirst_pass_rate\tavg_attempt\tblocked_rate\tnoted_rate\nhaiku\t4\t0.00\t1.50\t0.75\t0.00\nsonnet\t1\t1.00\t1.00\t0.00\t0.00\nunknown\t1\t1.00\t1.00\t0.00\t0.00')"
ms_got="$(python3 "$MS_PY" "$MS_DIR/P-MS.md")"
expect_eq "(ms-1) フィクスチャ log の集計出力（見出し行・モデル別の行）が期待値と一致" "$ms_want" "$ms_got"
expect_eq "(ms-1) 見出し行がタブ区切りの6列" "6" "$(echo "$ms_got" | head -1 | awk -F'\t' '{print NF}')"
expect_eq "(ms-5) doing→blocked creator= で終わるタスクも creator のモデルに集計される（haiku 4件・blocked 率 0.75）" "$(printf 'haiku\t4\t0.00\t1.50\t0.75\t0.00')" "$(echo "$ms_got" | grep '^haiku')"
# (ms-6) noted_rate: <base>/log/<計画ID>.md から <base>/verdicts/<計画ID>/<id>.json を読む
mkdir -p "$MS_DIR/nt/vault/log" "$MS_DIR/nt/vault/verdicts/P-NT"
cat > "$MS_DIR/nt/vault/log/P-NT.md" <<'MSEOF'
- 2026-10-01 10:00 T-01 todo→doing attempt=1
- 2026-10-01 10:05 T-01 doing→review attempt=1 creator=sonnet
- 2026-10-01 10:10 T-01 review→done attempt=1 verifier=opus
- 2026-10-01 11:00 T-02 todo→doing attempt=1
- 2026-10-01 11:05 T-02 doing→review attempt=1 creator=sonnet
- 2026-10-01 11:10 T-02 review→done attempt=1 verifier=opus
- 2026-10-01 12:00 T-03 todo→doing attempt=1
- 2026-10-01 12:05 T-03 doing→blocked attempt=1 creator=sonnet 質問
- 2026-10-01 13:00 T-04 todo→doing attempt=1
- 2026-10-01 13:05 T-04 doing→review attempt=1 creator=haiku
- 2026-10-01 13:10 T-04 review→done attempt=1 verifier=opus
MSEOF
printf '%s' '{"task":"T-01","reasons":["r1"]}' > "$MS_DIR/nt/vault/verdicts/P-NT/T-01.json"
printf '%s' '{"task":"T-02","reasons":[]}' > "$MS_DIR/nt/vault/verdicts/P-NT/T-02.json"
printf '%s' 'not json' > "$MS_DIR/nt/vault/verdicts/P-NT/T-04.json"
ms_want6="$(printf 'model\ttasks\tfirst_pass_rate\tavg_attempt\tblocked_rate\tnoted_rate\nhaiku\t1\t1.00\t1.00\t0.00\t0.00\nsonnet\t3\t0.67\t1.00\t0.33\t0.33')"
expect_eq "(ms-6) noted_rate は verdict の reasons が空でないタスクの割合（verdict 無し・壊れた JSON は指摘なし）" "$ms_want6" "$(python3 "$MS_PY" "$MS_DIR/nt/vault/log/P-NT.md")"
python3 "$MS_PY" >/dev/null 2>&1; msrc=$?
expect_eq "(ms-2) 引数なしの実行が現在の vault/log に対して終了コード0" "0" "$msrc"
mkdir -p "$MS_DIR/root/scripts" "$MS_DIR/root/vault/log" "$MS_DIR/root/vault/archive/2026-01"
cp "$MS_PY" "$MS_DIR/root/scripts/model_stats.py"
grep -v 'creator=haiku' "$MS_DIR/P-MS.md" > "$MS_DIR/root/vault/log/P-LIVE.md"
cp "$MS_DIR/P-MS.md" "$MS_DIR/root/vault/archive/2026-01/P-OLD.md"
ms_def="$(python3 "$MS_DIR/root/scripts/model_stats.py")"
expect_eq "(ms-2) vault/archive/ 配下は既定の対象に含まれない（haiku の行が出ない）" "0" "$(echo "$ms_def" | grep -c '^haiku')"
expect_eq "(ms-2) vault/log/ 配下は既定の対象になる（sonnet の行が出る）" "1" "$(echo "$ms_def" | grep -c '^sonnet')"
expect_eq "(ms-3) SKILL.md に creator= の記述" "1" "$(grep -q 'creator=' "$ROOT/.claude/skills/run/SKILL.md" && echo 1 || echo 0)"
expect_eq "(ms-3) SKILL.md に verifier= の記述" "1" "$(grep -q 'verifier=' "$ROOT/.claude/skills/run/SKILL.md" && echo 1 || echo 0)"
expect_eq "(ms-3) vault-spec.md に verifier= の記述" "1" "$(grep -q 'verifier=' "$ROOT/docs/vault-spec.md" && echo 1 || echo 0)"
rm -rf "$MS_DIR"

# creator=/verifier= 付きの log とタスク表がある状態でも stop_gate.py・plan_guard.py の判定が変わらない
rm -rf "$TMP/vault/plans" "$TMP/vault/verdicts" "$TMP/vault/log"; mkdir -p "$TMP/vault/log"
cat > "$TMP/vault/log/P-TEST.md" <<'MSEOF'
- 2026-10-01 10:00 T-0001 todo→doing attempt=1
- 2026-10-01 10:05 T-0001 doing→review attempt=1 creator=sonnet
- 2026-10-01 10:10 T-0001 review→done attempt=1 verifier=opus
- 2026-10-01 11:05 T-0002 doing→review attempt=1 creator=haiku
MSEOF
make_plan "P-TEST" "approved" "| T-0001 | done | 1 | - | A | |" "| T-0002 | review | 1 | - | B | |"
make_verdict T-0001 1 PASS; make_verdict T-0002 1 PASS
expect "(ms-4) 補足付き log・stop_gate: review で PASS → ブロック（done にする指示）" block "$(run_stop)" "done"
make_plan "P-TEST" "approved" "| T-0001 | done | 1 | - | A | |" "| T-0002 | done | 1 | - | B | |"
expect "(ms-4) 補足付き log・stop_gate: 全 done → 許可" allow "$(run_stop)"
expect "(ms-4) 補足付き log・plan_guard: 正常な計画票 → 許可" allow "$(run_plan_guard)"
make_plan "P-TEST" "approved" "| T-0001 | done | 1 | - | A | |" "| T-0001 | done | 1 | - | B | |"
expect "(ms-4) 補足付き log・plan_guard: id 重複 → ブロック（判定が変わらない）" block "$(run_plan_guard)" "重複"
rm -rf "$TMP/vault/plans" "$TMP/vault/verdicts" "$TMP/vault/log"; mkdir -p "$TMP/vault/plans"

echo "== usage_stats.py =="
US_PY="$ROOT/scripts/usage_stats.py"
US_DIR="$(smoke_tmpdir)" || abort_tmp
us_line() { # $1=agentId $2=agentType $3=model $4=tokens $5=ms $6=tools $7=prompt
  printf '{"type":"user","message":{"role":"user"},"toolUseResult":{"agentId":"%s","agentType":"%s","resolvedModel":"%s","status":"completed","prompt":"%s","totalTokens":%s,"totalDurationMs":%s,"totalToolUseCount":%s,"usage":{}}}\n' "$1" "$2" "$3" "$7" "$4" "$5" "$6"
}
{
  us_line a1 creator claude-haiku-x 1000 10000 3 "x"
  us_line a2 creator claude-haiku-x 2000 21000 4 "x"
  us_line a3 creator claude-haiku-x 2001 12000 4 "x"
  us_line a4 creator claude-sonnet-x 300 2000 1 "x"
  us_line a5 verifier claude-sonnet-x 5000 30000 10 "x"
} > "$US_DIR/ok.jsonl"
us_want="$(printf 'agent\tmodel\tcalls\ttokens_total\ttokens_avg\tduration_avg_s\ttool_uses_avg\ncreator\tclaude-haiku-x\t3\t5001\t1667.0\t14.3\t3.7\ncreator\tclaude-sonnet-x\t1\t300\t300.0\t2.0\t1.0\nverifier\tclaude-sonnet-x\t1\t5000\t5000.0\t30.0\t10.0')"
expect_eq "(us-1) agentType×resolvedModel ごとの集計が見出し付きのタブ区切りで出る" "$us_want" "$(python3 "$US_PY" "$US_DIR/ok.jsonl")"
{
  echo 'not json'
  us_line a1 creator claude-haiku-x 1000 10000 3 "x"
  echo ''
  echo '{"type":"user","message":"no result"}'
  us_line a2 creator claude-haiku-x 2000 21000 4 "x"
  echo '{"type":"user","toolUseResult":"just a string"}'
  echo '{"type":"user","toolUseResult":{"agentType":"creator","resolvedModel":"claude-haiku-x","totalDurationMs":1,"totalToolUseCount":1}}'
  us_line a3 creator claude-haiku-x 2001 12000 4 "x"
  echo '{"type":"user","toolUseResult":{"agentType":"creator","resolvedModel":"claude-haiku-x","totalTokens":1,"totalDurationMs":1}}'
  us_line a4 creator claude-sonnet-x 300 2000 1 "x"
  us_line a5 verifier claude-sonnet-x 5000 30000 10 "x"
  printf '\n'
} > "$US_DIR/messy.jsonl"
us_got="$(python3 "$US_PY" "$US_DIR/messy.jsonl" 2>/dev/null)"; us_rc=$?
expect_eq "(us-2) 壊れた行・欠けた行を読み飛ばし終了コード0で (us-1) と同じ集計" "0:$us_want" "$us_rc:$us_got"
{
  us_line p1 creator claude-sonnet-x 100 1000 1 "do P-20990101-aa/T-01 now"
  us_line p2 creator claude-sonnet-x 200 3000 2 "do P-20990101-bb/T-02 now"
  us_line p3 creator claude-sonnet-x 300 5000 3 "no plan id here"
  us_line p4 creator claude-sonnet-x 400 7000 4 "P-20990101-aa/T-03"
} > "$US_DIR/plan.jsonl"
expect_eq "(us-3) --plan は計画IDが一致する呼び出しだけを集計する" "$(printf 'agent\tmodel\tcalls\ttokens_total\ttokens_avg\tduration_avg_s\ttool_uses_avg\ncreator\tclaude-sonnet-x\t2\t500\t250.0\t4.0\t2.5')" "$(python3 "$US_PY" --plan P-20990101-aa "$US_DIR/plan.jsonl")"
US_ROOT="$US_DIR/home/my_root.v2"
US_KEY="$(printf '%s' "$US_ROOT" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$US_ROOT/scripts" "$US_DIR/home/.claude/projects/$US_KEY"
cp "$US_PY" "$US_ROOT/scripts/usage_stats.py"
cp "$US_DIR/ok.jsonl" "$US_DIR/home/.claude/projects/$US_KEY/a.jsonl"
expect_eq "(us-4) 引数なしは HOME 配下の既定の読み込み先を読む" "$us_want" "$(env HOME="$US_DIR/home" python3 "$US_ROOT/scripts/usage_stats.py")"
mkdir -p "$US_DIR/dir"
us_line d1 creator claude-haiku-x 1000 10000 3 "x" > "$US_DIR/dir/a.jsonl"
us_line d2 creator claude-haiku-x 3000 20000 5 "x" > "$US_DIR/dir/b.jsonl"
us_line d3 creator claude-haiku-x 90000 90000 9 "x" > "$US_DIR/dir/c.txt"
expect_eq "(us-5) ディレクトリ引数は直下の *.jsonl だけを合わせて集計する" "$(printf 'agent\tmodel\tcalls\ttokens_total\ttokens_avg\tduration_avg_s\ttool_uses_avg\ncreator\tclaude-haiku-x\t2\t4000\t2000.0\t15.0\t4.0')" "$(python3 "$US_PY" "$US_DIR/dir")"
mkdir -p "$US_DIR/dup"
us_line same creator claude-haiku-x 1000 10000 3 "x" > "$US_DIR/dup/a.jsonl"
us_line same creator claude-haiku-x 1000 10000 3 "x" > "$US_DIR/dup/b.jsonl"
expect_eq "(us-6) 同じ agentId は全ファイルを通して1回だけ数える" "$(printf 'agent\tmodel\tcalls\ttokens_total\ttokens_avg\tduration_avg_s\ttool_uses_avg\ncreator\tclaude-haiku-x\t1\t1000\t1000.0\t10.0\t3.0')" "$(python3 "$US_PY" "$US_DIR/dup/a.jsonl" "$US_DIR/dup/b.jsonl")"
python3 "$US_PY" "$US_DIR/nonexistent.jsonl" >/dev/null 2>&1; us_rc=$?
expect_eq "(us-7) 存在しないパスを渡すと終了コード1" "1" "$us_rc"
rm -rf "$US_DIR"

echo "== verdict_notes.py =="
VN_PY="$ROOT/scripts/verdict_notes.py"
VN_DIR="$(smoke_tmpdir)" || abort_tmp
mkdir -p "$VN_DIR/vault/verdicts/P-VN" "$VN_DIR/other" "$VN_DIR/empty/vault/verdicts/P-VN"
printf '%s' '{"task":"T-01","reasons":["r1"]}' > "$VN_DIR/vault/verdicts/P-VN/T-01.json"
printf '%s' '{"task":"T-02","reasons":[]}' > "$VN_DIR/vault/verdicts/P-VN/T-02.json"
printf '%s' '{"task":"T-03","reasons":["a\nb","c"]}' > "$VN_DIR/vault/verdicts/P-VN/T-03.json"
printf '%s' '{"task":"T-09","reasons":[]}' > "$VN_DIR/empty/vault/verdicts/P-VN/T-09.json"
printf '%s' '{"task":"T-07","reasons":["other"]}' > "$VN_DIR/other/T-07.json"
vn_out="$(cd "$VN_DIR" && python3 "$VN_PY" P-VN 2>/dev/null)"
expect_eq "(vn-1) 既定の読み込み先で reasons を <id>: <reason> の行にする" $'T-01: r1\nT-03: a b\nT-03: c' "$vn_out"
vn_out="$(cd "$VN_DIR/empty" && python3 "$VN_PY" P-VN 2>/dev/null)"
expect_eq "(vn-2) reasons が全部空なら 指摘なし だけ" "指摘なし" "$vn_out"
vn_out="$(cd "$VN_DIR" && python3 "$VN_PY" P-VN --dir other 2>/dev/null)"
expect_eq "(vn-3) --dir 指定は計画 ID の既定ディレクトリでなくそちらを読む" "T-07: other" "$vn_out"
printf '%s' 'not json' > "$VN_DIR/other/T-08.json"
vn_out="$(cd "$VN_DIR" && python3 "$VN_PY" P-VN --dir other 2>/dev/null)"; vn_rc=$?
expect_eq "(vn-4) 壊れた JSON が混じっても終了コード0で他の行は出る" "0:T-07: other" "$vn_rc:$vn_out"
( cd "$VN_DIR" && python3 "$VN_PY" P-VN --dir nonexistent >/dev/null 2>&1 ); vn_rc=$?
expect_eq "(vn-5) 読み込み先のディレクトリが無ければ終了コード1" "1" "$vn_rc"
( cd "$VN_DIR" && python3 "$VN_PY" >/dev/null 2>&1 ); vn_rc=$?
expect_eq "(vn-6) 引数なしは終了コード2" "2" "$vn_rc"
rm -rf "$VN_DIR"

echo "== purge_plan.sh =="
PP_SH="$ROOT/scripts/purge_plan.sh"
PP_ID="P-20990101-pp"
PP_OUT="$TMP/pp_out.txt"; PP_ERR="$TMP/pp_err.txt"
pp_git() { git -c user.name=smoke -c user.email=smoke@example.com "$@"; }
pp_make() { # $1=リポジトリ名 $2=frontmatter の status $3...=タスク表の status（複数）。ブランチは work/p-20990101-pp
  local d="$TMP/$1" st="$2" i=0 s
  shift 2
  rm -rf "$d"
  mkdir -p "$d/vault/plans" "$d/vault/tasks/$PP_ID" "$d/vault/verdicts/$PP_ID" "$d/vault/log"
  {
    printf -- '---\nid: %s\nstatus: %s\n---\n# ゴール\nx\n\n## タスク表\n| id | status | title |\n|----|--------|-------|\n' "$PP_ID" "$st"
    for s in "$@"; do i=$((i+1)); printf '| T-0%d | %s | t |\n' "$i" "$s"; done
  } > "$d/vault/plans/$PP_ID.md"
  printf '# T-01\n' > "$d/vault/tasks/$PP_ID/T-01.md"
  printf '{"result":"PASS"}\n' > "$d/vault/verdicts/$PP_ID/T-01.json"
  printf -- '- 2099-01-01 00:00 T-01 doing→review\n' > "$d/vault/log/$PP_ID.md"
  ( cd "$d" && git init -q -b main . && git checkout -q -b work/p-20990101-pp && git add -A && pp_git commit -q -m c ) >/dev/null 2>&1
}
pp_run() { # $1=リポジトリ名 $2...=引数。PP_RC に終了コード
  local r="$1"
  shift
  ( cd "$TMP/$r" && bash "$PP_SH" "$@" ) > "$PP_OUT" 2> "$PP_ERR"
  PP_RC=$?
}
pp_status() { ( cd "$TMP/$1" && git status --porcelain ); }
pp_four=$'vault/plans/P-20990101-pp.md\nvault/tasks/P-20990101-pp/\nvault/verdicts/P-20990101-pp/\nvault/log/P-20990101-pp.md'

pp_make pp1 done done done
pp_run pp1 --dry-run "$PP_ID"
expect_eq "(pp-1) --dry-run は4行を出し、何も変えない" "0|$pp_four|" "$PP_RC|$(cat "$PP_OUT")|$(pp_status pp1)"

pp_make pp2 done done done
pp2_head="$(cd "$TMP/pp2" && git rev-parse HEAD)"
pp_run pp2 "$PP_ID"
pp2_ok=1
for p in vault/plans/$PP_ID.md vault/tasks/$PP_ID vault/verdicts/$PP_ID vault/log/$PP_ID.md; do
  [ -e "$TMP/pp2/$p" ] && pp2_ok=0
done
pp2_bad="$(pp_status pp2 | grep -vc '^D ')"
expect_eq "(pp-2) 実行は4つを git rm し、コミットしない" "0|1|0|$pp_four|$pp2_head" "$PP_RC|$pp2_ok|$pp2_bad|$(cat "$PP_OUT")|$(cd "$TMP/pp2" && git rev-parse HEAD)"

pp_make pp3 done done done
( cd "$TMP/pp3" && git checkout -q -b other ) >/dev/null 2>&1
pp_run pp3 "$PP_ID"
expect_eq "(pp-3) ブランチが違えば終了コード1で何も変えない" "1||" "$PP_RC|$(cat "$PP_OUT")|$(pp_status pp3)"

pp_make pp4 approved done done
pp_run pp4 "$PP_ID"
expect_eq "(pp-4) status が approved なら終了コード1で何も変えない" "1||" "$PP_RC|$(cat "$PP_OUT")|$(pp_status pp4)"

pp_make pp5a done done doing
pp_run pp5a "$PP_ID"; pp5a_rc=$PP_RC
pp5a_st="$(pp_status pp5a)"
pp_make pp5b done
sed -i '/^| T-/d' "$TMP/pp5b/vault/plans/$PP_ID.md"
( cd "$TMP/pp5b" && git add -A && pp_git commit -q -m c ) >/dev/null 2>&1
pp_run pp5b "$PP_ID"
expect_eq "(pp-5) done でない行がある時もデータ行0行の時も終了コード1で何も変えない" "1||1||" "$pp5a_rc|$pp5a_st|$PP_RC|$(cat "$PP_OUT")|$(pp_status pp5b)"

pp_make pp6a done done done
printf -- '- 2099-01-02 00:00 追記\n' >> "$TMP/pp6a/vault/log/$PP_ID.md"
pp_run pp6a "$PP_ID"; pp6a_rc=$PP_RC
pp6a_ok=0
[ -e "$TMP/pp6a/vault/plans/$PP_ID.md" ] && [ -e "$TMP/pp6a/vault/tasks/$PP_ID/T-01.md" ] && [ -e "$TMP/pp6a/vault/verdicts/$PP_ID/T-01.json" ] && [ -e "$TMP/pp6a/vault/log/$PP_ID.md" ] && pp6a_ok=1
pp_make pp6b done done done
printf 'new\n' > "$TMP/pp6b/vault/tasks/$PP_ID/T-02.md"
pp_run pp6b "$PP_ID"
pp6b_ok=0
[ -e "$TMP/pp6b/vault/plans/$PP_ID.md" ] && [ -e "$TMP/pp6b/vault/tasks/$PP_ID/T-01.md" ] && [ -e "$TMP/pp6b/vault/tasks/$PP_ID/T-02.md" ] && [ -e "$TMP/pp6b/vault/verdicts/$PP_ID/T-01.json" ] && [ -e "$TMP/pp6b/vault/log/$PP_ID.md" ] && pp6b_ok=1
expect_eq "(pp-6) 未コミットの変更も未追跡ファイルも終了コード1で何も消さない" "1:1:1:1" "$pp6a_rc:$pp6a_ok:$PP_RC:$pp6b_ok"

pp_make pp7 done done done
( cd "$TMP/pp7" && git rm -r -q -- "vault/verdicts/$PP_ID" && pp_git commit -q -m c ) >/dev/null 2>&1
pp_run pp7 --dry-run "$PP_ID"
expect_eq "(pp-7) verdicts が無ければ除いた3行を出す" $'0|vault/plans/P-20990101-pp.md\nvault/tasks/P-20990101-pp/\nvault/log/P-20990101-pp.md' "$PP_RC|$(cat "$PP_OUT")"

pp_make pp8 done done done
mkdir -p "$TMP/pp8_nogit"
pp_run pp8; pp8_a=$PP_RC
pp_run pp8 --bogus "$PP_ID"; pp8_b=$PP_RC
pp_run pp8 P-1; pp8_c=$PP_RC
( cd "$TMP/pp8_nogit" && bash "$PP_SH" "$PP_ID" ) >/dev/null 2>&1; pp8_d=$?
expect_eq "(pp-8) 引数なし・未知のオプション・形式違いの ID・git の外はどれも終了コード2" "2:2:2:2" "$pp8_a:$pp8_b:$pp8_c:$pp8_d"

echo "== vcs_finish.sh =="
VF_BIN="$TMP/vf_bin"; VF_REC="$TMP/vf_rec.txt"; VF_REPO="$TMP/vf_repo"
mkdir -p "$VF_BIN" "$VF_REPO"
for vf_cmd in gh glab; do
  printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "%%s\\n" "$a"; done > "%s"\n[ "${1:-}" = api ] && echo https://github.com/o/r/pull/1\nexit 0\n' "$VF_REC" > "$VF_BIN/$vf_cmd"
  chmod +x "$VF_BIN/$vf_cmd"
done
(
  cd "$VF_REPO" && git init -q -b vfmain . \
    && git -c user.name=smoke -c user.email=smoke@example.com commit -q --allow-empty -m init \
    && git config branch.vfmain.remote . && git config branch.vfmain.merge refs/heads/vfmain \
    && git remote add origin https://github.com/o/r.git
) >/dev/null 2>&1
expect_vf() { # $1=name $2=host $3=期待する記録（改行区切り） $4...=vcs_finish.sh への引数
  local name="$1" host="$2" want="$3"
  shift 3
  rm -f "$VF_REC"
  ( cd "$VF_REPO" && PATH="$VF_BIN:$PATH" HARNESS_VCS_HOST="$host" bash "$ROOT/scripts/vcs_finish.sh" "$@" ) >/dev/null 2>&1
  local got; got="$(cat "$VF_REC" 2>/dev/null || true)"
  if [ "$got" = "$want" ]; then
    echo "  ok   $name"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $name (want='$(echo "$want" | tr '\n' ' ')' got='$(echo "$got" | tr '\n' ' ')')"; FAIL_N=$((FAIL_N+1))
  fi
}
expect_vf "(vcs_finish) github・引数あり → そのまま（--fill なし）" github $'pr\ncreate\n--title\nT\n--body\nB' --title T --body B
expect_vf "(vcs_finish) gitlab・引数なし → glab mr create --fill --yes" gitlab $'mr\ncreate\n--fill\n--yes'
expect_vf "(vcs_finish) gitlab・引数あり → そのまま（--fill なし）" gitlab $'mr\ncreate\n--title\nT\n--body\nB' --title T --body B

# 計画のあるブランチ（別リポジトリ）：引数なしならタスク履歴を本文に載せる
VF_REPO2="$TMP/vf_repo2"
mkdir -p "$VF_REPO2/vault/plans" "$VF_REPO2/vault/verdicts/P-20990101-vf"
(
  cd "$VF_REPO2" && git init -q -b work/p-20990101-vf . \
    && printf -- '---\nid: P-20990101-vf\nstatus: approved\n---\n# ゴール\nvf goal line\n\n## タスク表\n| id | status | attempt | after | title | question |\n|---|---|---|---|---|---|\n| T-01 | done | 1 | - | first | |\n| T-02 | todo | 0 | T-01 | second | |\n' > vault/plans/P-20990101-vf.md \
    && printf '{"task": "P-20990101-vf/T-01", "attempt": 1, "result": "PASS"}\n' > vault/verdicts/P-20990101-vf/T-01.json \
    && git add -A && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m "P-20990101-vf/T-01: done" \
    && git config branch.work/p-20990101-vf.remote . && git config branch.work/p-20990101-vf.merge refs/heads/work/p-20990101-vf \
    && git remote add origin https://github.com/o/r.git
) >/dev/null 2>&1
vf_body_check() { # $1=name $2=host
  local name="$1" host="$2" ok=1 want5
  shift 2
  rm -f "$VF_REC"
  ( cd "$VF_REPO2" && PATH="$VF_BIN:$PATH" HARNESS_VCS_HOST="$host" bash "$ROOT/scripts/vcs_finish.sh" "$@" ) >/dev/null 2>&1
  local got; got="$(cat "$VF_REC" 2>/dev/null || true)"
  want5=$'mr\ncreate\n--title\nP-20990101-vf: vf goal line\n--description'
  [ "$(printf '%s\n' "$got" | head -5)" = "$want5" ] || ok=0
  printf '%s\n' "$got" | grep -q '^| T-01 | .*PASS (attempt=1) |$' || ok=0
  printf '%s\n' "$got" | grep -q '^| T-02 | .*| - | - |$' || ok=0
  if [ "$host" = gitlab ]; then
    [ "$(printf '%s\n' "$got" | tail -1)" = "--yes" ] || ok=0
  fi
  if [ "$ok" = 1 ]; then
    echo "  ok   $name"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $name (got='$(echo "$got" | tr '\n' ' ')')"; FAIL_N=$((FAIL_N+1))
  fi
}
vf_body_check "(vcs_finish-body) gitlab・計画あり・引数なし → --title と --description にタスク履歴と --yes" gitlab
rm -f "$VF_REC"
( cd "$VF_REPO2" && PATH="$VF_BIN:$PATH" HARNESS_VCS_HOST=github bash "$ROOT/scripts/vcs_finish.sh" --title T --body B ) >/dev/null 2>&1
if [ "$(cat "$VF_REC" 2>/dev/null)" = $'pr\ncreate\n--title\nT\n--body\nB' ]; then
  echo "  ok   (vcs_finish-body) github・計画あり・引数あり → そのまま"; PASS_N=$((PASS_N+1))
else
  echo "  NG   (vcs_finish-body) github・計画あり・引数あり → そのまま (got='$(tr '\n' ' ' < "$VF_REC" 2>/dev/null)')"; FAIL_N=$((FAIL_N+1))
fi

# HARNESS_PR_BODY_FILE と HARNESS_PR_TITLE で本文とタイトルを渡す経路
VF_NOTES="$TMP/vf_notes.md"; printf 'notes line 1\nnotes line 2\n' > "$VF_NOTES"
vf_notes_run() { # $1=リポジトリ $2=host $3...=env 代入
  local repo="$1" host="$2"; shift 2
  rm -f "$VF_REC"
  ( cd "$repo" && env PATH="$VF_BIN:$PATH" HARNESS_VCS_HOST="$host" "$@" bash "$ROOT/scripts/vcs_finish.sh" ) >/dev/null 2>&1
}
vf_notes_ok() { # $1=name $2=want
  local got; got="$(cat "$VF_REC" 2>/dev/null || true)"
  if [ "$got" = "$2" ]; then
    echo "  ok   $1"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $1 (want='$(echo "$2" | tr '\n' ' ')' got='$(echo "$got" | tr '\n' ' ')')"; FAIL_N=$((FAIL_N+1))
  fi
}
vf_notes_run "$VF_REPO" gitlab HARNESS_PR_BODY_FILE="$VF_NOTES" HARNESS_PR_TITLE="NT"
vf_notes_ok "(vf-notes-2) gitlab・本文ファイルとタイトル → --description に中身と --yes" $'mr\ncreate\n--title\nNT\n--description\nnotes line 1\nnotes line 2\n--yes'
rm -f "$VF_REC"
( cd "$VF_REPO2" && env PATH="$VF_BIN:$PATH" HARNESS_VCS_HOST=github HARNESS_PR_BODY_FILE="$VF_NOTES" HARNESS_PR_TITLE=X bash "$ROOT/scripts/vcs_finish.sh" --title T --body B ) >/dev/null 2>&1
vf_notes_ok "(vf-notes-4) 引数あり → 環境変数を無視してそのまま" $'pr\ncreate\n--title\nT\n--body\nB'
vf_notes_run "$VF_REPO" github HARNESS_PR_BODY_FILE="$TMP/vf_no_such_file.md"; vf_rc=$?
if [ "$vf_rc" = 2 ] && [ ! -e "$VF_REC" ]; then
  echo "  ok   (vf-notes-5) 本文ファイルが読めない → 終了コード2で gh を呼ばない"; PASS_N=$((PASS_N+1))
else
  echo "  NG   (vf-notes-5) rc=$vf_rc rec=$([ -e "$VF_REC" ] && echo yes || echo no)"; FAIL_N=$((FAIL_N+1))
fi

# GitHub の REST（gh api）の経路
vf_rest_check() { # $1=name $2=ok(0/1) $3=got
  if [ "$2" = 1 ]; then
    echo "  ok   $1"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   $1 (got='$(echo "$3" | tr '\n' ' ')')"; FAIL_N=$((FAIL_N+1))
  fi
}
vf_notes_run "$VF_REPO" github HARNESS_PR_BODY_FILE="$VF_NOTES" HARNESS_PR_TITLE="NT"
vf_got="$(cat "$VF_REC" 2>/dev/null || true)"
vf_want=$'api\n-X\nPOST\nrepos/o/r/pulls\n-f\ntitle=NT\n-f\nhead=vfmain\n-f\nbase=main\n-F\nbody=@'"$VF_NOTES"$'\n--jq\n.html_url'
[ "$vf_got" = "$vf_want" ] && vf_ok=1 || vf_ok=0
vf_rest_check "(vf-rest-1) github・本文ファイルとタイトル → gh api の REST" "$vf_ok" "$vf_got"

vf_notes_run "$VF_REPO2" github
vf_got="$(cat "$VF_REC" 2>/dev/null || true)"
vf_ok=1
[ "$(printf '%s\n' "$vf_got" | head -11)" = $'api\n-X\nPOST\nrepos/o/r/pulls\n-f\ntitle=P-20990101-vf: vf goal line\n-f\nhead=work/p-20990101-vf\n-f\nbase=main\n-f' ] || vf_ok=0
printf '%s\n' "$vf_got" | sed -n '12p' | grep -q '^body=' || vf_ok=0
printf '%s\n' "$vf_got" | grep -q '^| T-01 | ' || vf_ok=0
printf '%s\n' "$vf_got" | grep -q '^| T-02 | ' || vf_ok=0
[ "$(printf '%s\n' "$vf_got" | tail -2)" = $'--jq\n.html_url' ] || vf_ok=0
vf_rest_check "(vf-rest-2) github・計画あり・引数なし → gh api の REST でタスク履歴" "$vf_ok" "$vf_got"

vf_notes_run "$VF_REPO" github
vf_got="$(cat "$VF_REC" 2>/dev/null || true)"
vf_want=$'api\n-X\nPOST\nrepos/o/r/pulls\n-f\ntitle=init\n-f\nhead=vfmain\n-f\nbase=main\n-f\nbody=\n--jq\n.html_url'
[ "$vf_got" = "$vf_want" ] && vf_ok=1 || vf_ok=0
vf_rest_check "(vf-rest-3) github・計画無し・引数なし → 直近コミットの件名と本文" "$vf_ok" "$vf_got"

vf_ok=1; vf_got=""
for vf_url in git@github.com:o2/r2.git https://github.com/o2/r2 ssh://git@github.com/o2/r2.git/; do
  ( cd "$VF_REPO" && git remote set-url origin "$vf_url" ) >/dev/null 2>&1
  vf_notes_run "$VF_REPO" github
  vf_one="$(cat "$VF_REC" 2>/dev/null || true)"
  vf_got="$vf_got $vf_one"
  printf '%s\n' "$vf_one" | grep -qx 'repos/o2/r2/pulls' || vf_ok=0
done
( cd "$VF_REPO" && git remote set-url origin https://github.com/o/r.git ) >/dev/null 2>&1
vf_rest_check "(vf-rest-4) origin の URL の形が違っても owner/repo を取れる" "$vf_ok" "$vf_got"

VF_REPO3="$TMP/vf_repo3"; mkdir -p "$VF_REPO3"
(
  cd "$VF_REPO3" && git init -q -b vfmain . \
    && git -c user.name=smoke -c user.email=smoke@example.com commit -q --allow-empty -m init \
    && git config branch.vfmain.remote . && git config branch.vfmain.merge refs/heads/vfmain
) >/dev/null 2>&1
vf_notes_run "$VF_REPO3" github; vf_rc=$?
[ "$vf_rc" = 2 ] && [ ! -e "$VF_REC" ] && vf_ok=1 || vf_ok=0
vf_rest_check "(vf-rest-5) origin が無い → 終了コード2で gh を呼ばない" "$vf_ok" "rc=$vf_rc"

rm -f "$VF_REC"
vf_out="$( cd "$VF_REPO" && env PATH="$VF_BIN:$PATH" HARNESS_VCS_HOST=github HARNESS_PR_BODY_FILE="$VF_NOTES" HARNESS_PR_TITLE=NT bash "$ROOT/scripts/vcs_finish.sh" 2>/dev/null )"
[ "$vf_out" = "https://github.com/o/r/pull/1" ] && vf_ok=1 || vf_ok=0
vf_rest_check "(vf-rest-6) 標準出力は PR の URL の1行だけ" "$vf_ok" "$vf_out"

echo "== archive_plans.sh =="
AR_OUT="$TMP/ar_out.txt"; AR_ERR="$TMP/ar_err.txt"
ar_init() { # $1=リポジトリ名（$TMP の下に作る）
  mkdir -p "$TMP/$1/vault/plans" "$TMP/$1/vault/log"
  ( cd "$TMP/$1" && git init -q -b main . ) >/dev/null 2>&1
}
ar_plan() { # $1=リポジトリ名 $2=計画ID $3=frontmatter の status $4=タスク表の status $5=log の最初の日時（YYYY-MM-DD HH:MM）
  local d="$TMP/$1"
  mkdir -p "$d/vault/tasks/$2" "$d/vault/verdicts/$2"
  printf -- '---\nid: %s\nstatus: %s\n---\n# ゴール\nx\n\n## タスク表\n| id | status | title |\n|----|--------|-------|\n| T-01 | %s | t |\n' "$2" "$3" "$4" > "$d/vault/plans/$2.md"
  printf '# T-01\n' > "$d/vault/tasks/$2/T-01.md"
  printf '{"verdict":"PASS"}\n' > "$d/vault/verdicts/$2/T-01.json"
  printf -- '- %s - draft→approved\n' "$5" > "$d/vault/log/$2.md"
}
ar_commit() { # $1=リポジトリ名
  ( cd "$TMP/$1" && git add -A && git -c user.name=smoke -c user.email=smoke@example.com commit -q -m c ) >/dev/null 2>&1
}
ar_branch() { # $1=リポジトリ名 $2=作業ブランチ名
  ( cd "$TMP/$1" && git checkout -q -b "$2" ) >/dev/null 2>&1
}
ar_run() { # $1=リポジトリ名 $2...=archive_plans.sh への引数。AR_RC に終了コード、AR_OUT/AR_ERR に出力
  local r="$1"
  shift
  ( cd "$TMP/$r" && bash "$ROOT/scripts/archive_plans.sh" "$@" ) > "$AR_OUT" 2> "$AR_ERR"
  AR_RC=$?
}
ar_clean() { # $1=リポジトリ名。作業ツリーに変更が無ければ clean
  if [ -z "$(cd "$TMP/$1" && git status --porcelain)" ]; then echo clean; else echo dirty; fi
}

# 共通の用意：A=done・マージ済み、B=approved、C=表に review、E=移動先が既にある、CUR=現在のブランチの計画
ar_init ar_repo
ar_plan ar_repo P-20260101-a done done "2026-01-01 10:00"
ar_plan ar_repo P-20260102-b approved todo "2026-01-02 10:00"
ar_plan ar_repo P-20260103-c done review "2026-01-03 10:00"
ar_plan ar_repo P-20260105-e done done "2026-01-05 10:00"
ar_plan ar_repo P-20260109-cur done done "2026-01-09 10:00"
mkdir -p "$TMP/ar_repo/vault/archive/2026-01/plans"
printf 'x\n' > "$TMP/ar_repo/vault/archive/2026-01/plans/P-20260105-e.md"
ar_commit ar_repo
ar_branch ar_repo work/p-20260109-cur
ar_plan ar_repo P-20260104-d done done "2026-01-04 10:00"
ar_commit ar_repo

ar_run ar_repo --keep 0 --dry-run P-20260101-a
expect_eq "(ar-1) dry-run: 終了コード0" "0" "$AR_RC"
expect_eq "(ar-1) dry-run: git mv 行が4行" "4" "$(grep -c '^git mv ' "$AR_OUT")"
expect_eq "(ar-1) dry-run: ファイルは動いていない" "clean" "$(ar_clean ar_repo)"

ar_init ar_repo2
ar_plan ar_repo2 P-20260101-a done done "2026-01-01 10:00"
ar_commit ar_repo2
ar_branch ar_repo2 work/p-20260109-cur
ar_run ar_repo2 --keep 0 --apply P-20260101-a
expect_eq "(ar-2) apply: 終了コード0" "0" "$AR_RC"
ar_dst_ok="yes"
for ar_p in plans/P-20260101-a.md tasks/P-20260101-a/T-01.md verdicts/P-20260101-a/T-01.json log/P-20260101-a.md; do
  [ -e "$TMP/ar_repo2/vault/archive/2026-01/$ar_p" ] || ar_dst_ok="no"
done
expect_eq "(ar-2) apply: archive/2026-01/{plans,tasks,verdicts,log}/ に移った" "yes" "$ar_dst_ok"
ar_src_gone="yes"
for ar_p in plans/P-20260101-a.md tasks/P-20260101-a verdicts/P-20260101-a log/P-20260101-a.md; do
  [ ! -e "$TMP/ar_repo2/vault/$ar_p" ] || ar_src_gone="no"
done
expect_eq "(ar-2) apply: 元の場所から消えた" "yes" "$ar_src_gone"
expect_eq "(ar-2) apply: git status に rename（R ）の行がある" "yes" "$(cd "$TMP/ar_repo2" && git status --porcelain | grep -q '^R ' && echo yes || echo no)"

ar_run ar_repo --keep 0 --dry-run P-20260104-d
expect_eq "(ar-3) main に無い done 計画: 終了コード1" "1" "$AR_RC"
expect_eq "(ar-3) stderr に NG 行" "1" "$(grep -c '^archive_plans: NG P-20260104-d: ' "$AR_ERR")"
expect_eq "(ar-3) 何も動かない" "clean" "$(ar_clean ar_repo)"

ar_run ar_repo --keep 0 --apply P-20260102-b
expect_eq "(ar-4) approved の計画: 終了コード1" "1" "$AR_RC"
expect_eq "(ar-4) 何も動かない" "clean" "$(ar_clean ar_repo)"

ar_run ar_repo --keep 0 --apply P-20260103-c
expect_eq "(ar-5) 表に review がある計画: 終了コード1" "1" "$AR_RC"
expect_eq "(ar-5) 何も動かない" "clean" "$(ar_clean ar_repo)"

ar_run ar_repo --keep 0 --apply P-20260101-a P-20260102-b
expect_eq "(ar-6) 移せる計画と NG を一緒に: 終了コード1" "1" "$AR_RC"
expect_eq "(ar-6) 移せる方も動かない" "clean" "$(ar_clean ar_repo)"
expect_eq "(ar-6) 移せる方の計画票が残っている" "yes" "$([ -f "$TMP/ar_repo/vault/plans/P-20260101-a.md" ] && echo yes || echo no)"

ar_run ar_repo --keep 0 P-20260101-a
expect_eq "(ar-7) モード無し: 終了コード2" "2" "$AR_RC"
expect_eq "(ar-7) モード無し: stderr に usage: 行" "1" "$(grep -c '^usage: ' "$AR_ERR")"

ar_run ar_repo --keep 0 --apply P-20260105-e
expect_eq "(ar-8) 移動先が既にある: 終了コード1" "1" "$AR_RC"
expect_eq "(ar-8) 移動先が既にある: 何も動かない" "clean" "$(ar_clean ar_repo)"
ar_run ar_repo --keep 0 --apply P-20260109-cur
expect_eq "(ar-8) 現在のブランチの計画: 終了コード1" "1" "$AR_RC"
expect_eq "(ar-8) 現在のブランチの計画: 何も動かない" "clean" "$(ar_clean ar_repo)"
ar_init ar_repo3
ar_plan ar_repo3 P-20260109-cur done done "2026-01-09 10:00"
ar_commit ar_repo3
ar_branch ar_repo3 work/p-20260109-cur
ar_run ar_repo3 --keep 0 --list
expect_eq "(ar-8) 現在のブランチの計画は --keep 0 --list に出ない（終了コード0・出力なし）" "0:" "$AR_RC:$(cat "$AR_OUT")"

ar_init ar_repo9
ar_plan ar_repo9 P-20260201-x done done "2026-02-01 10:00"
ar_plan ar_repo9 P-20260202-x done done "2026-02-02 10:00"
ar_plan ar_repo9 P-20260203-x done done "2026-02-03 10:00"
ar_commit ar_repo9
ar_branch ar_repo9 work/p-20260109-cur
ar_run ar_repo9 --keep 2 --apply
expect_eq "(ar-9) 新しい件数は残る: 終了コード0" "0" "$AR_RC"
expect_eq "(ar-9) 一番古い1件だけ移る" "moved" "$([ -f "$TMP/ar_repo9/vault/archive/2026-02/plans/P-20260201-x.md" ] && [ ! -e "$TMP/ar_repo9/vault/plans/P-20260201-x.md" ] && echo moved || echo no)"
expect_eq "(ar-9) 新しい2件は vault/plans/ に残る" "P-20260202-x.md P-20260203-x.md" "$(cd "$TMP/ar_repo9/vault/plans" && echo *.md)"

ar_init ar_repo10
ar_plan ar_repo10 P-20260201-x done done "2026-02-01 10:00"
ar_plan ar_repo10 P-20260202-x done done "2026-02-02 10:00"
ar_commit ar_repo10
ar_branch ar_repo10 work/p-20260109-cur
ar_run ar_repo10 --keep 2 --apply
expect_eq "(ar-10) 候補が --keep 件以下: 終了コード0・stdout 空" "0:" "$AR_RC:$(cat "$AR_OUT")"
expect_eq "(ar-10) 何も動かない" "clean" "$(ar_clean ar_repo10)"
ar_run ar_repo10 --apply
expect_eq "(ar-10) 既定の --keep 5 でも終了コード0・stdout 空" "0:" "$AR_RC:$(cat "$AR_OUT")"

ar_init ar_repo11
ar_plan ar_repo11 P-20260105-a done done "2026-01-05 11:00"
ar_plan ar_repo11 P-20260105-b done done "2026-01-05 10:00"
ar_commit ar_repo11
ar_branch ar_repo11 work/p-20260109-cur
ar_run ar_repo11 --keep 1 --list
expect_eq "(ar-11) 同日: log の日時が古い -b だけが出る（新しい -a が残る）" "P-20260105-b" "$(cat "$AR_OUT")"
ar_init ar_repo12
ar_plan ar_repo12 P-20260106-a done done "2026-01-06 10:00"
ar_plan ar_repo12 P-20260106-b done done "2026-01-06 10:00"
ar_commit ar_repo12
ar_branch ar_repo12 work/p-20260109-cur
ar_run ar_repo12 --keep 1 --list
expect_eq "(ar-11) log の日時も同じ: ID の文字列順で前の -a だけが出る" "P-20260106-a" "$(cat "$AR_OUT")"

echo
echo "== _hooklib.py =="
HLB="$(smoke_tmpdir)" || abort_tmp
mkdir -p "$HLB/.claude/hooks"
for h in agent_write_guard plan_guard stop_gate; do cp "$ROOT/.claude/hooks/$h.py" "$HLB/.claude/hooks/$h.py"; done
printf 'def broken(:\n' > "$HLB/.claude/hooks/_hooklib.py"
printf '%s' '{}' | CLAUDE_PROJECT_DIR="$HLB" python3 "$HLB/.claude/hooks/agent_write_guard.py" >/dev/null 2>&1; rc=$?
expect_eq "(hooklib-broken) agent_write_guard: _hooklib 構文エラー → 終了コード 2" "2" "$rc"
printf '%s' '{}' | CLAUDE_PROJECT_DIR="$HLB" python3 "$HLB/.claude/hooks/plan_guard.py" >/dev/null 2>&1; rc=$?
expect_eq "(hooklib-broken) plan_guard: _hooklib 構文エラー → 終了コード 2" "2" "$rc"
printf '%s' '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$HLB" python3 "$HLB/.claude/hooks/stop_gate.py" >/dev/null 2>&1; rc=$?
expect_eq "(hooklib-broken) stop_gate: stop_hook_active=false → 終了コード 2" "2" "$rc"
printf '%s' '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$HLB" HARNESS_STRICT_STOP=0 python3 "$HLB/.claude/hooks/stop_gate.py" >/dev/null 2>&1; rc=$?
expect_eq "(hooklib-broken) stop_gate: stop_hook_active=true・STRICT=0 → 終了コード 0" "0" "$rc"

WTBASE="$(smoke_tmpdir)" || abort_tmp
WTMAIN="$WTBASE/main"; LEAF="$WTBASE/leaf"
mkdir -p "$WTMAIN"
git -C "$WTMAIN" init -q -b main
sg_plan "$WTMAIN" P-SG
git -C "$WTMAIN" add -A
git -C "$WTMAIN" -c user.email=t@example.com -c user.name=t commit -q -m init
git -C "$WTMAIN" worktree add -q "$LEAF" -b wt-leaf
expect_eq "(stop_gate worktree) 前提: worktree の .git がファイルである" "yes" "$([ -f "$LEAF/.git" ] && echo yes || echo no)"
echo dirty > "$LEAF/x.txt"
expect "(stop_gate worktree) 未コミットのファイルがある → 許可" allow \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$LEAF" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")"
rm -f "$LEAF/x.txt"
expect "(stop_gate worktree) ファイルを消す → 許可" allow \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$LEAF" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")"
git -C "$WTMAIN" worktree remove -q --force "$LEAF"
rm -rf "$WTBASE"

HPC="$(smoke_tmpdir)" || abort_tmp
mkdir -p "$HPC/.claude/hooks"
cp "$ROOT"/.claude/hooks/*.py "$HPC/.claude/hooks/"
rm -rf "$HPC/.claude/hooks/__pycache__"
printf '%s' '{}' | env -u PYTHONDONTWRITEBYTECODE CLAUDE_PROJECT_DIR="$HPC" python3 "$HPC/.claude/hooks/agent_write_guard.py" >/dev/null 2>&1
printf '%s' '{}' | env -u PYTHONDONTWRITEBYTECODE CLAUDE_PROJECT_DIR="$HPC" python3 "$HPC/.claude/hooks/plan_guard.py" >/dev/null 2>&1
printf '%s' '{"stop_hook_active":true}' | env -u PYTHONDONTWRITEBYTECODE CLAUDE_PROJECT_DIR="$HPC" python3 "$HPC/.claude/hooks/stop_gate.py" >/dev/null 2>&1
expect_eq "(hooklib-pycache) 3フック実行後に .claude/hooks/__pycache__ が無い" "no" "$([ -e "$HPC/.claude/hooks/__pycache__" ] && echo yes || echo no)"
rm -rf "$HLB" "$HPC"

echo "== hooklib-rules（D-011 フェーズ2） =="
rm -rf "$TMP/vault/plans" "$TMP/vault/verdicts" "$TMP/vault/tasks"; mkdir -p "$TMP/vault/plans"
# a
make_plan_task T-0001 review 1
mkdir -p "$TMP/vault/tasks/P-TEST"
printf '# T-0001 テスト\n\n## 受け入れ基準\n1. 基準1\n2. 基準2\n3. 基準3\n4. 基準4\n\n## 決定済み\n- x\n' > "$TMP/vault/tasks/P-TEST/T-0001.md"
write_verdict T-0001 '{"task":"P-TEST/T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":['"$OK_C"','"$OK_C"','"$OK_C"','"$OK_C"'],"reasons":[]}'
expect "(hooklib-rules) stop_gate: 受け入れ基準が番号付きの4行・criteria 4件の PASS → 形式不正にしない" block "$(run_stop)" "verdict は PASS ですが"
# b
rm -rf "$TMP/vault/verdicts" "$TMP/vault/tasks"
make_plan "P-TEST" '"approved"' "| T-0001 | doing | 1 | - | A | |"
expect "(hooklib-rules) stop_gate: status: \"approved\"（引用符付き）の計画票を approved として扱う" block "$(run_stop)" "verdict が無い"
# c
make_plan "P-TEST" '"approved"' "| T-0001 | blocked | 1 | - | A | |"
expect "(hooklib-rules) plan_guard: status: \"approved\"（引用符付き）の計画票を approved として扱う" block "$(run_plan_guard)" "question 列が空です"
# d（status の後ろに語が続く fixtures-comment も同じ出力に含める。両方満たす時だけ P-CUR-Q になる）
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
printf -- "---\nid: 'P-CUR-Q'\nstatus: \"approved\"\n---\n" > "$TMP/vault/plans/P-CUR-Q.md"
hr_q="$(CLAUDE_PROJECT_DIR="$TMP" bash "$CURRENT_PLAN_SH")"
hr_fc="$(CLAUDE_PROJECT_DIR="$ROOT/vault/tasks/P-20261004-hooklib-rules/fixtures-comment" bash "$CURRENT_PLAN_SH")"
[ "$hr_fc" = "P-FIXTURE-COMMENT" ] || hr_q="$hr_q (fixtures-comment: $hr_fc)"
expect_eq "(hooklib-rules) current_plan.sh: id・status が引用符付き → 引用符を外した計画 ID を出す" "P-CUR-Q" "$hr_q"
# e（インデントした done でない行を持つ計画は候補から外れる。移る計画は q の1件だけ＝git mv 4行）
ar_init ar_quoted
ar_plan ar_quoted P-20260101-q '"done"' done "2026-01-01 10:00"
ar_plan ar_quoted P-20260102-q2 done review "2026-01-02 10:00"
sed 's/^| T-01/  | T-01/' "$TMP/ar_quoted/vault/plans/P-20260102-q2.md" > "$TMP/ar_quoted/q2.tmp" && mv "$TMP/ar_quoted/q2.tmp" "$TMP/ar_quoted/vault/plans/P-20260102-q2.md"
ar_commit ar_quoted
ar_branch ar_quoted work/p-20260109-cur
ar_run ar_quoted --keep 0 --dry-run
expect_eq "(hooklib-rules) archive_plans.sh: status: \"done\"（引用符付き）の計画を移す対象にする" "4" "$(grep -c '^git mv ' "$AR_OUT")"
# f
rm -rf "$TMP/vault/plans" "$TMP/vault/verdicts"
make_plan "P-TEST" "approved" "  | T-0001 | doing | 1 | - | A | |"
expect "(hooklib-rules) stop_gate: 行頭を半角空白でインデントしたタスク表の doing 行を検査する" block "$(run_stop)" "verdict が無い"
rm -rf "$TMP/vault/plans" "$TMP/vault/verdicts" "$TMP/vault/tasks"; mkdir -p "$TMP/vault/plans" "$TMP/vault/verdicts" "$TMP/vault/tasks"

echo "== transition.py（D-012 フェーズ2） =="
TR="$TMP/tr"
tr_setup() { # $1=std|draft|main
  local preset="${1:-std}" st=approved
  [ "$preset" = "draft" ] && st=draft
  rm -rf "$TR"
  mkdir -p "$TR/vault/plans" "$TR/vault/log" "$TR/vault/verdicts/P-TEST" "$TR/.claude/agents"
  {
    echo "---"; echo "id: P-TEST"; echo "status: $st"; echo "---"
    echo "# ゴール"; echo "確認用の計画"; echo
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
    echo
    echo "## 計画の受け入れ基準"; echo "- 確認用"
  } > "$TR/vault/plans/P-TEST.md"
  echo "- 2026-01-01 00:00 - draft→approved 人の指示: /plan approve P-TEST" > "$TR/vault/log/P-TEST.md"
  printf -- '---\nname: creator\nmodel: smoke-creator\n---\n本文\n' > "$TR/.claude/agents/creator.md"
  printf -- '---\nname: verifier\nmodel: smoke-verifier\n---\n本文\n' > "$TR/.claude/agents/verifier.md"
  git -C "$TR" init -q -b main
  git -C "$TR" config user.name smoke
  git -C "$TR" config user.email smoke@example.com
  git -C "$TR" add -A
  git -C "$TR" commit -q -m init
  [ "$preset" != "main" ] && git -C "$TR" checkout -q -b work/p-test
  local okc='{"text":"基準","ok":true,"note":"実行コマンド: x / 出力: y"}'
  printf '{"task":"P-TEST/T-06","attempt":1,"result":"PASS","checked_at":"2026-01-01 00:00","criteria":[%s],"reasons":[]}\n' "$okc" > "$TR/vault/verdicts/P-TEST/T-06.json"
  printf '{"task":"P-TEST/T-07","attempt":1,"result":"FAIL","checked_at":"2026-01-01 00:00","criteria":[%s],"reasons":["r"]}\n' "$okc" > "$TR/vault/verdicts/P-TEST/T-07.json"
  printf '{"task":"P-TEST/T-08","attempt":1,"result":"PASS","checked_at":"2026-01-01 00:00","criteria":[%s],"reasons":[]}\n' "$okc" > "$TR/vault/verdicts/P-TEST/T-08.json"
}
# transition.py を1回実行し、TR_RC・TR_NEW（増えたコミット数）・TR_PLAN／TR_LOG（same|diff）・TR_B／TR_A（前後の JST）を設定する
tr_run() {
  cp "$TR/vault/plans/P-TEST.md" "$TMP/tr_plan.before"
  cp "$TR/vault/log/P-TEST.md" "$TMP/tr_log.before"
  local n0 n1
  n0="$(git -C "$TR" rev-list --count HEAD)"
  TR_B="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')"
  ( cd "$TR" && python3 "$ROOT/scripts/transition.py" "$@" ) > "$TMP/tr_out" 2> "$TMP/tr_err"
  TR_RC=$?
  TR_A="$(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M')"
  n1="$(git -C "$TR" rev-list --count HEAD)"
  TR_NEW=$((n1 - n0))
  cmp -s "$TMP/tr_plan.before" "$TR/vault/plans/P-TEST.md" && TR_PLAN=same || TR_PLAN=diff
  cmp -s "$TMP/tr_log.before" "$TR/vault/log/P-TEST.md" && TR_LOG=same || TR_LOG=diff
}
tr_nochange() { echo "$TR_RC $TR_NEW $TR_PLAN $TR_LOG"; }
tr_row() { grep "^| $1 |" "$TR/vault/plans/P-TEST.md"; }
tr_lastlog() { tail -n "${1:-1}" "$TR/vault/log/P-TEST.md"; }

tr_setup std; tr_run P-TEST T-01,T-02 doing
expect_eq "(transition) 01 todo→doing で T-01 が doing・attempt=1" "1" "$(tr_row T-01 | grep -c '^| T-01 | doing | 1 |')"
expect_eq "(transition) 01 todo→doing で T-02 が doing・attempt=1" "1" "$(tr_row T-02 | grep -c '^| T-02 | doing | 1 |')"
expect_eq "(transition) 01 終了コードは 0" "0" "$TR_RC"
expect_eq "(transition) 02 log に T-01 の行が追記される" "1" "$(tr_lastlog 2 | grep -c '^- [0-9-]* [0-9:]* T-01 todo→doing attempt=1$')"
expect_eq "(transition) 02 log に T-02 の行が追記される" "1" "$(tr_lastlog 2 | grep -c '^- [0-9-]* [0-9:]* T-02 todo→doing attempt=1$')"
expect_eq "(transition) 03 コミットが1つ増える" "1" "$TR_NEW"
expect_eq "(transition) 03 コミットのファイルは計画票と log だけ" "vault/log/P-TEST.md vault/plans/P-TEST.md" \
  "$(git -C "$TR" show --name-only --format= HEAD | sort | tr '\n' ' ' | sed 's/ $//')"
LOGDT="$(tr_lastlog 2 | sed -n '1s/^- \([0-9-]* [0-9:]*\) .*/\1/p')"
if [ "$LOGDT" = "$TR_B" ] || [ "$LOGDT" = "$TR_A" ]; then DT_OK=match; else DT_OK="mismatch($LOGDT vs $TR_B/$TR_A)"; fi
expect_eq "(transition) 04 log の日時が実行前後の JST と一致する" "match" "$DT_OK"

tr_setup std; tr_run P-TEST T-04 review
expect_eq "(transition) 05 doing→review の log 行が creator=smoke-creator で終わる" "1" \
  "$(tr_lastlog | grep -c ' T-04 doing→review attempt=1 creator=smoke-creator$')"

tr_setup std; tr_run P-TEST T-06 done
expect_eq "(transition) 06 review→done で行が done になる" "1" "$(tr_row T-06 | grep -c '^| T-06 | done | 1 |')"
expect_eq "(transition) 06 log 行が verifier=smoke-verifier で終わる" "1" \
  "$(tr_lastlog | grep -c ' T-06 review→done attempt=1 verifier=smoke-verifier$')"
expect_eq "(transition) 07 review→done のコミットに verdict が含まれる" "1" \
  "$(git -C "$TR" show --name-only --format= HEAD | grep -c '^vault/verdicts/P-TEST/T-06.json$')"

tr_setup std; export HARNESS_CREATOR_MODEL=haiku; tr_run P-TEST T-04 review; unset HARNESS_CREATOR_MODEL
expect_eq "(transition-model-1) HARNESS_CREATOR_MODEL=haiku で doing→review の行が creator=haiku で終わる" "1" \
  "$(tr_lastlog | grep -c ' T-04 doing→review attempt=1 creator=haiku$')"
tr_setup std; export HARNESS_CREATOR_MODEL=haiku; tr_run P-TEST T-06 done; unset HARNESS_CREATOR_MODEL
expect_eq "(transition-model-2) 環境変数があっても review→done は verifier=smoke-verifier のまま" "1" \
  "$(tr_lastlog | grep -c ' T-06 review→done attempt=1 verifier=smoke-verifier$')"
tr_setup std; export HARNESS_CREATOR_MODEL=; tr_run P-TEST T-04 review; unset HARNESS_CREATOR_MODEL
expect_eq "(transition-model-3) 空文字なら creator=smoke-creator" "1" \
  "$(tr_lastlog | grep -c ' T-04 doing→review attempt=1 creator=smoke-creator$')"
tr_setup std; export HARNESS_CREATOR_MODEL=haiku; tr_run P-TEST T-04 review --no-model; unset HARNESS_CREATOR_MODEL
expect_eq "(transition-model-4) --no-model なら環境変数があってもモデルを付けない" "1" \
  "$(tr_lastlog | grep -c ' T-04 doing→review attempt=1$')"

tr_setup std; tr_run P-TEST T-09 done
expect_eq "(transition) 08 verdict 無しの review→done は何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; tr_run P-TEST T-07 done
expect_eq "(transition) 09 FAIL の review→done は何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; tr_run P-TEST T-08 done
expect_eq "(transition) 10 attempt 不一致の review→done は何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; tr_run P-TEST T-01 todo
expect_eq "(transition) 11 遷移先が todo は何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; tr_run P-TEST T-01 approved
expect_eq "(transition) 12 遷移先が approved は何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; tr_run P-TEST T-10 doing
expect_eq "(transition) 13 blocked の行からの遷移は何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup draft; tr_run P-TEST T-01 doing
expect_eq "(transition) 14 計画票が draft なら何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup main; tr_run P-TEST T-01 doing
expect_eq "(transition) 15 ブランチが main なら何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; tr_run P-TEST T-03 doing
expect_eq "(transition) 16 after が done でない行を doing にすると何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; HARNESS_MAX_ATTEMPTS=3 tr_run P-TEST T-05 doing
expect_eq "(transition) 17 attempt が HARNESS_MAX_ATTEMPTS を超える再試行は何も変えない" "1 0 same same" "$(tr_nochange)"
tr_setup std; tr_run P-TEST T-04 blocked
expect_eq "(transition) 18 question 無しの blocked は何も変えない" "1 0 same same" "$(tr_nochange)"

tr_setup std
printf 'A|B\n次の行\n' > "$TMP/tr_q.txt"
tr_run P-TEST T-04 blocked --question-file "$TMP/tr_q.txt"
expect_eq "(transition) 19 question の | と改行が ／ と空白に置き換わる" "1" "$(tr_row T-04 | grep -c '^| T-04 | blocked | 1 | - | D | A／B 次の行 |$')"
PGOUT="$(printf '{"hook_event_name":"PostToolUse","tool_name":"Edit"}' | CLAUDE_PROJECT_DIR="$TR" python3 "$PLAN_GUARD_HOOK")"
expect_eq "(transition) 19 その計画票を plan_guard.py が許可する" "0" "$(echo "$PGOUT" | grep -c '"decision": *"block"')"

tr_setup std; tr_run P-TEST T-01,T-06,T-09 done
expect_eq "(transition) 20 複数 id のうち1つが拒否されると全部変わらない" "1 0 same same" "$(tr_nochange)"

tr_setup std
echo extra > "$TR/extra.txt"; git -C "$TR" add extra.txt
tr_run P-TEST T-01 doing
expect_eq "(transition) 21 コミットに無関係な staged ファイルを混ぜない" "0" "$(git -C "$TR" show --name-only --format= HEAD | grep -c '^extra.txt$')"
expect_eq "(transition) 21 無関係な staged ファイルは staged のまま残る" "extra.txt" "$(git -C "$TR" diff --cached --name-only)"

tr_setup std; tr_run P-TEST T-04 review --no-model --note 中断から再開
expect_eq "(transition) 22 --no-model で log 行にモデルが付かず補足で終わる" "1" \
  "$(tr_lastlog | grep -c ' T-04 doing→review attempt=1 中断から再開$')"
expect_eq "(transition) 22 終了コードは 0" "0" "$TR_RC"

echo
echo "== diff_gate.py（D-012 フェーズ3） =="
DG="$TMP/dg"
DG_OUT="$TMP/dg_out.txt"
DG_ERR="$TMP/dg_err.txt"
dg_task() { # $1=id $2=成果物の宣言行（複数行可）
  printf '# %s 確認用のタスク\n\n## 目的\n確認用\n\n## 入力\n- `docs/readme.md`\n\n## 成果物\n%s\n\n## 受け入れ基準\n- 基準1\n- 基準2\n\n## 決定済み\n- なし\n\n## 進捗\n' "$1" "$2"
}
dg_replace() { # $1=file $2=old $3=new（最初の1か所だけ置き換える）
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert old in s, old
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
dg_setup() { # 一時リポジトリを作り直し、main に base をコミットして work/b に切り替える
  rm -rf "$DG"
  mkdir -p "$DG/vault/tasks/P-TEST" "$DG/vault/plans" "$DG/vault/log" "$DG/vault/verdicts/P-TEST" \
    "$DG/vault/rules/common" "$DG/scripts" "$DG/docs/dir" "$DG/.claude/hooks" "$DG/.claude/agents"
  dg_task T-01 '- `scripts/foo.py`（1ファイル）
- `docs/dir/`（ディレクトリ）
- `.claude/hooks/x.py`
- `vault/plans/P-TEST.md`・`vault/log/P-TEST.md`・`vault/rules/common/x.md`・`vault/verdicts/P-TEST/`
- `check_func` 関数' > "$DG/vault/tasks/P-TEST/T-01.md"
  dg_task T-02 '- `scripts/foo.py`' > "$DG/vault/tasks/P-TEST/T-02.md"
  printf -- '---\nid: P-TEST\nstatus: approved\n---\n' > "$DG/vault/plans/P-TEST.md"
  echo "- log" > "$DG/vault/log/P-TEST.md"
  echo rule > "$DG/vault/rules/common/x.md"
  echo "print(1)" > "$DG/scripts/foo.py"
  echo a > "$DG/docs/dir/a.md"
  echo readme > "$DG/docs/readme.md"
  echo "x = 1" > "$DG/.claude/hooks/x.py"
  echo "y = 1" > "$DG/.claude/hooks/y.py"
  echo "{}" > "$DG/.claude/settings.json"
  printf -- '---\nname: creator\n---\n' > "$DG/.claude/agents/creator.md"
  git -C "$DG" init -q -b main
  git -C "$DG" config user.name smoke
  git -C "$DG" config user.email smoke@example.com
  git -C "$DG" add -A
  git -C "$DG" commit -q -m base
  git -C "$DG" checkout -q -b work/b
}
dg_commit() { git -C "$DG" add -A; git -C "$DG" commit -q -m change; }
dg_run() { # 引数は diff_gate.py へ渡す（省略時は P-TEST T-01 main work/b）
  [ $# -gt 0 ] || set -- P-TEST T-01 main work/b
  ( cd "$DG" && python3 "$ROOT/scripts/diff_gate.py" "$@" ) > "$DG_OUT" 2> "$DG_ERR"
  DG_RC=$?
}
dg_state() { echo "$(git -C "$DG" rev-parse HEAD) $(git -C "$DG" status --porcelain | tr '\n' ' ')"; }
dg_has() { grep -cxF -- "$1" "$DG_OUT"; }

# 01 宣言どおり
dg_setup
echo "print(2)" > "$DG/scripts/foo.py"
mkdir -p "$DG/docs/dir/sub"; echo b > "$DG/docs/dir/sub/b.md"
echo "x = 2" > "$DG/.claude/hooks/x.py"
echo "- 進捗の追記" >> "$DG/vault/tasks/P-TEST/T-01.md"
dg_commit
DG_S0="$(dg_state)"
dg_run
expect_eq "(diff_gate) 01 宣言どおりの変更は終了コード 0" "0" "$DG_RC"
expect_eq "(diff_gate) 01 宣言どおりの変更は出力が空" "0" "$(wc -c < "$DG_OUT" | tr -d ' ')"
expect_eq "(diff_gate) 01 実行の前後で HEAD と git status が変わらない" "$DG_S0" "$(dg_state)"

# 02 03 宣言外のファイル
dg_setup
echo extra > "$DG/extra.txt"; dg_commit
dg_run
expect_eq "(diff_gate) 02 宣言外のファイルを足すと終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 03 出力に「<パス>: 「成果物」に宣言されていない」の行がある" "1" \
  "$(dg_has 'extra.txt: 「成果物」に宣言されていない')"

# 04 未コミット
dg_setup
echo extra > "$DG/extra.txt"
dg_run
expect_eq "(diff_gate) 04 未コミットの宣言外ファイルは対象外で終了コード 0" "0" "$DG_RC"

# 05 git mv
dg_setup
git -C "$DG" mv scripts/foo.py scripts/bar.py; dg_commit
dg_run
expect_eq "(diff_gate) 05 宣言したファイルを宣言外の名前にすると終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 05 新しいパスが違反として出る" "1" \
  "$(dg_has 'scripts/bar.py: 「成果物」に宣言されていない')"

# 06 07 08 タスク票
dg_setup
dg_replace "$DG/vault/tasks/P-TEST/T-01.md" "- 基準2" "- 基準2（書き換え）"; dg_commit
dg_run
expect_eq "(diff_gate) 06 自分のタスク票の「受け入れ基準」を変えると終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 06 理由が「進捗」以外の節が変わっている" "1" \
  "$(dg_has 'vault/tasks/P-TEST/T-01.md: タスク票の「進捗」以外の節が変わっている')"

dg_setup
dg_replace "$DG/vault/tasks/P-TEST/T-01.md" "# T-01 確認用のタスク" "# T-01 確認用のタスク（書き換え）"; dg_commit
dg_run
expect_eq "(diff_gate) 07 タスク票の最初の見出しより前を変えると終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 07 理由が「進捗」以外の節が変わっている" "1" \
  "$(dg_has 'vault/tasks/P-TEST/T-01.md: タスク票の「進捗」以外の節が変わっている')"

dg_setup
echo "- 進捗の追記" >> "$DG/vault/tasks/P-TEST/T-02.md"; dg_commit
dg_run
expect_eq "(diff_gate) 08 ほかのタスク票を宣言なしで変えると終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 08 ほかのタスク票が宣言外として出る" "1" \
  "$(dg_has 'vault/tasks/P-TEST/T-02.md: 「成果物」に宣言されていない')"

# 09 10 11 常に違反の3ディレクトリ、12 vault/rules/ は宣言があれば許される
dg_setup
echo "変更" >> "$DG/vault/plans/P-TEST.md"; dg_commit
dg_run
expect_eq "(diff_gate) 09 宣言のある vault/plans/ 配下の変更は終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 09 理由が vault/plans/ 配下は宣言があっても変更できない" "1" \
  "$(dg_has 'vault/plans/P-TEST.md: vault/plans/ 配下は宣言があっても変更できない')"

dg_setup
echo "- 変更" >> "$DG/vault/log/P-TEST.md"; dg_commit
dg_run
expect_eq "(diff_gate) 10 宣言のある vault/log/ 配下の変更は終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 10 理由が vault/log/ 配下は宣言があっても変更できない" "1" \
  "$(dg_has 'vault/log/P-TEST.md: vault/log/ 配下は宣言があっても変更できない')"

dg_setup
echo '{"result":"PASS"}' > "$DG/vault/verdicts/P-TEST/T-01.json"; dg_commit
dg_run
expect_eq "(diff_gate) 11 宣言のある vault/verdicts/ 配下の変更は終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 11 理由が vault/verdicts/ 配下は宣言があっても変更できない" "1" \
  "$(dg_has 'vault/verdicts/P-TEST/T-01.json: vault/verdicts/ 配下は宣言があっても変更できない')"

dg_setup
echo rule2 > "$DG/vault/rules/common/x.md"; dg_commit
dg_run
expect_eq "(diff_gate) 12 宣言のある vault/rules/ 配下の変更は終了コード 0" "0" "$DG_RC"
expect_eq "(diff_gate) 12 宣言のある vault/rules/ 配下の変更は違反の出力が空" "0" "$(wc -c < "$DG_OUT" | tr -d ' ')"

dg_setup
echo rule > "$DG/vault/rules/common/y.md"; dg_commit
dg_run
expect_eq "(diff_gate) 12b 宣言の無い vault/rules/ 配下の変更は終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 12b 理由が「成果物」に宣言されていない" "1" \
  "$(dg_has 'vault/rules/common/y.md: 「成果物」に宣言されていない')"

# 13 branch 側で宣言を書き足しても base の版で判定する
dg_setup
dg_replace "$DG/vault/tasks/P-TEST/T-01.md" '- `check_func` 関数' '- `check_func` 関数
- `extra.txt`'
echo extra > "$DG/extra.txt"; dg_commit
dg_run
expect_eq "(diff_gate) 13 branch 側で宣言を書き足しても終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 13 書き足したファイルは宣言外のまま違反" "1" \
  "$(dg_has 'extra.txt: 「成果物」に宣言されていない')"

# 14 15 16 .claude/ 配下の宣言無し
dg_setup
echo "y = 2" > "$DG/.claude/hooks/y.py"; dg_commit
dg_run
expect_eq "(diff_gate) 14 宣言の無い .claude/hooks/ のファイルは終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 14 .claude/hooks/y.py が違反として出る" "1" \
  "$(dg_has '.claude/hooks/y.py: 「成果物」に宣言されていない')"

dg_setup
echo '{"a": 1}' > "$DG/.claude/settings.json"; dg_commit
dg_run
expect_eq "(diff_gate) 15 宣言の無い .claude/settings.json は終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 15 .claude/settings.json が違反として出る" "1" \
  "$(dg_has '.claude/settings.json: 「成果物」に宣言されていない')"

dg_setup
printf -- '---\nname: creator\nmodel: m\n---\n' > "$DG/.claude/agents/creator.md"; dg_commit
dg_run
expect_eq "(diff_gate) 16 宣言の無い .claude/agents/ 配下は終了コード 1" "1" "$DG_RC"
expect_eq "(diff_gate) 16 .claude/agents/creator.md が違反として出る" "1" \
  "$(dg_has '.claude/agents/creator.md: 「成果物」に宣言されていない')"

# 17 18 19 終了コード 2
dg_setup
echo "- 進捗の追記" >> "$DG/vault/tasks/P-TEST/T-01.md"; dg_commit
dg_run P-TEST T-09 main work/b
expect_eq "(diff_gate) 17 base にタスク票が無い id は終了コード 2" "2" "$DG_RC"
expect_eq "(diff_gate) 17 標準出力は空で、理由は標準エラーに出る" "0 1" \
  "$(wc -c < "$DG_OUT" | tr -d ' ') $(grep -c '^\[diff_gate\]' "$DG_ERR")"
dg_run P-TEST T-01 no-such-base work/b
expect_eq "(diff_gate) 18 存在しない base は終了コード 2" "2" "$DG_RC"
dg_run P-TEST T-01 main
expect_eq "(diff_gate) 19 引数が3つだと終了コード 2" "2" "$DG_RC"

# 20 check() の import（02 と同じ変更）
dg_setup
echo extra > "$DG/extra.txt"; dg_commit
DG_CHK="$( cd "$DG" && python3 - "$ROOT/scripts" "$DG" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import diff_gate
v = diff_gate.check(sys.argv[2], "P-TEST", "T-01", "main", "work/b")
print(" ".join(p for p, _ in v))
PY
)"
expect_eq "(diff_gate) 20 check() が 02 と同じ変更で違反のパスのリストを返す" "extra.txt" "$DG_CHK"

echo
echo "== transition.py worktree（D-012 フェーズ4） =="
TW="$TMP/tw"
TWR="$TW/repo"
TWW="$TW/wt"
TWB="worktree-agent-sm"
TW_OUT="$TMP/tw_out.txt"
TW_ERR="$TMP/tw_err.txt"
tw_setup() { # $1=T-01 の status $2=attempt（一時リポジトリと worktree を作り直す。verdict は置かない）
  local st="$1" at="$2"
  rm -rf "$TW"
  mkdir -p "$TWR/vault/plans" "$TWR/vault/log" "$TWR/vault/verdicts/P-TEST" "$TWR/vault/tasks/P-TEST" "$TWR/src" "$TWR/.claude/agents"
  {
    echo "---"; echo "id: P-TEST"; echo "status: approved"; echo "---"
    echo "# ゴール"; echo "確認用の計画"; echo
    echo "## タスク表（状態の正本）"
    echo "| id | status | attempt | after | title | question |"
    echo "|---|---|---|---|---|---|"
    echo "| T-01 | $st | $at | - | A | |"
    echo "| T-02 | todo | 0 | T-01 | B | |"
    echo
    echo "## 計画の受け入れ基準"; echo "- 確認用"
  } > "$TWR/vault/plans/P-TEST.md"
  {
    echo "# T-01 確認用"; echo
    echo "## 目的"; echo "確認用"; echo
    echo "## 入力"; echo "- なし"; echo
    echo "## 成果物"; echo '- `src/ok.txt`（1ファイル）'; echo
    echo "## 受け入れ基準"; echo "- 基準"; echo
    echo "## 決定済み"; echo "- なし"; echo
    echo "## 進捗"
  } > "$TWR/vault/tasks/P-TEST/T-01.md"
  echo "- 2026-01-01 00:00 - draft→approved 人の指示: /plan approve P-TEST" > "$TWR/vault/log/P-TEST.md"
  echo base > "$TWR/src/ok.txt"
  printf -- '---\nname: creator\nmodel: smoke-creator\n---\n本文\n' > "$TWR/.claude/agents/creator.md"
  printf -- '---\nname: verifier\nmodel: smoke-verifier\n---\n本文\n' > "$TWR/.claude/agents/verifier.md"
  git -C "$TWR" init -q -b main
  git -C "$TWR" config user.name smoke
  git -C "$TWR" config user.email smoke@example.com
  git -C "$TWR" add -A
  git -C "$TWR" commit -q -m init
  git -C "$TWR" checkout -q -b work/p-test
  TW_PH="$(git -C "$TWR" rev-parse HEAD)"
  git -C "$TWR" worktree add -q -b "$TWB" "$TWW" "$TW_PH"
  TW_RP="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$TWW")"
}
tw_mod() { echo changed > "$TWW/src/ok.txt"; printf -- '- 進捗の追記\n' >> "$TWW/vault/tasks/P-TEST/T-01.md"; }
tw_commit() { git -C "$TWW" add -A; git -C "$TWW" commit -q -m "creator のコミット"; }
tw_verdict() { # $1=PASS|FAIL $2=attempt（未追跡で置く。FAIL の reasons は長い2件。TW_NOTE・TW_QUEST に期待値を入れる）
  python3 - "$TWR" "$1" "$2" <<'PY'
import json, os, re, sys
root, res, at = sys.argv[1], sys.argv[2], int(sys.argv[3])
r1 = "一つ目の理由|縦棒" + "あ" * 100
r2 = "二つ目の理由" + "い" * 150
def clean(s):
    return re.sub(r"\r\n|\r|\n", " ", s.replace("|", "／")).strip()
v = {"task": "P-TEST/T-01", "attempt": at, "result": res, "checked_at": "2026-01-01 00:00",
     "criteria": [{"text": "基準", "ok": res == "PASS", "note": "実行コマンド: x / 出力: y"}],
     "reasons": [] if res == "PASS" else [r1, r2]}
with open(os.path.join(root, "vault/verdicts/P-TEST/T-01.json"), "w", encoding="utf-8") as f:
    json.dump(v, f, ensure_ascii=False); f.write("\n")
with open(os.path.join(root, "..", "expect.txt"), "w", encoding="utf-8") as f:
    f.write(clean(r1)[:80] + "\n" + clean("／".join([r1, r2]))[:200] + "\n")
PY
  TW_NOTE="$(sed -n 1p "$TW/expect.txt")"
  TW_QUEST="$(sed -n 2p "$TW/expect.txt")"
}
tw_wtcount() { git -C "$TWR" rev-list --count "$TW_PH..$TWB" 2>/dev/null || echo gone; }
tw_run() { # transition.py を1回実行。TW_RC・TW_NEW・TW_PLAN・TW_WTN（worktree 側のコミットの増減）を設定する
  cp "$TWR/vault/plans/P-TEST.md" "$TW/plan.before"
  local n0 w0 w1
  n0="$(git -C "$TWR" rev-parse HEAD)"
  w0="$(tw_wtcount)"
  ( cd "$TWR" && python3 "$ROOT/scripts/transition.py" "$@" ) > "$TW_OUT" 2> "$TW_ERR"
  TW_RC=$?
  TW_N0="$n0"
  TW_NEW="$(git -C "$TWR" rev-list --count "$n0..HEAD")"
  cmp -s "$TW/plan.before" "$TWR/vault/plans/P-TEST.md" && TW_PLAN=same || TW_PLAN=diff
  w1="$(tw_wtcount)"
  if [ "$w1" = gone ]; then TW_WTN=gone; else TW_WTN=$((w1 - w0)); fi
  TW_OL="$(wc -l < "$TW_OUT" | tr -d ' ')"
}
tw_nochange() { echo "$TW_RC $TW_NEW $TW_PLAN $TW_WTN"; }
tw_row() { grep '^| T-01 |' "$TWR/vault/plans/P-TEST.md"; }
tw_state() { echo "$(git -C "$TWR" worktree list --porcelain | grep -c "^branch refs/heads/$TWB\$") $([ -d "$TWW" ] && echo yes || echo no) $(git -C "$TWR" show-ref --verify --quiet "refs/heads/$TWB" && echo yes || echo no)"; }
tw_logtail() { tail -n "${1:-1}" "$TWR/vault/log/P-TEST.md" | sed 's/^- [0-9-]* [0-9:]* //'; }
tw_wtflags() { TW_A=(--worktree "$TWW" --branch "$TWB" --plan-head "$TW_PH"); }

# 01〜03 review 正常
tw_setup doing 1; tw_mod; tw_wtflags
tw_run P-TEST T-01 review "${TW_A[@]}"
expect_eq "(transition-wt) 01 未コミット分が worktree で収集コミットされる" "P-TEST/T-01: creator 成果物をオーケストレーターが収集" \
  "$(git -C "$TWR" log -1 --format=%s "$TWB")"
expect_eq "(transition-wt) 02 宣言どおりの変更は終了コード 0" "0" "$TW_RC"
expect_eq "(transition-wt) 02 T-01 が review" "1" "$(tw_row | grep -c '^| T-01 | review | 1 |')"
expect_eq "(transition-wt) 03 log に記録行と doing→review の行がこの順で追記される" \
  "T-01 worktree path=$TW_RP branch=$TWB plan_head=$TW_PH
T-01 doing→review attempt=1 creator=smoke-creator" "$(tw_logtail 2)"

# 04〜06 review 宣言外
tw_setup doing 1; tw_mod; echo extra > "$TWW/extra.txt"; tw_wtflags
tw_run P-TEST T-01 review "${TW_A[@]}"
expect_eq "(transition-wt) 04 宣言外のファイルがあると終了コード 3" "3" "$TW_RC"
expect_eq "(transition-wt) 04 T-01 が doing・attempt=2" "1" "$(tw_row | grep -c '^| T-01 | doing | 2 |')"
expect_eq "(transition-wt) 21 差し戻し（終了コード3）の標準出力は1行" "1" "$TW_OL"
expect_eq "(transition-wt) 05 タスク票の末尾が差し戻しの1行" "- 差し戻し（attempt=1）: 宣言外の変更 extra.txt" \
  "$(tail -n 1 "$TWR/vault/tasks/P-TEST/T-01.md")"
expect_eq "(transition-wt) 05 log の最後の行が doing→doing で終わり creator= が無い" "T-01 doing→doing attempt=2 宣言外の変更: extra.txt" "$(tw_logtail 1)"
expect_eq "(transition-wt) 06 worktree とブランチが消える" "0 no no" "$(tw_state)"

# 07 review 上限
tw_setup doing 3; tw_mod; echo extra > "$TWW/extra.txt"; tw_wtflags
tw_run P-TEST T-01 review "${TW_A[@]}"
expect_eq "(transition-wt) 07 attempt が上限で宣言外のファイルがあると終了コード 4" "4" "$TW_RC"
expect_eq "(transition-wt) 07 T-01 が blocked で question に宣言外のパス" "1" "$(tw_row | grep '^| T-01 | blocked | 3 |' | grep -c 'extra\.txt')"
expect_eq "(transition-wt) 07 worktree が残る" "1 yes yes" "$(tw_state)"
expect_eq "(transition-wt) 21 blocked（終了コード4）の標準出力は1行" "1" "$TW_OL"

# 08 新規コミット無し
tw_setup doing 1; tw_wtflags
tw_run P-TEST T-01 review "${TW_A[@]}"
expect_eq "(transition-wt) 08 新規コミットが無い worktree は終了コード 4" "4" "$TW_RC"
expect_eq "(transition-wt) 08 question が新規コミット無しの文面" "1" \
  "$(tw_row | grep '^| T-01 | blocked |' | grep -c 'worktree に新規コミットが無い（マージ対象の差分が無い）')"

# 09 検証に通らない worktree・ブランチ
tw_setup doing 1; tw_mod; tw_commit
tw_run P-TEST T-01 review --worktree "$TWW" --branch worktree-agent-zz --plan-head "$TW_PH"
expect_eq "(transition-wt) 09 ブランチ名の不一致は何も変えない" "1 0 same 0" "$(tw_nochange)"
tw_run P-TEST T-01 review --worktree "$TW/nowhere" --branch "$TWB" --plan-head "$TW_PH"
expect_eq "(transition-wt) 09 未登録のパスは何も変えない" "1 0 same 0" "$(tw_nochange)"
git -C "$TWR" worktree add -q -b feature-x "$TW/wt2" "$TW_PH"
tw_run P-TEST T-01 review --worktree "$TW/wt2" --branch feature-x --plan-head "$TW_PH"
expect_eq "(transition-wt) 09 worktree-agent- で始まらないブランチは何も変えない" "1 0 same 0" "$(tw_nochange)"

# 10〜13 done 正常
tw_setup review 1; tw_mod; tw_commit; echo out > "$TWW/verifier-out.txt"; tw_verdict PASS 1
tw_run P-TEST T-01 done --worktree "$TWW" --branch "$TWB" --plan-head "$TW_PH"
TW_MC="$(git -C "$TWR" log -1 --format=%H --grep='^P-TEST/T-01: マージ$')"
expect_eq "(transition-wt) 10 終了コード 0" "0" "$TW_RC"
expect_eq "(transition-wt) 10 件名 P-TEST/T-01: マージ の親が2つのコミットができる" "3" \
  "$([ -n "$TW_MC" ] && git -C "$TWR" rev-list --parents -n 1 "$TW_MC" | wc -w | tr -d ' ')"
expect_eq "(transition-wt) 11 T-01 が done" "1" "$(tw_row | grep -c '^| T-01 | done | 1 |')"
expect_eq "(transition-wt) 11 最後のコミットに verdict が含まれる" "1" \
  "$(git -C "$TWR" show --name-only --format= HEAD | grep -c '^vault/verdicts/P-TEST/T-01.json$')"
expect_eq "(transition-wt) 12 worktree とブランチが消える" "0 no no" "$(tw_state)"
expect_eq "(transition-wt) 13 未追跡のファイルはマージコミットに入らない" "0" \
  "$(git -C "$TWR" ls-tree -r --name-only HEAD | grep -c 'verifier-out.txt')"

# 24 pr_body（10 の後のリポジトリ）
TW_H1="$(git -C "$TWR" log -1 --format=%h --grep='^P-TEST/T-01: review→done$')"
TW_PB="$( cd "$TWR" && python3 "$ROOT/scripts/pr_body.py" P-TEST 2>/dev/null | grep '^| T-01 |' )"
expect_eq "(transition-wt) 24 pr_body の T-01 の commit 列が transition.py の done のコミット" "| T-01 | A | $TW_H1 " "$(echo "$TW_PB" | cut -d'|' -f1-4)"
expect_eq "(transition-wt) 24 短縮ハッシュが空でない" "1" "$([ -n "$TW_H1" ] && echo 1 || echo 0)"

# 14〜15 done 衝突
tw_setup review 1; tw_mod; tw_commit; tw_verdict PASS 1
echo "plan side" > "$TWR/src/ok.txt"; git -C "$TWR" add src/ok.txt; git -C "$TWR" commit -q -m "計画ブランチ側の変更"
tw_run P-TEST T-01 done --worktree "$TWW" --branch "$TWB" --plan-head "$TW_PH"
expect_eq "(transition-wt) 14 衝突する変更は終了コード 4" "4" "$TW_RC"
expect_eq "(transition-wt) 14 マージ中の状態が残らない" "no" \
  "$(f="$(git -C "$TWR" rev-parse --git-path MERGE_HEAD)"; { [ -e "$f" ] || [ -e "$TWR/$f" ]; } && echo yes || echo no)"
expect_eq "(transition-wt) 21 衝突の blocked の標準出力は1行" "1" "$TW_OL"
expect_eq "(transition-wt) 15 T-01 が blocked で question に衝突したファイル" "1" "$(tw_row | grep '^| T-01 | blocked | 1 |' | grep -c 'src/ok\.txt')"
expect_eq "(transition-wt) 15 worktree が残る" "1 yes yes" "$(tw_state)"

# 16 done 宣言外をコミット済み
tw_setup review 1; tw_mod; echo extra > "$TWW/extra.txt"; tw_commit; tw_verdict PASS 1
tw_run P-TEST T-01 done --worktree "$TWW" --branch "$TWB" --plan-head "$TW_PH"
expect_eq "(transition-wt) 16 宣言外のコミットは終了コード 4" "4" "$TW_RC"
expect_eq "(transition-wt) 16 マージコミットができず増えたコミットの親が1つ" "1 2" \
  "$(git -C "$TWR" rev-list --count "$TW_N0..HEAD") $(git -C "$TWR" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')"
expect_eq "(transition-wt) 16 T-01 が blocked" "1" "$(tw_row | grep -c '^| T-01 | blocked | 1 |')"

# 17 done FAIL の verdict
tw_setup review 1; tw_mod; tw_commit; tw_verdict FAIL 1
tw_run P-TEST T-01 done --worktree "$TWW" --branch "$TWB" --plan-head "$TW_PH"
expect_eq "(transition-wt) 17 FAIL の verdict は何も変えず終了コード 1" "1 0 same 0" "$(tw_nochange)"
expect_eq "(transition-wt) 17 worktree が残る" "1 yes yes" "$(tw_state)"

# 18 doing FAIL の再試行
tw_setup review 1; tw_mod; tw_commit; tw_verdict FAIL 1
tw_run P-TEST T-01 doing --worktree "$TWW" --branch "$TWB"
expect_eq "(transition-wt) 18 FAIL の verdict で終了コード 3" "3" "$TW_RC"
expect_eq "(transition-wt) 18 T-01 が doing・attempt=2" "1" "$(tw_row | grep -c '^| T-01 | doing | 2 |')"
expect_eq "(transition-wt) 18 log の補足が reasons の先頭を80文字で切ったもの" \
  "T-01 review→doing attempt=2 verifier=smoke-verifier $TW_NOTE" "$(tw_logtail 1)"
expect_eq "(transition-wt) 18 worktree とブランチが消える" "0 no no" "$(tw_state)"
expect_eq "(transition-wt) 21 再試行（終了コード3）の標準出力は1行" "1" "$TW_OL"

# 19 doing 上限の FAIL
tw_setup review 3; tw_mod; tw_commit; tw_verdict FAIL 3
tw_run P-TEST T-01 doing --worktree "$TWW" --branch "$TWB"
expect_eq "(transition-wt) 19 attempt が上限の FAIL で終了コード 4" "4" "$TW_RC"
expect_eq "(transition-wt) 19 T-01 が blocked で question が reasons を200文字で切ったもの" "| T-01 | blocked | 3 | - | A | $TW_QUEST |" "$(tw_row)"
expect_eq "(transition-wt) 19 question は200文字" "200" "$(printf '%s' "$TW_QUEST" | python3 -c 'import sys;print(len(sys.stdin.read()))')"

# 20 blocked
tw_setup doing 1; tw_mod; printf '質問A|B\n次の行\n' > "$TW/q.txt"
tw_run P-TEST T-01 blocked --worktree "$TWW" --branch "$TWB" --plan-head "$TW_PH" --question-file "$TW/q.txt"
expect_eq "(transition-wt) 20 --question-file 付きの blocked は終了コード 4" "4" "$TW_RC"
expect_eq "(transition-wt) 20 T-01 が blocked" "1" "$(tw_row | grep -c '^| T-01 | blocked | 1 | - | A | 質問A／B 次の行 |$')"
expect_eq "(transition-wt) 20 log に記録行と doing→blocked の行がこの順で書かれる" \
  "T-01 worktree path=$TW_RP branch=$TWB plan_head=$TW_PH
T-01 doing→blocked attempt=1 creator=smoke-creator" "$(tw_logtail 2)"
expect_eq "(transition-wt) 20 worktree が残り収集コミットができない" "1 yes yes 0" "$(tw_state) $TW_WTN"
expect_eq "(transition-wt) 21 blocked の報告の標準出力は1行" "1" "$TW_OL"

# 22 --worktree 無しはフェーズ2どおり
tw_setup doing 1; tw_mod; tw_commit
tw_run P-TEST T-01 review
expect_eq "(transition-wt) 22 --worktree 無しの review はフェーズ2どおりで worktree に触れない" "0 1 diff 0 1 yes yes" "$TW_RC $TW_NEW $TW_PLAN $TW_WTN $(tw_state)"
tw_setup review 1; tw_mod; tw_commit; tw_verdict PASS 1
tw_run P-TEST T-01 done
expect_eq "(transition-wt) 22 --worktree 無しの done はフェーズ2どおりで worktree に触れない" "0 1 diff 0 1 yes yes" "$TW_RC $TW_NEW $TW_PLAN $TW_WTN $(tw_state)"
tw_setup doing 1; tw_mod; tw_commit
tw_run P-TEST T-01 doing
expect_eq "(transition-wt) 22 --worktree 無しの doing はフェーズ2どおりで worktree に触れない" "0 1 diff 0 1 yes yes" "$TW_RC $TW_NEW $TW_PLAN $TW_WTN $(tw_state)"

# 23 引数の誤り
tw_setup doing 1; tw_mod
tw_run P-TEST T-01 review --worktree "$TWW" --branch "$TWB"
expect_eq "(transition-wt) 23 --plan-head 無しの review は終了コード 2" "2" "$TW_RC"
tw_run P-TEST T-01 review --worktree "$TWW" --plan-head "$TW_PH"
expect_eq "(transition-wt) 23 --branch 無しの --worktree は終了コード 2" "2" "$TW_RC"
tw_run P-TEST T-01,T-02 review --worktree "$TWW" --branch "$TWB" --plan-head "$TW_PH"
expect_eq "(transition-wt) 23 --worktree と複数の id は終了コード 2" "2" "$TW_RC"

# 25 pr_body の件名のパターン
tw_setup doing 1
git -C "$TWR" commit -q --allow-empty -m 'P-TEST/T-01,T-02: review→done'
TW_HA="$(git -C "$TWR" log -1 --format=%h)"
git -C "$TWR" commit -q --allow-empty -m 'P-TEST/T-03: done'
TW_HB="$(git -C "$TWR" log -1 --format=%h)"
python3 - "$TWR/vault/plans/P-TEST.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("| T-02 | todo | 0 | T-01 | B | |", "| T-02 | todo | 0 | T-01 | B | |\n| T-03 | todo | 0 | - | C | |\n| T-04 | todo | 0 | - | D | |")
open(p, "w", encoding="utf-8").write(s)
PY
TW_PB="$( cd "$TWR" && python3 "$ROOT/scripts/pr_body.py" P-TEST 2>/dev/null )"
expect_eq "(transition-wt) 25 件名に複数 id のある done のコミットが T-01 の行に出る" "| T-01 | A | $TW_HA | - |" "$(echo "$TW_PB" | grep '^| T-01 |')"
expect_eq "(transition-wt) 25 同じコミットが T-02 の行に出る" "| T-02 | B | $TW_HA | - |" "$(echo "$TW_PB" | grep '^| T-02 |')"
expect_eq "(transition-wt) 25 従来の件名のコミットが T-03 の行に出る" "| T-03 | C | $TW_HB | - |" "$(echo "$TW_PB" | grep '^| T-03 |')"
expect_eq "(transition-wt) 25 done のコミットが無いタスクの行は -" "| T-04 | D | - | - |" "$(echo "$TW_PB" | grep '^| T-04 |')"

# --- スキルの記述の検査 ---
RUN_SKILL="$ROOT/.claude/skills/run/SKILL.md"
DESIGN_SKILL="$ROOT/.claude/skills/design/SKILL.md"
rs_step7="$(awk '/^## 7\./{f=1;next} /^## 8\./{f=0} f' "$RUN_SKILL")"
rs_add="$(printf '%s\n' "$rs_step7" | grep -nF -m1 'git add vault/plans/<計画ID>.md' | cut -d: -f1)"
rs_fin="$(printf '%s\n' "$rs_step7" | grep -nF -m1 'bash scripts/vcs_finish.sh' | cut -d: -f1)"
if [ -n "$rs_add" ] && [ -n "$rs_fin" ] && [ "$rs_add" -lt "$rs_fin" ]; then rs1=ok; else rs1=NG; fi
expect_eq "(run-skill-1) run 手順7で計画票のコミットが vcs_finish.sh より前にある" ok "$rs1"
if ! grep -qF 'gh issue create' "$RUN_SKILL" && grep -qF 'gh api repos/{owner}/{repo}/issues' "$RUN_SKILL"; then rs2=ok; else rs2=NG; fi
expect_eq "(run-skill-2) run の issue 起票が REST（gh issue create が無い）" ok "$rs2"
if grep -qF '`gh api` の PR 作成に渡すはずだった' "$RUN_SKILL" && grep -qF '`gh api` の PR 作成に渡すはずだった' "$DESIGN_SKILL"; then rs3=ok; else rs3=NG; fi
expect_eq "(run-skill-3) run・design の MCP 代替が gh api の PR 作成を引き継ぐ" ok "$rs3"

if ! grep -qF '起点コミット' "$ROOT/.claude/agents/creator.md" "$ROOT/.claude/agents/verifier.md" "$ROOT/.claude/agents/planner.md"; then ag1=ok; else ag1=NG; fi
expect_eq "(agents-1) creator・verifier・planner の定義に「起点コミット」の語が無い" ok "$ag1"

# --- 主な文書の参照切れの検査 ---
refcheck() { # $1=ルート。存在しないパスを <文書>:<行>: <パス> で出す
  python3 - "$1" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
if os.path.exists(os.path.join(root, ".claude/harness-manifest.json")):
    sys.exit(0)
docs = [".claude/ai-harness.md"]
docs += sorted(os.path.relpath(p, root) for p in glob.glob(os.path.join(root, ".claude/skills/*/SKILL.md")))
docs += sorted(os.path.relpath(p, root) for p in glob.glob(os.path.join(root, ".claude/agents/*.md")))
docs += ["README.md", "docs/vault-spec.md", "docs/runbook.md", "docs/install.md"]
excl = {"vault/designs/D-xxx.md", ".claude/projects", ".claude/harness-manifest.json", ".claude/settings.local.json"}
for d in docs:
    f = os.path.join(root, d)
    if not os.path.isfile(f):
        continue
    with open(f, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            for m in re.finditer(r"`([^`\n]+)`", line):
                p = m.group(1)
                if not p.startswith(("vault/", "scripts/", "docs/", ".claude/")):
                    continue
                if re.search(r"[<*{$\s]", p) or p.startswith("vault/rules/") or p in excl:
                    continue
                if not os.path.exists(os.path.join(root, p)):
                    print(f"{d}:{n}: {p}")
PY
}

RC="$TMP/refcheck"
expect_eq "(ref-1) 主な文書のバッククォート内のパスがすべて存在する" "" "$(refcheck "$ROOT")"

mkdir -p "$RC/a/.claude/skills/x" "$RC/a/.claude/agents" "$RC/a/docs"
printf '`scripts/no-such-a.sh`\n' > "$RC/a/.claude/ai-harness.md"
printf '`docs/no-such-b.md`\n' > "$RC/a/.claude/skills/x/SKILL.md"
printf '`vault/no-such-c.md`\n' > "$RC/a/.claude/agents/y.md"
printf 'なし\n`.claude/no-such-d.md`\n' > "$RC/a/README.md"
printf '`docs/no-such-e.md`\n`docs/install.md`\n' > "$RC/a/docs/install.md"
printf '`docs/no-such-f.md`\n' > "$RC/a/docs/decisions.md"
RC_WANT='.claude/ai-harness.md:1: scripts/no-such-a.sh
.claude/skills/x/SKILL.md:1: docs/no-such-b.md
.claude/agents/y.md:1: vault/no-such-c.md
README.md:2: .claude/no-such-d.md
docs/install.md:1: docs/no-such-e.md'
expect_eq "(ref-2) 存在しないパスを対象の文書ごとに見つけ、対象外の文書は見ない" "$RC_WANT" "$(refcheck "$RC/a")"

mkdir -p "$RC/b"
printf '%s\n' '`vault/<id>.md`' '`scripts/*.sh`' '`docs/{a,b}.md`' '`vault/$X.md`' '`docs/a b.md`' '`vault/rules/x.md`' '`vault/designs/D-xxx.md`' '`.claude/projects`' '`.claude/harness-manifest.json`' '`.claude/settings.local.json`' > "$RC/b/README.md"
expect_eq "(ref-3) 雛形・vault/rules/ 配下・除外リストは数えない" "" "$(refcheck "$RC/b")"

mkdir -p "$RC/c/.claude"
printf '{}' > "$RC/c/.claude/harness-manifest.json"
printf '`scripts/no-such.sh`\n' > "$RC/c/README.md"
expect_eq "(ref-4) 導入先（.claude/harness-manifest.json がある）では検査しない" "" "$(refcheck "$RC/c")"

echo
echo "smoke: pass=$PASS_N fail=$FAIL_N"
[ "$FAIL_N" -eq 0 ]
