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
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

SGTMP="$(mktemp -d)"
mkdir -p "$SGTMP/vault/plans"
git -C "$SGTMP" init -q -b main
git -C "$SGTMP" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
echo dirty > "$SGTMP/x.txt"
expect "(f) 未コミットの変更がある → ブロック" block \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$SGTMP" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")" "コミット"
rm -f "$SGTMP/x.txt"
expect "(g) 未コミットの変更が無い → 許可（既存判定へ進む）" allow \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$SGTMP" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")"
rm -rf "$SGTMP"

# worktree 委譲（issue #56 / D-008 フェーズ2）。agent_write_guard.py の (delegate) テスト・
# plan_guard.py の (delegate plan_guard) テストと同じ型：一時 worktree に判定結果が変わる
# 差し替えスクリプトを置き、cwd をその worktree に向けたペイロードをメインリポジトリ側の
# stop_gate.py に渡す。stop_gate.py は has_uncommitted_changes() を持つため、ローカル判定に
# フォールバックさせるテスト（二重委譲防止・委譲失敗）では、CLAUDE_PROJECT_DIR 側のリポジトリを
# 事前に commit してクリーンな状態にしておく（さもないと未コミット変更ブロックが先に発火する）。
DWSMAIN="$(mktemp -d)"
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
git -C "$DWSMAIN" add -A
git -C "$DWSMAIN" -c user.email=t@example.com -c user.name=t commit -q -m plan
DWSLEAF="$(mktemp -d)"; rmdir "$DWSLEAF"
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

DWSMAIN2="$(mktemp -d)"
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
DWSLEAF2="$(mktemp -d)"; rmdir "$DWSLEAF2"
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
expect_guard "verifier が Bash で git commit → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
expect_guard "verifier が Bash でテスト実行 → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"python3 -m pytest -q"}}')"
expect_guard "planner が vault/tasks/ に Write → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/tasks/T-0002.md"}}')"
expect_guard "planner が vault/todo.md に Edit → 拒否" deny \
  "$(run_guard '{"agent_type":"planner","tool_name":"Edit","tool_input":{"file_path":"'"$TMP"'/vault/todo.md"}}')"
expect_guard "メインエージェントが README.md に Edit → 許可" allow \
  "$(run_guard '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMP"'/README.md"}}')"
expect_guard "gh api で vault/rules/ へ PUT → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"gh api -X PUT repos/o/r/contents/vault/rules/common/roles.md -f message=m -f content=Zm9v -f sha=abc"}}')"
expect_guard "gh api で -X 指定なしでも vault/rules/ を対象に -f content → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"gh api repos/o/r/contents/vault/rules/common/roles.md -f content=Zm9v -f message=m"}}')"
expect_guard "curl で api.github.com の vault/rules/ へ PUT → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"curl -X PUT -H \"Authorization: token x\" https://api.github.com/repos/o/r/contents/vault/rules/common/roles.md"}}')"
expect_guard "vault/rules/ を含まない gh api issues 一覧 → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"gh api repos/o/r/issues"}}')"
expect_guard "vault/rules/ を含まない curl コマンド → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"curl https://api.github.com/repos/o/r/contents/README.md"}}')"
expect_guard "verifier が Bash で root 外（tmp）だけに mkdir/cp → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"mkdir -p /tmp/xxx && cp scripts/install.sh /tmp/xxx/install.sh"}}')"
expect_guard "verifier が Bash で root 内の許可外パス（vault/rules/）へ cp → 拒否（既存挙動を維持）" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"cp x.txt vault/rules/common/a.md"}}')"
expect_guard "verifier が Bash で root 外（tmp）と root 内の許可外パスが混在 → 拒否（root 外許可がバイパスの抜け穴にならない）" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"mkdir -p /tmp/xxx && cp vault/rules/common/a.md /tmp/xxx/"}}')"

make_plan_task T-0001 doing 1
expect_guard "(a) doing 中にメインエージェントが vault/rules/ へ Write → 拒否" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_plan_task T-0001 todo 0
expect_guard "(b) todo のみ（doing/review 無し）でもメインエージェントが vault/rules/ へ Write → 拒否" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_plan_task T-0001 doing 1
expect_guard "(c) doing 中に verifier が vault/verdicts/ へ Write → 許可（従来どおり）" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/verdicts/T-0001.json"}}')"
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
expect_guard "(g) approved な計画票が0件でも vault/rules/ へ Write → 拒否" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_plan "P-A" "approved" "| T-0001 | todo | 0 | - | A | |"
make_plan "P-B" "approved" "| T-0001 | doing | 1 | - | B | |"
expect_guard "(h) approved な計画票が2件以上でも vault/rules/ へ Write → 拒否" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"

GTMP="$(mktemp -d)"
git -C "$GTMP" init -q -b main
git -C "$GTMP" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
expect_guard "(i) main で git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) grep の検索語に git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep -n \"git commit\" README.md"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) git log --grep の引数に git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git log --oneline --grep \"git commit\""}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) echo の引用符内に git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo \"run git commit later\""}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) ヒアドキュメント本文に git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat <<\"EOF\"\ngit commit -m x\nEOF"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) パイプの grep に git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat README.md | grep \"git commit\""}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) && の後ろの git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git add a && git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) ; の後ろの git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo x; git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) 改行区切りの後ろの git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo a\ngit commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) 先頭の代入付きの git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"GIT_AUTHOR_NAME=x git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) 絶対パスのコマンド語の git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) コマンド置換を含む git commit は従来判定で → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<\"EOF\"\nmsg\nEOF\n)\""}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) bash -c 内の git commit は従来判定で → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"bash -c \"git commit -m x\""}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) git -C . で前置オプション付きの git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -C . commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(bash-parse-main) git -c で前置オプション付きの git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -c user.name=x commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
git -C "$GTMP" checkout -q -b work/p-test
expect_guard "(j) work ブランチで git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
git -C "$GTMP" checkout -q main
git -C "$GTMP" checkout -q -b design/d-999
expect_guard "(k) design/d-999 ブランチで git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
expect_guard "(l) design/d-999 ブランチで vault/designs/D-999.md へ Write → 許可" allow \
  "$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$GTMP"'/vault/designs/D-999.md"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
rm -rf "$GTMP"

expect_guard "creator が vault/plans/ に Write → 拒否" deny \
  "$(run_guard '{"agent_type":"creator","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/plans/P-X.md"}}')"
expect_guard "creator が vault/log/ に Write → 拒否" deny \
  "$(run_guard '{"agent_type":"creator","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/log/P-X.md"}}')"
expect_guard "creator が README.md に Write → 許可" allow \
  "$(run_guard '{"agent_type":"creator","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/README.md"}}')"

WMAIN="$(mktemp -d)"
git -C "$WMAIN" init -q -b main
git -C "$WMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
WLEAF="$(mktemp -d)"; rmdir "$WLEAF"
git -C "$WMAIN" worktree add -q -b work/p-wt "$WLEAF" >/dev/null 2>&1
mkdir -p "$WLEAF/vault/verdicts"
expect_guard "(worktree) verifier が worktree 内の vault/verdicts/ に Write（CLAUDE_PROJECT_DIR はメインチェックアウト側のまま）→ 許可" allow \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$WLEAF"'/vault/verdicts/T-1.json"}}' | CLAUDE_PROJECT_DIR="$WMAIN" python3 "$GUARD_HOOK")"
git -C "$WMAIN" worktree remove -q --force "$WLEAF" >/dev/null 2>&1
rm -rf "$WMAIN" "$WLEAF"

WMAIN2="$(mktemp -d)"
git -C "$WMAIN2" init -q -b main
git -C "$WMAIN2" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
WLEAF2="$(mktemp -d)"; rmdir "$WLEAF2"
git -C "$WMAIN2" worktree add -q -b work/p-wt-nested "$WLEAF2" >/dev/null 2>&1
expect_guard "(worktree nested) verifier が worktree 内の未作成ネストディレクトリ vault/verdicts/P-NEW/ に Write（事前 mkdir なし）→ 許可" allow \
  "$(printf '%s' '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$WLEAF2"'/vault/verdicts/P-NEW/T-1.json"}}' | CLAUDE_PROJECT_DIR="$WMAIN2" python3 "$GUARD_HOOK")"
git -C "$WMAIN2" worktree remove -q --force "$WLEAF2" >/dev/null 2>&1
rm -rf "$WMAIN2" "$WLEAF2"

# 委譲判定を確認するテストでは、Bash + 相対パスの vault/rules/ ターゲット（cp x.txt vault/rules/...）を
# ローカル判定の目印として使う（既存の「root 内の許可外パスへ cp」テストと同じ相対パス方式）。
# Write/Edit + 絶対 file_path 方式だと、mktemp が返す tmp パスと git rev-parse --show-toplevel が
# 返す解決済みパス（macOS では /var/... が /private/var/... に解決される）が食い違い、
# normalize() の prefix 比較が環境依存で崩れてしまうため使わない。
DWTMAIN="$(mktemp -d)"
git -C "$DWTMAIN" init -q -b main
git -C "$DWTMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
DWTLEAF="$(mktemp -d)"; rmdir "$DWTLEAF"
git -C "$DWTMAIN" worktree add -q -b work/p-delegate "$DWTLEAF" >/dev/null 2>&1
mkdir -p "$DWTLEAF/.claude/hooks"
cat > "$DWTLEAF/.claude/hooks/agent_write_guard.py" <<'PYEOF'
#!/usr/bin/env python3
import json, sys
json.load(sys.stdin)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}))
PYEOF
expect_guard "(delegate) worktree 側が常に allow を返す差し替え → 通常なら拒否される vault/rules/ への書き込みも委譲先の判定（allow）が採用される" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cp x.txt vault/rules/common/a.md"},"cwd":"'"$DWTLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWTMAIN" python3 "$GUARD_HOOK")"

expect_guard "(delegate) 呼び出し前に _HOOK_DELEGATED が既にセット済み → 二重委譲を防止しローカル判定にフォールバック（vault/rules/ 拒否が効く）" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cp x.txt vault/rules/common/a.md"},"cwd":"'"$DWTLEAF"'"}' | CLAUDE_PROJECT_DIR="$DWTMAIN" _HOOK_DELEGATED=1 python3 "$GUARD_HOOK")"

git -C "$DWTMAIN" worktree remove -q --force "$DWTLEAF" >/dev/null 2>&1
rm -rf "$DWTMAIN" "$DWTLEAF"

DWTMAIN2="$(mktemp -d)"
git -C "$DWTMAIN2" init -q -b main
git -C "$DWTMAIN2" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
DWTLEAF2="$(mktemp -d)"; rmdir "$DWTLEAF2"
git -C "$DWTMAIN2" worktree add -q -b work/p-delegate-fail "$DWTLEAF2" >/dev/null 2>&1
mkdir -p "$DWTLEAF2/.claude/hooks"
cat > "$DWTLEAF2/.claude/hooks/agent_write_guard.py" <<'PYEOF'
#!/usr/bin/env python3
import sys
sys.exit(1)
PYEOF
expect_guard "(delegate) 委譲先 subprocess が非0で終了 → フェイルオープンでメインリポジトリ側のローカル判定にフォールバック（vault/rules/ 拒否が引き続き効く）" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cp x.txt vault/rules/common/a.md"},"cwd":"'"$DWTLEAF2"'"}' | CLAUDE_PROJECT_DIR="$DWTMAIN2" python3 "$GUARD_HOOK")"
git -C "$DWTMAIN2" worktree remove -q --force "$DWTLEAF2" >/dev/null 2>&1
rm -rf "$DWTMAIN2" "$DWTLEAF2"

expect_guard "verifier が Bash で 2>&1 を含む非書き込みコマンド → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"echo x 2>&1"}}')"
expect_guard "planner が Bash で 2>&1 を含む非書き込みコマンド → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"echo x 2>&1"}}')"
expect_guard "(issue #54 placeholder) verifier が山括弧プレースホルダーを含むだけの読み取り専用 grep → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"grep -n -A 5 \"doing\\u2192review attempt=<n>\" .claude/skills/run/SKILL.md"}}')"
expect_guard "(issue #54 placeholder) planner が <計画ID> プレースホルダーを含むだけの読み取り専用 grep → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"grep -n \"vault/tasks/<計画ID>/<id>.md\" docs/vault-spec.md"}}')"
expect_guard "(issue #54 placeholder) verifier がプレースホルダーと実リダイレクト（許可外パス）が混在するコマンド → 実リダイレクトは拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"echo \"doing\\u2192review attempt=<n>\" > README.md"}}')"
expect_guard "(issue #54 placeholder) verifier がプレースホルダーと実リダイレクト（許可ディレクトリ内）が混在するコマンド → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"echo \"doing\\u2192review attempt=<n>\" > '"$TMP"'/vault/verdicts/T-1.json"}}')"
expect_guard "(issue #54 placeholder) verifier が <n> を含む rm コマンド → 破壊的操作として拒否（プレースホルダー有無に関係なく維持）" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"rm attempt=<n>.txt"}}')"
expect_guard "(issue #54 placeholder) verifier が <n> を含む git commit → 破壊的操作として拒否（プレースホルダー有無に関係なく維持）" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"git commit -m \"attempt=<n>\""}}')"
expect_guard "(bash-parse-allowed) verifier が grep の引数の git add → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"grep -n \"git add\" .claude/skills/run/SKILL.md"}}')"
expect_guard "(bash-parse-allowed) verifier が許可ディレクトリへの mkdir -p → 許可" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"mkdir -p vault/verdicts/P-X"}}')"
expect_guard "(bash-parse-allowed) planner が grep の引数の rm -rf → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"grep -n \"rm -rf\" docs/vault-spec.md"}}')"
expect_guard "(bash-parse-allowed) planner が grep の引数の doing->review → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"grep -n \"doing->review\" docs/vault-spec.md"}}')"
expect_guard "(bash-parse-allowed) verifier が git add → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"git add vault/verdicts/P-X/T-01.json"}}')"
expect_guard "(bash-parse-allowed) verifier が許可ディレクトリ内の rm → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"rm vault/verdicts/P-X/T-01.json"}}')"
expect_guard "(bash-parse-allowed) verifier が許可外へのリダイレクト → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"echo x > README.md"}}')"
expect_guard "(bash-parse-allowed) verifier が root 内をコピー先にする cp → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"cp /tmp/a vault/verdicts/P-X/T-01.json"}}')"
expect_guard "(bash-parse-allowed) verifier が tee → 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"tee vault/verdicts/P-X/T-01.json"}}')"
expect_guard "(bash-parse-allowed) verifier が bash -c のインタプリタ（従来判定）→ 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"bash -c \"echo x > README.md\""}}')"
expect_guard "(bash-parse-allowed) verifier がコマンド置換内の git commit（従来判定）→ 拒否" deny \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"echo \"$(git commit -m x)\""}}')"
expect_guard "(bash-parse-allowed) planner が awk の print 書き込み（従来判定）→ 拒否" deny \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"awk '"'"'{print > \"README.md\"}'"'"' README.md"}}')"
expect_guard "(bash-parse-allowed) planner が許可内リダイレクトと許可外 rm の連結 → 拒否" deny \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"echo x > vault/tasks/T.md; rm README.md"}}')"

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
expect_guard "(done-write) Bash のリダイレクトで done のタスク票へ追記 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"printf x >> vault/tasks/P-FIX/T-01.md"}}')" "done"
expect_guard "(done-write) Bash の sed -i で done のタスク票を書き換え → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ vault/tasks/P-FIX/T-01.md"}}')" "done"
# Bash の書き込み動詞が git add / git commit だけなら done 判定の対象外（issue #84）。混在は従来どおり拒否。
expect_guard "(done-write) メインの git add で done の verdict と計画票をステージ（issue #84 再現）→ 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git add vault/verdicts/P-FIX/T-01.json vault/plans/P-FIX.md"}}')"
expect_guard "(done-write) メインの git commit -m \"P-FIX/T-01: done\" → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"P-FIX/T-01: done\""}}')"
expect_guard "(done-write) agent_type=creator の git add で done の verdict をステージ → 許可（agent_type に依存しない）" allow \
  "$(run_guard '{"agent_type":"creator","tool_name":"Bash","tool_input":{"command":"git add vault/verdicts/P-FIX/T-01.json"}}')"
expect_guard "(done-write) git add && git commit の連結 → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git add vault/verdicts/P-FIX/T-01.json && git commit -m x"}}')"
expect_guard "(done-write) commit メッセージ中の done verdict パス文字列は書き込み対象ではない → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add vault/verdicts/P-FIX/T-01.json\""}}')"
expect_guard "(done-write) git add に done の verdict へのリダイレクトが混在 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git add x && echo x > vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(done-write) git add に sed -i が混在 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git add x && sed -i s/a/b/ vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(done-write) git add に cp が混在 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git add x; cp /tmp/y vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(done-write) git rm で done の verdict を削除 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git rm vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(done-write) commit メッセージ内のコマンド置換で done のタスク票へ書き込み → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(echo x > vault/tasks/P-FIX/T-01.md)\""}}')" "done"
# Bash 判定を analyze_bash_writes に載せ替え（issue #87・#91）。git add/commit は除き、実際の書き込み対象で判定する
expect_guard "(bash-parse-done) #87 log 追記と done verdict の git add の && 連結 → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"printf '%s' \"- 2026-10-02 10:00 T-01 review→done attempt=1 verifier=sonnet\" >> vault/log/P-FIX.md && git add vault/plans/P-FIX.md vault/log/P-FIX.md vault/verdicts/P-FIX/T-01.json"}}')"
expect_guard "(bash-parse-done) git add と git commit の改行区切り → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git add vault/verdicts/P-FIX/T-01.json\ngit commit -m \"P-FIX/T-01: done\""}}')"
expect_guard "(bash-parse-done) grep の引数に done のタスク票パスがあるだけ → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"grep -n \"vault/tasks/P-FIX/T-01.md\" README.md > /tmp/x.txt"}}')"
expect_guard "(bash-parse-done) cat で done の verdict を読んで別ファイルへ出力 → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cat vault/verdicts/P-FIX/T-01.json > /tmp/v.json"}}')"
expect_guard "(bash-parse-done) log 追記に done の verdict へのリダイレクトが && 連結 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"printf x >> vault/log/P-FIX.md && echo y > vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(bash-parse-done) git add の後に git rm で done の verdict を削除 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git add x && git rm vault/verdicts/P-FIX/T-01.json"}}')" "done"
expect_guard "(guard-text heredoc) H3 commit メッセージのヒアドキュメント本文に done の verdict パス → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nP-FIX/T-01 vault/verdicts/P-FIX/T-01.json\nEOF\n)\""}}')"
expect_guard "(bash-parse-done) git restore で done のタスク票を戻す → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"git restore vault/tasks/P-FIX/T-01.md"}}')" "done"
expect_guard "(bash-parse-done) cp で done のタスク票を上書きして git add → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cp /tmp/y vault/tasks/P-FIX/T-01.md\ngit add vault/tasks/P-FIX/T-01.md"}}')" "done"
expect_guard "(bash-parse-done) tee で done の verdict へ書き込み → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"tee vault/verdicts/P-FIX/T-01.json < /tmp/y"}}')" "done"

# 会話記録（~/.claude/projects/）への書き込み拒否（D-010 フェーズ4）。実ホームを触らないよう HOME を差し替える
TG_HOME="$TMP/transcript-guard-home"
mkdir -p "$TG_HOME/.claude/projects/x"
run_guard_home() { printf '%s' "$1" | HOME="$TG_HOME" CLAUDE_PROJECT_DIR="$TMP" python3 "$GUARD_HOOK"; }
expect_tg() { # $1=name $2=deny|allow $3=payload json
  local out; out="$(run_guard_home "$3")"
  expect_guard "(transcript-guard) $1" "$2" "$out"
  if [ "$2" = deny ] && ! echo "$out" | grep -q '~/.claude/projects/'; then
    echo "  NG   (transcript-guard) $1 reason に ~/.claude/projects/ が無い"; FAIL_N=$((FAIL_N+1))
  fi
}
for at in "" creator verifier planner; do
  ap=""; [ -n "$at" ] && ap='"agent_type":"'"$at"'",'
  for tl in Write Edit MultiEdit; do
    expect_tg "agent_type='$at' の $tl → 拒否" deny \
      '{'"$ap"'"tool_name":"'"$tl"'","tool_input":{"file_path":"'"$TG_HOME"'/.claude/projects/x/s.jsonl"}}'
  done
done
expect_tg "Bash リダイレクト > （~ 表記）→ 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"echo x > ~/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash リダイレクト >> （絶対パス）→ 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"echo x >> '"$TG_HOME"'/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash tee → 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"echo x | tee ~/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash sed -i → 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ ~/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash rm → 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"rm '"$TG_HOME"'/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash mv → 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"mv /tmp/a ~/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash cp → 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"cp /tmp/a ~/.claude/projects/x/s.jsonl"}}'
expect_tg "verifier の Bash リダイレクト（~ 表記）→ 拒否" deny '{"agent_type":"verifier","tool_name":"Bash","tool_input":{"command":"echo x > ~/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash cat（読み取り）→ 許可" allow '{"tool_name":"Bash","tool_input":{"command":"cat ~/.claude/projects/x/s.jsonl"}}'
expect_tg "Bash grep（読み取り）→ 許可" allow '{"tool_name":"Bash","tool_input":{"command":"grep foo '"$TG_HOME"'/.claude/projects/x/s.jsonl"}}'
expect_tg "Read → 許可" allow '{"tool_name":"Read","tool_input":{"file_path":"'"$TG_HOME"'/.claude/projects/x/s.jsonl"}}'
expect_tg "~/.claude/settings.json への Write → 許可" allow '{"tool_name":"Write","tool_input":{"file_path":"'"$TG_HOME"'/.claude/settings.json"}}'
expect_tg "~/.claude/projects-x/ への Write → 許可（前方一致の誤検出なし）" allow '{"tool_name":"Write","tool_input":{"file_path":"'"$TG_HOME"'/.claude/projects-x/a"}}'
expect_tg "Bash で ~/.claude/settings.json へリダイレクト → 許可" allow '{"tool_name":"Bash","tool_input":{"command":"echo x > ~/.claude/settings.json"}}'

# Bash の vault/rules/・会話記録判定の精密化（issue #91）。analyze_bash_writes で解析できる形は実際の
# 書き込み対象だけで判定し、解析できない形は従来の判定に落とす（fail-closed）。
bp() { # $1=name $2=deny|allow $3=payload json $4=reason に含むべき部分文字列(optional)
  expect_guard "(bash-parse) $1" "$2" "$(run_guard_home "$3")" "${4:-}"
}
bp "grep の検索語・対象に git commit を含む会話記録の読み取り → 許可" allow '{"tool_name":"Bash","tool_input":{"command":"grep -n \"git commit\" ~/.claude/projects/x/s.jsonl"}}'
bp "grep -c mkdir で会話記録の読み取り → 許可" allow '{"tool_name":"Bash","tool_input":{"command":"grep -c mkdir ~/.claude/projects/x/s.jsonl"}}'
bp "grep の検索語に doing->review を含む会話記録の読み取り → 許可" allow '{"tool_name":"Bash","tool_input":{"command":"grep -n \"doing->review\" ~/.claude/projects/x/s.jsonl"}}'
bp "printf の引用符内に vault/rules/ へのリダイレクト文字列 → 許可" allow '{"tool_name":"Bash","tool_input":{"command":"printf '"'"'%s'"'"' \"echo x > vault/rules/a.md\""}}'
bp "ヒアドキュメント本文に vault/rules/ と git commit の文字列 → 許可" allow '{"tool_name":"Bash","tool_input":{"command":"cat > /tmp/P-20261002-write-guard-false-positive-note.md <<'"'"'EOF'"'"'\nsee vault/rules/common/git.md and git commit\nEOF"}}'
bp "vault/rules/ へのリダイレクト → 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"echo \"x\" > vault/rules/a.md"}}' "vault/rules/"
bp "vault/rules/ へのリダイレクト（ヒアドキュメント付き）→ 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"cat > vault/rules/a.md <<'"'"'EOF'"'"'\nbody\nEOF"}}' "vault/rules/"
bp "区切りの後ろの会話記録へのリダイレクト → 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"echo x; echo y > ~/.claude/projects/x/s.jsonl"}}' "~/.claude/projects/"
bp "改行区切りの後ろの rm（会話記録）→ 拒否" deny '{"tool_name":"Bash","tool_input":{"command":"echo a\nrm ~/.claude/projects/x/s.jsonl"}}' "~/.claude/projects/"
bp "コマンド置換の中の vault/rules/ へのリダイレクト → 拒否（従来判定）" deny '{"tool_name":"Bash","tool_input":{"command":"echo \"$(echo x > vault/rules/a.md)\""}}' "vault/rules/"
bp "cd 後の相対リダイレクト（vault/rules/common 配下）→ 拒否（従来判定）" deny '{"tool_name":"Bash","tool_input":{"command":"cd vault/rules/common && echo x > a.md"}}' "vault/rules/"
bp "変数を含む vault/rules/ の対象 → 拒否（従来判定）" deny '{"tool_name":"Bash","tool_input":{"command":"echo x > vault/rules/$NAME"}}' "vault/rules/"
bp "bash -c の中の vault/rules/ へのリダイレクト → 拒否（従来判定）" deny '{"tool_name":"Bash","tool_input":{"command":"bash -c \"echo x > vault/rules/a.md\""}}' "vault/rules/"
bp "展開されるヒアドキュメント本文のコマンド置換 → 拒否（従来判定）" deny '{"tool_name":"Bash","tool_input":{"command":"cat <<EOF > /tmp/x\n$(echo x > vault/rules/a.md)\nEOF"}}' "vault/rules/"
bp "awk の print リダイレクトで vault/rules/ へ書き込み → 拒否（従来判定）" deny '{"tool_name":"Bash","tool_input":{"command":"awk '"'"'{print > \"vault/rules/a.md\"}'"'"' README.md"}}' "vault/rules/"
bp "絶対パスのコマンド語 /bin/rm で会話記録を削除 → 拒否（basename 照合）" deny '{"tool_name":"Bash","tool_input":{"command":"/bin/rm ~/.claude/projects/x/s.jsonl"}}' "~/.claude/projects/"

# issue #109: 本文・引数に vault/rules/ のパス文字列があるだけの誤検知の回帰ケース（P-20261003-guard-rules-path-text）
expect_guard "(guard-text heredoc) H1 main の gh issue create 本文に vault/rules/ と > → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title t --body \"$(cat <<'"'"'EOF'"'"'\n## 該当箇所\n- vault/rules/planner/planner.md の確認コマンド（... > /tmp/x.md）\nEOF\n)\""}}')"
expect_guard "(guard-text heredoc) H2 planner の gh issue create 本文に vault/rules/ と > → 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"gh issue create --title t --body \"$(cat <<'"'"'EOF'"'"'\n## 該当箇所\n- vault/rules/planner/planner.md の確認コマンド（... > /tmp/x.md）\nEOF\n)\""}}')"
expect_guard "(guard-text heredoc) H4 区切り語を引用符で囲まない本文に vault/rules/ と > → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title t --body \"$(cat <<EOF\nsee vault/rules/common/git.md > x\nEOF\n)\""}}')"
expect_guard "(guard-text heredoc) H5 本文の後ろの vault/rules/ へのリダイレクト → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"echo \"$(cat <<'"'"'EOF'"'"'\nx\nEOF\n)\" > vault/rules/a.md"}}')" "vault/rules/"
expect_guard "(guard-text heredoc) H6 展開される本文のコマンド置換で vault/rules/ へ書く → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"echo \"$(cat <<EOF\n$(echo x > vault/rules/a.md)\nEOF\n)\""}}')" "vault/rules/"
expect_guard "(guard-text heredoc) H7 区切り語の後ろの別コマンドで vault/rules/ へ書く → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"echo \"$(cat <<'"'"'EOF'"'"'\nx\nEOF\ncp y vault/rules/a.md\n)\""}}')" "vault/rules/"
expect_guard "(guard-text cd) C1 planner の cd と読み取りだけ（issue の再現例）→ 許可" allow \
  "$(run_guard '{"agent_type":"planner","tool_name":"Bash","tool_input":{"command":"cd '"$TMP"'; ls scripts/ scripts/*/ 2>/dev/null | head -30; grep -c x vault/rules/planner/planner.md; wc -l vault/rules/planner/planner.md"}}')"
expect_guard "(guard-text cd) C2 ルートへの cd の後に vault/rules/ を読んで別ファイルへ出力 → 許可" allow \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cd '"$TMP"' && grep -n x vault/rules/common/git.md > /tmp/out.txt"}}')"
expect_guard "(guard-text cd) C3 ルートへの cd の後に vault/rules/ へリダイレクト → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cd '"$TMP"' && echo x > vault/rules/a.md"}}')" "vault/rules/"
expect_guard "(guard-text cd) C4 ルートへの cd の後に cp で vault/rules/ へ書く → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cd '"$TMP"'; cp x.txt vault/rules/common/a.md"}}')" "vault/rules/"
expect_guard "(guard-text cd) C5 ルートへの cd の後に tee で vault/rules/ へ書く → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cd '"$TMP"' && printf x | tee vault/rules/a.md"}}')" "vault/rules/"
expect_guard "(guard-text cd) C6 ルート以外への cd の後に vault/rules/ へリダイレクト → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && echo x > vault/rules/a.md"}}')" "vault/rules/"
expect_guard "(guard-text cd) C7 2つ目の cd で vault/rules/common に入って書く → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cd '"$TMP"'; cd vault/rules/common && echo x > a.md"}}')" "vault/rules/"
expect_guard "(guard-text cd) C8 ルートへの cd の後に gh api で vault/rules/ を更新 → 拒否" deny \
  "$(run_guard '{"tool_name":"Bash","tool_input":{"command":"cd '"$TMP"'; gh api -X PUT repos/o/r/contents/vault/rules/common/roles.md -f content=Zm9v"}}')" "vault/rules/"

# creator の vault/plans/・vault/log/ 拒否の Bash 判定も analyze_bash_writes に載せ替え（issue #91 / T-02）
bpc() { # $1=name $2=deny|allow $3=command(JSON 文字列の中身)
  local sub=""; [ "$2" = deny ] && sub="creator は vault/plans/"
  expect_guard "(bash-parse-creator) $1" "$2" "$(run_guard '{"agent_type":"creator","tool_name":"Bash","tool_input":{"command":"'"$3"'"}}')" "$sub"
}
bpc "grep の検索語に git add を含む計画票の読み取り → 許可" allow 'grep -n \"git add\" vault/plans/P-X.md'
bpc "git log -p の出力を別の場所へリダイレクト → 許可" allow 'git log -p -- vault/log/P-X.md > /tmp/out.txt'
bpc "ヒアドキュメント本文に vault/plans/ と git commit の文字列 → 許可" allow "cat > /tmp/note.md <<'EOF'\nvault/plans/P-X.md ni git commit\nEOF"
bpc "grep の検索語に doing->review を含むログの読み取り → 許可" allow 'grep -n \"doing->review\" vault/log/P-X.md'
bpc "grep -c の計画票読み取りの結果を別の場所へリダイレクト → 許可" allow 'grep -c x vault/plans/P-X.md > /tmp/c.txt'
bpc "ログへの >> リダイレクト → 拒否" deny 'echo x >> vault/log/P-X.md'
bpc "計画票への tee -a → 拒否" deny 'printf x | tee -a vault/plans/P-X.md'
bpc "計画票への sed -i → 拒否" deny 'sed -i s/a/b/ vault/plans/P-X.md'
bpc "ログへの cp → 拒否" deny 'cp /tmp/a vault/log/P-X.md'
bpc "計画票の git add → 拒否" deny 'git add vault/plans/P-X.md'
bpc "コマンド置換の中のログへのリダイレクト → 拒否（従来判定）" deny 'echo \"$(echo x >> vault/log/P-X.md)\"'
bpc "改行区切りの後ろのログの rm → 拒否" deny 'echo a\nrm vault/log/P-X.md'

# 計画票の承認（draft→approved）の会話記録による裏付け（D-010 フェーズ4 / T-03）。
# make_transcript は T-04 でも流用する。パスは $TMP 配下（実行ごとに一意。引数の各行を JSONL として書く）
AP_TRANSCRIPT="$TMP/approve-transcript.jsonl"
AP_NONEXIST="$TMP/approve-nonexistent.jsonl"
make_transcript() { printf '%s\n' "$@" > "$AP_TRANSCRIPT"; }
T_CMD='{"type":"user","message":{"role":"user","content":"<command-name>/plan</command-name>\n<command-args>approve P-TEST</command-args>"}}'
T_CMD_SP='{"type":"user","message":{"role":"user","content":"<command-name>/plan</command-name>\n<command-args>  approve P-TEST  </command-args>"}}'
T_SENT='{"type":"user","message":{"role":"user","content":"/plan approve P-TEST"}}'
T_OTHER_ID='{"type":"user","message":{"role":"user","content":"/plan approve P-OTHER"}}'
T_PREFIX_ID='{"type":"user","message":{"role":"user","content":"/plan approve P-TEST2"}}'
T_CHAT='{"type":"user","message":{"role":"user","content":"こんにちは"}}'
T_TOOLRES='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"/plan approve P-TEST"}]}}'
T_META='{"type":"user","isMeta":true,"message":{"role":"user","content":"/plan approve P-TEST"}}'
expect_ap() { # $1=name $2=deny|allow $3=payload json（deny の時は reason に /plan approve を含むことも確認）
  local out; out="$(run_guard "$3")"
  if [ "$2" = deny ]; then expect_guard "(approve-pre) $1" deny "$out" "/plan approve"
  else expect_guard "(approve-pre) $1" allow "$out"; fi
}
AP_EDIT='"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"status: draft","new_string":"status: approved"}'
AP_MULTI='"tool_name":"MultiEdit","tool_input":{"file_path":"vault/plans/P-TEST.md","edits":[{"old_string":"# ゴール","new_string":"# ゴール2"},{"old_string":"status: draft","new_string":"status: approved"}]}'
AP_WRITE='"tool_name":"Write","tool_input":{"file_path":"vault/plans/P-TEST.md","content":"---\nid: P-TEST\nstatus: approved\n---\n# ゴール\n"}'
TP='"transcript_path":"'"$AP_TRANSCRIPT"'"'
make_plan "P-TEST" "draft" "| T-01 | todo | 0 | - | A | |"
for form in "$T_CMD" "$T_CMD_SP" "$T_SENT"; do
  make_transcript "$T_CHAT" "$form"
  for tool in "$AP_EDIT" "$AP_MULTI" "$AP_WRITE"; do
    expect_ap "コマンドあり・メイン・${tool%%,*} → 許可" allow "{$TP,$tool}"
  done
done
make_transcript "$T_CHAT" "$T_CMD"
expect_ap "コマンドあり・agent_type=planner → 拒否" deny "{$TP,\"agent_type\":\"planner\",$AP_EDIT}"
expect_ap "コマンドあり・agent_type=creator → 拒否" deny "{$TP,\"agent_type\":\"creator\",$AP_WRITE}"
make_transcript "$T_CHAT"
expect_ap "コマンド無し（無関係な発言のみ）→ 拒否" deny "{$TP,$AP_EDIT}"
expect_ap "コマンド無し・Write → 拒否" deny "{$TP,$AP_WRITE}"
expect_ap "コマンド無し・MultiEdit → 拒否" deny "{$TP,$AP_MULTI}"
make_transcript "$T_CHAT" "$T_OTHER_ID"
expect_ap "別の計画 ID（approve P-OTHER）だけ → 拒否" deny "{$TP,$AP_EDIT}"
make_transcript "$T_CHAT" "$T_PREFIX_ID"
expect_ap "前方一致の計画 ID（approve P-TEST2）だけ → 拒否" deny "{$TP,$AP_EDIT}"
make_transcript "$T_CHAT" "$T_TOOLRES"
expect_ap "tool_result（content が配列）にしかコマンドが無い → 拒否" deny "{$TP,$AP_EDIT}"
make_transcript "$T_CHAT" "$T_META"
expect_ap "isMeta の行にしかコマンドが無い → 拒否" deny "{$TP,$AP_EDIT}"
# 会話記録が読めない時は許可
make_transcript "$T_TOOLRES" "$T_META"
expect_ap "人の発言が1件も無い → 許可（読めない扱い）" allow "{$TP,$AP_EDIT}"
make_transcript "not json" "{broken"
expect_ap "どの行も JSON でない → 許可（読めない扱い）" allow "{$TP,$AP_EDIT}"
expect_ap "transcript_path が無い → 許可" allow "{$AP_EDIT}"
expect_ap "transcript_path のファイルが無い → 許可" allow '{"transcript_path":"'"$AP_NONEXIST"'",'"$AP_EDIT"'}'
expect_ap "読めない時でも agent_type=planner は拒否" deny "{\"agent_type\":\"planner\",$AP_EDIT}"
# 承認に当たらない書き込みは会話記録と無関係に許可
make_transcript "$T_CHAT"
make_plan "P-TEST" "draft" "| T-01 | todo | 0 | - | A | |"
expect_ap "draft→draft の Edit → 許可" allow '{'"$TP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"# ゴール","new_string":"# ゴール2"}}'
expect_ap "draft→draft の Write → 許可" allow '{'"$TP"',"tool_name":"Write","tool_input":{"file_path":"vault/plans/P-TEST.md","content":"---\nstatus: draft\n---\n本文に status: approved\n"}}'
expect_ap "本文中の status: approved は無視（Edit）→ 許可" allow '{'"$TP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"# ゴール","new_string":"status: approved"}}'
expect_ap "old_string が見つからない Edit → 許可（Claude Code 側が失敗させる）" allow '{'"$TP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"存在しない","new_string":"status: approved"}}'
make_plan "P-TEST" "approved" "| T-01 | todo | 0 | - | A | |"
expect_ap "approved→approved の Edit → 許可" allow '{'"$TP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"| todo |","new_string":"| doing |"}}'
make_plan "P-TEST" "done" "| T-01 | done | 1 | - | A | |"
expect_ap "done→done の Edit → 許可" allow '{'"$TP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"# ゴール","new_string":"# ゴール2"}}'
expect_ap "他ファイル（README.md）への approved 内容の Write → 許可" allow '{'"$TP"',"tool_name":"Write","tool_input":{"file_path":"README.md","content":"---\nstatus: approved\n---\n"}}'
expect_ap "新規の計画票（ファイル無し）を approved で Write・コマンド無し → 拒否" deny '{'"$TP"',"tool_name":"Write","tool_input":{"file_path":"vault/plans/P-NEW.md","content":"---\nstatus: approved\n---\n"}}'
rm -f "$AP_TRANSCRIPT"

# blocked の解除（blocked→他）の会話記録による裏付け（D-010 フェーズ5 / T-01）
UB_TRANSCRIPT="$TMP/unblock-transcript.jsonl"
UB_NONEXIST="$TMP/unblock-nonexistent.jsonl"
make_ub_transcript() { printf '%s\n' "$@" > "$UB_TRANSCRIPT"; }
U_CMD='{"type":"user","message":{"role":"user","content":"<command-name>/plan</command-name>\n<command-args>unblock P-TEST T-02 方針は A で\n2行目の回答</command-args>"}}'
U_CMD_SP='{"type":"user","message":{"role":"user","content":"<command-name>/plan</command-name>\n<command-args>  unblock P-TEST T-02  </command-args>"}}'
U_SENT='{"type":"user","message":{"role":"user","content":"/plan unblock P-TEST T-02 方針は A で\n2行目"}}'
U_OTHER_PLAN='{"type":"user","message":{"role":"user","content":"/plan unblock P-OTHER T-02"}}'
U_OTHER_TASK='{"type":"user","message":{"role":"user","content":"/plan unblock P-TEST T-03"}}'
U_PREFIX='{"type":"user","message":{"role":"user","content":"/plan unblock P-TEST T-020"}}'
U_TOOLRES='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"/plan unblock P-TEST T-02"}]}}'
U_META='{"type":"user","isMeta":true,"message":{"role":"user","content":"/plan unblock P-TEST T-02"}}'
expect_ub() { # $1=name $2=deny|allow $3=payload json（deny の時は reason に /plan unblock を含むことも確認）
  local out; out="$(run_guard "$3")"
  if [ "$2" = deny ]; then expect_guard "(unblock-pre) $1" deny "$out" "/plan unblock"
  else expect_guard "(unblock-pre) $1" allow "$out"; fi
}
UTP='"transcript_path":"'"$UB_TRANSCRIPT"'"'
ub_edit() { echo '"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"| '"$1"' | '"$2"' |","new_string":"| '"$1"' | '"$3"' |"}'; }
ub_multi() { echo '"tool_name":"MultiEdit","tool_input":{"file_path":"vault/plans/P-TEST.md","edits":[{"old_string":"# ゴール","new_string":"# ゴール2"},{"old_string":"| '"$1"' | '"$2"' |","new_string":"| '"$1"' | '"$3"' |"}]}'; }
ub_write() { # $1=T-01 の status $2=T-02 の status
  echo '"tool_name":"Write","tool_input":{"file_path":"vault/plans/P-TEST.md","content":"---\nid: P-TEST\nstatus: approved\n---\n# ゴール\n\n## タスク表（状態の正本）\n| id | status | attempt | after | title | question |\n|----|----|----|----|----|----|\n| T-01 | '"$1"' | 1 | - | A | q1 |\n| T-02 | '"$2"' | 1 | - | B | q2 |\n"}'
}
make_plan "P-TEST" "approved" "| T-01 | blocked | 1 | - | A | q1 |" "| T-02 | blocked | 1 | - | B | q2 |"
for form in "$U_CMD" "$U_CMD_SP" "$U_SENT"; do
  make_ub_transcript "$T_CHAT" "$form"
  expect_ub "T-02 blocked→todo・Edit・メイン → 許可" allow "{$UTP,$(ub_edit T-02 blocked todo)}"
  expect_ub "T-02 blocked→todo・MultiEdit・メイン → 許可" allow "{$UTP,$(ub_multi T-02 blocked todo)}"
  expect_ub "T-02 blocked→todo・Write・メイン → 許可" allow "{$UTP,$(ub_write blocked todo)}"
  expect_ub "T-01 blocked→todo・Edit（コマンドは T-02 のみ）→ 拒否" deny "{$UTP,$(ub_edit T-01 blocked todo)}"
  expect_ub "T-01 blocked→todo・Write → 拒否" deny "{$UTP,$(ub_write todo blocked)}"
  expect_ub "T-01・T-02 を同時に解除（T-01 に裏付け無し）→ 拒否" deny "{$UTP,$(ub_write todo todo)}"
done
make_ub_transcript "$T_CHAT" "$U_CMD"
expect_ub "T-02 blocked→doing・Edit → 許可（遷移先は問わない）" allow "{$UTP,$(ub_edit T-02 blocked doing)}"
expect_ub "コマンドあり・agent_type=creator → 拒否" deny "{$UTP,\"agent_type\":\"creator\",$(ub_edit T-02 blocked todo)}"
expect_ub "コマンドあり・agent_type=planner → 拒否" deny "{$UTP,\"agent_type\":\"planner\",$(ub_write blocked todo)}"
make_ub_transcript "$T_CHAT"
expect_ub "コマンド無し（無関係な発言のみ）blocked→todo → 拒否" deny "{$UTP,$(ub_edit T-02 blocked todo)}"
expect_ub "コマンド無し blocked→doing → 拒否" deny "{$UTP,$(ub_edit T-02 blocked doing)}"
make_ub_transcript "$T_CHAT" "$U_OTHER_PLAN"
expect_ub "別の計画 ID だけ → 拒否" deny "{$UTP,$(ub_edit T-02 blocked todo)}"
make_ub_transcript "$T_CHAT" "$U_OTHER_TASK"
expect_ub "別のタスク ID だけ → 拒否" deny "{$UTP,$(ub_edit T-02 blocked todo)}"
make_ub_transcript "$T_CHAT" "$U_PREFIX"
expect_ub "前方一致（T-020）だけ → 拒否" deny "{$UTP,$(ub_edit T-02 blocked todo)}"
make_ub_transcript "$T_CHAT" "$U_TOOLRES"
expect_ub "tool_result にしかコマンドが無い → 拒否" deny "{$UTP,$(ub_edit T-02 blocked todo)}"
make_ub_transcript "$T_CHAT" "$U_META"
expect_ub "isMeta の行にしかコマンドが無い → 拒否" deny "{$UTP,$(ub_edit T-02 blocked todo)}"
# 会話記録が読めない時は許可（agent_type が空の時のみ）
make_ub_transcript "$U_TOOLRES" "$U_META"
expect_ub "人の発言が1件も無い → 許可（読めない扱い）" allow "{$UTP,$(ub_edit T-02 blocked todo)}"
make_ub_transcript "not json" "{broken"
expect_ub "どの行も JSON でない → 許可（読めない扱い）" allow "{$UTP,$(ub_edit T-02 blocked todo)}"
expect_ub "transcript_path が無い → 許可" allow "{$(ub_edit T-02 blocked todo)}"
expect_ub "読めない時でも agent_type=planner は拒否" deny "{\"agent_type\":\"planner\",$(ub_edit T-02 blocked todo)}"
# 解除に当たらない書き込みは会話記録と無関係に許可
make_ub_transcript "$T_CHAT"
expect_ub "blocked→blocked（question の書き換え）→ 許可" allow '{'"$UTP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"| q2 |","new_string":"| q2 改 |"}}'
expect_ub "blocked 行を含まない新規 Write → 許可" allow '{'"$UTP"',"tool_name":"Write","tool_input":{"file_path":"vault/plans/P-NEW.md","content":"---\nstatus: draft\n---\n## タスク表\n| id | status | attempt | after | title | question |\n|--|--|--|--|--|--|\n| T-01 | todo | 0 | - | A | |\n"}}'
expect_ub "T-01 の行が消えるだけ（今回は検査しない）→ 許可" allow '{'"$UTP"',"tool_name":"Edit","tool_input":{"file_path":"vault/plans/P-TEST.md","old_string":"| T-01 | blocked | 1 | - | A | q1 |\n","new_string":""}}'
make_plan "P-TEST" "approved" "| T-01 | todo | 0 | - | A | |" "| T-02 | doing | 1 | - | B | |" "| T-03 | review | 1 | - | C | |"
expect_ub "todo→doing・コマンド無し → 許可" allow "{$UTP,$(ub_edit T-01 todo doing)}"
expect_ub "doing→review → 許可" allow "{$UTP,$(ub_edit T-02 doing review)}"
expect_ub "review→done → 許可" allow "{$UTP,$(ub_edit T-03 review done)}"
expect_ub "review→doing → 許可" allow "{$UTP,$(ub_edit T-03 review doing)}"
expect_ub "review→blocked → 許可" allow "{$UTP,$(ub_edit T-03 review blocked)}"
expect_ub "doing→blocked → 許可" allow "{$UTP,$(ub_edit T-02 doing blocked)}"
rm -f "$UB_TRANSCRIPT"

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"

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
expect "正常な計画票（doing 1件・blocked に question あり）→ 許可" allow "$(run_plan_guard)"
make_plan "P-TEST" "approved"
expect "データ行が無い → 許可" allow "$(run_plan_guard)"
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
expect "(f) approved な計画票が0件 → 許可" allow "$(run_plan_guard)"
make_plan "P-A" "approved" "| T-0001 | todo | 0 | - | A | |"
make_plan "P-B" "approved" "| T-0001 | todo | 0 | - | B | |"
expect "(f) approved な計画票が2件以上 → ブロック" block "$(run_plan_guard)" "approved"
rm -rf "$TMP/vault/plans"
EMPTY_DIR="$(mktemp -d)"
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
ap_reset; ap_commit_plan draft; ap_plan approved
make_transcript "$T_CHAT"
out="$(run_ap_post "$AP_TRANSCRIPT")"
expect "(approve-post) 裏付け無し → ブロック（計画 ID を含む）" block "$out" "P-TEST"
expect "(approve-post) 裏付け無し → reason に git restore を含む" block "$out" "git restore vault/plans/P-TEST.md"
for form in "$T_CMD" "$T_CMD_SP" "$T_SENT"; do
  make_transcript "$T_CHAT" "$form"
  expect "(approve-post) 人の /plan approve P-TEST あり → 許可" allow "$(run_ap_post "$AP_TRANSCRIPT")"
done
make_transcript "$T_CHAT" "$T_TOOLRES"
expect "(approve-post) tool_result にしか無い → ブロック" block "$(run_ap_post "$AP_TRANSCRIPT")" "P-TEST"
make_transcript "$T_CHAT" "$T_META"
expect "(approve-post) isMeta にしか無い → ブロック" block "$(run_ap_post "$AP_TRANSCRIPT")" "P-TEST"
make_transcript "$T_CHAT" "$T_OTHER_ID"
expect "(approve-post) 別の計画 ID だけ → ブロック" block "$(run_ap_post "$AP_TRANSCRIPT")" "P-TEST"
make_transcript "$T_CHAT" "$T_PREFIX_ID"
expect "(approve-post) 前方一致の計画 ID だけ → ブロック" block "$(run_ap_post "$AP_TRANSCRIPT")" "P-TEST"
# 会話記録が読めない時は警告（ブロックしない）
ap_warn() { # $1=name $2=transcript_path
  local o; o="$(run_ap_post "$2")"
  expect "(approve-post) $1 → 警告（ブロックしない）" allow "$o" "会話記録が読めないため承認の裏付けを検査できませんでした"
  if echo "$o" | grep -q '"additionalContext"' && echo "$o" | grep -q '"hookEventName": *"PostToolUse"' && echo "$o" | grep -q 'P-TEST'; then
    echo "  ok   (approve-post) $1 → hookSpecificOutput.additionalContext に計画 ID"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   (approve-post) $1 → additionalContext の形式"; FAIL_N=$((FAIL_N+1))
  fi
}
make_transcript "$T_TOOLRES" "$T_META"; ap_warn "人の発言が1件も無い" "$AP_TRANSCRIPT"
make_transcript "not json" "{broken"; ap_warn "どの行も JSON でない" "$AP_TRANSCRIPT"
ap_warn "transcript_path が無い" ""
ap_warn "transcript_path のファイルが無い" "$AP_NONEXIST"
# 承認済み・draft・HEAD 無し・未追跡・非 git
make_transcript "$T_CHAT"
ap_commit_plan approved
expect "(approve-post) HEAD で既に approved → 検査しない（許可）" allow "$(run_ap_post "$AP_TRANSCRIPT")"
if [ -z "$(run_ap_post "$AP_TRANSCRIPT")" ]; then echo "  ok   (approve-post) HEAD で既に approved → 出力なし"; PASS_N=$((PASS_N+1)); else echo "  NG   (approve-post) HEAD で既に approved → 出力あり"; FAIL_N=$((FAIL_N+1)); fi
ap_reset; ap_commit_plan draft
expect "(approve-post) draft のまま → 許可" allow "$(run_ap_post "$AP_TRANSCRIPT")"
ap_reset; ap_plan approved
expect "(approve-post) HEAD が無い（未コミット）・裏付け無し → ブロック" block "$(run_ap_post "$AP_TRANSCRIPT")" "P-TEST"
ap_reset; echo x > "$AP_REPO/other.txt"; ap_git add other.txt; ap_git commit -q -m other; ap_plan approved
expect "(approve-post) 未追跡の計画票・裏付け無し → ブロック" block "$(run_ap_post "$AP_TRANSCRIPT")" "P-TEST"
make_transcript "$T_CHAT" "$T_CMD"
expect "(approve-post) 未追跡の計画票・裏付けあり → 許可" allow "$(run_ap_post "$AP_TRANSCRIPT")"
make_transcript "$T_CHAT"
NONGIT="$(mktemp -d)"; mkdir -p "$NONGIT/vault/plans"; cp "$AP_REPO/vault/plans/P-TEST.md" "$NONGIT/vault/plans/"
expect "(approve-post) 非 git ディレクトリ → 何もしない（許可）" allow "$(printf '{"tool_name":"Bash","transcript_path":"%s"}' "$AP_TRANSCRIPT" | CLAUDE_PROJECT_DIR="$NONGIT" python3 "$PLAN_GUARD_HOOK")"
rm -rf "$NONGIT"
# block が出る時は警告を重ねない（JSON は1つだけ）：タスク表の列数不正 + 会話記録が読めない
ap_reset; ap_commit_plan draft; ap_plan approved
sed -i.bak 's/| T-01 | todo | 0 | - | A | |/| T-01 | todo | 0 | - | A |/' "$AP_REPO/vault/plans/P-TEST.md"; rm -f "$AP_REPO/vault/plans/P-TEST.md.bak"
make_transcript "not json"
cnt="$(run_ap_post "$AP_TRANSCRIPT" | grep -c '^{')"
if [ "$cnt" = 1 ]; then echo "  ok   (approve-post) 警告と block が競合する時は JSON 1つ"; PASS_N=$((PASS_N+1)); else echo "  NG   (approve-post) JSON が $cnt 個"; FAIL_N=$((FAIL_N+1)); fi
expect "(approve-post) 警告と block が競合する時は block を優先" block "$(run_ap_post "$AP_TRANSCRIPT")" "列数"
rm -f "$AP_TRANSCRIPT"

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
make_ub_transcript "$T_CHAT"
out="$(run_up_post "$UB_TRANSCRIPT")"
expect "(unblock-post) 裏付け無し → ブロック（計画 ID・タスク ID を含む）" block "$out" "P-TEST/T-02"
expect "(unblock-post) 裏付け無し → reason に git restore を含む" block "$out" "git restore vault/plans/P-TEST.md"
for form in "$U_CMD" "$U_CMD_SP" "$U_SENT"; do
  make_ub_transcript "$T_CHAT" "$form"
  expect "(unblock-post) 人の /plan unblock P-TEST T-02 あり → 許可" allow "$(run_up_post "$UB_TRANSCRIPT")"
done
make_ub_transcript "$T_CHAT" "$U_TOOLRES"
expect "(unblock-post) tool_result にしか無い → ブロック" block "$(run_up_post "$UB_TRANSCRIPT")" "P-TEST/T-02"
make_ub_transcript "$T_CHAT" "$U_META"
expect "(unblock-post) isMeta にしか無い → ブロック" block "$(run_up_post "$UB_TRANSCRIPT")" "P-TEST/T-02"
make_ub_transcript "$T_CHAT" "$U_OTHER_PLAN"
expect "(unblock-post) 別の計画 ID だけ → ブロック" block "$(run_up_post "$UB_TRANSCRIPT")" "P-TEST/T-02"
make_ub_transcript "$T_CHAT" "$U_OTHER_TASK"
expect "(unblock-post) 別のタスク ID だけ → ブロック" block "$(run_up_post "$UB_TRANSCRIPT")" "P-TEST/T-02"
make_ub_transcript "$T_CHAT" "$U_PREFIX"
expect "(unblock-post) 前方一致のタスク ID だけ → ブロック" block "$(run_up_post "$UB_TRANSCRIPT")" "P-TEST/T-02"
up_warn() { # $1=name $2=transcript_path
  local o; o="$(run_up_post "$2")"
  expect "(unblock-post) $1 → 警告（ブロックしない）" allow "$o" "解除の裏付けを検査できませんでした"
  if echo "$o" | grep -q '"additionalContext"' && echo "$o" | grep -q '"hookEventName": *"PostToolUse"' && echo "$o" | grep -q 'P-TEST/T-02'; then
    echo "  ok   (unblock-post) $1 → hookSpecificOutput.additionalContext に計画 ID・タスク ID"; PASS_N=$((PASS_N+1))
  else
    echo "  NG   (unblock-post) $1 → additionalContext の形式"; FAIL_N=$((FAIL_N+1))
  fi
}
make_ub_transcript "$U_TOOLRES" "$U_META"; up_warn "人の発言が1件も無い" "$UB_TRANSCRIPT"
make_ub_transcript "not json" "{broken"; up_warn "どの行も JSON でない" "$UB_TRANSCRIPT"
up_warn "transcript_path が無い" ""
up_warn "transcript_path のファイルが無い" "$UB_NONEXIST"
# 対象外：blocked のまま・HEAD でも blocked でない・HEAD 無し・未追跡・行が無い・非 git
make_ub_transcript "$T_CHAT"
up_reset; up_commit todo blocked; up_plan doing blocked
expect "(unblock-post) blocked→blocked（他の行だけ変更）→ 許可" allow "$(run_up_post "$UB_TRANSCRIPT")"
if [ -z "$(run_up_post "$UB_TRANSCRIPT")" ]; then echo "  ok   (unblock-post) blocked→blocked → 出力なし"; PASS_N=$((PASS_N+1)); else echo "  NG   (unblock-post) blocked→blocked → 出力あり"; FAIL_N=$((FAIL_N+1)); fi
up_reset; up_commit todo todo; up_plan doing doing
expect "(unblock-post) HEAD でも blocked でない（todo→doing）→ 許可" allow "$(run_up_post "$UB_TRANSCRIPT")"
if [ -z "$(run_up_post "$UB_TRANSCRIPT")" ]; then echo "  ok   (unblock-post) todo→doing → 出力なし"; PASS_N=$((PASS_N+1)); else echo "  NG   (unblock-post) todo→doing → 出力あり"; FAIL_N=$((FAIL_N+1)); fi
up_reset; UP_STATUS=draft up_plan todo todo
expect "(unblock-post) HEAD が無い（未コミット）→ 許可" allow "$(run_up_post "$UB_TRANSCRIPT")"
up_reset; echo x > "$UP_REPO/other.txt"; up_git add other.txt; up_git commit -q -m other; UP_STATUS=draft up_plan todo todo
expect "(unblock-post) 未追跡の計画票 → 許可" allow "$(run_up_post "$UB_TRANSCRIPT")"
if [ -z "$(run_up_post "$UB_TRANSCRIPT")" ]; then echo "  ok   (unblock-post) 未追跡の計画票 → 出力なし"; PASS_N=$((PASS_N+1)); else echo "  NG   (unblock-post) 未追跡の計画票 → 出力あり"; FAIL_N=$((FAIL_N+1)); fi
up_reset; up_commit todo blocked; up_plan todo todo
sed -i.bak '/^| T-02 /d' "$UP_REPO/vault/plans/P-TEST.md"; rm -f "$UP_REPO/vault/plans/P-TEST.md.bak"
expect "(unblock-post) 作業ツリーに同じ id の行が無い → 許可" allow "$(run_up_post "$UB_TRANSCRIPT")"
up_reset; up_commit todo blocked; up_plan todo todo
NONGIT="$(mktemp -d)"; mkdir -p "$NONGIT/vault/plans"; cp "$UP_REPO/vault/plans/P-TEST.md" "$NONGIT/vault/plans/"
expect "(unblock-post) 非 git ディレクトリ → 何もしない（許可）" allow "$(printf '{"tool_name":"Bash","transcript_path":"%s"}' "$UB_TRANSCRIPT" | CLAUDE_PROJECT_DIR="$NONGIT" python3 "$PLAN_GUARD_HOOK")"
rm -rf "$NONGIT"
# コミット後は HEAD の版が blocked でなくなり対象外
up_git add vault/plans/P-TEST.md; up_git commit -q -m unblock
expect "(unblock-post) 解除をコミットした後 → 許可" allow "$(run_up_post "$UB_TRANSCRIPT")"
# 複数行の解除：最初の裏付けの無い行でブロック
up_reset; printf -- '---\nid: P-TEST\nstatus: approved\n---\n\n## タスク表（状態の正本）\n| id | status | attempt | after | title | question |\n|---|---|---|---|---|---|\n| T-02 | blocked | 1 | - | B | q |\n| T-03 | blocked | 1 | - | C | q |\n' > "$UP_REPO/vault/plans/P-TEST.md"
up_git add vault/plans/P-TEST.md; up_git commit -q -m plan
sed -i.bak 's/blocked/todo/; s/| q |/| |/' "$UP_REPO/vault/plans/P-TEST.md"; rm -f "$UP_REPO/vault/plans/P-TEST.md.bak"
make_ub_transcript "$T_CHAT" "$U_CMD"
expect "(unblock-post) 複数行の解除・T-02 だけ裏付けあり → T-03 でブロック" block "$(run_up_post "$UB_TRANSCRIPT")" "P-TEST/T-03"
# block が出る時は警告を重ねない（JSON は1つだけ）：列数不正 + 会話記録が読めない
up_reset; up_commit todo blocked; up_plan todo todo
sed -i.bak 's/| T-01 | todo | 0 | - | A | |/| T-01 | todo | 0 | - | A |/' "$UP_REPO/vault/plans/P-TEST.md"; rm -f "$UP_REPO/vault/plans/P-TEST.md.bak"
make_ub_transcript "not json"
cnt="$(run_up_post "$UB_TRANSCRIPT" | grep -c '^{')"
if [ "$cnt" = 1 ]; then echo "  ok   (unblock-post) 警告と block が競合する時は JSON 1つ"; PASS_N=$((PASS_N+1)); else echo "  NG   (unblock-post) JSON が $cnt 個"; FAIL_N=$((FAIL_N+1)); fi
expect "(unblock-post) 警告と block が競合する時は block を優先" block "$(run_up_post "$UB_TRANSCRIPT")" "列数"
rm -f "$UB_TRANSCRIPT"

# worktree 委譲（issue #56 / D-008 フェーズ2）。agent_write_guard.py の (delegate) テストと同じ型：
# 一時 worktree に判定結果が変わる差し替えスクリプトを置き、cwd をその worktree に向けたペイロードを
# メインリポジトリ側の plan_guard.py に渡す。
DWPMAIN="$(mktemp -d)"
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
DWPLEAF="$(mktemp -d)"; rmdir "$DWPLEAF"
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

DWPMAIN2="$(mktemp -d)"
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
DWPLEAF2="$(mktemp -d)"; rmdir "$DWPLEAF2"
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
ITMP="$(mktemp -d)"
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
NTMP="$(mktemp -d)"
bash "$ROOT/scripts/install.sh" "$NTMP" >/dev/null 2>&1
NMAN="$NTMP/.claude/harness-manifest.json"
expect_eq "(h) マニフェストが作られる" "1" "$([ -f "$NMAN" ] && echo 1 || echo 0)"
expect_eq "(h) files が1件以上" "True" \
  "$(python3 -c "import json;print(len(json.load(open('$NMAN'))['files']) >= 1)")"
expect_eq "(h) 代表2パスのハッシュが64桁16進" "True" \
  "$(python3 -c "import json,re;d=json.load(open('$NMAN'))['files'];print(bool(re.fullmatch('[0-9a-f]{64}',d['.claude/hooks/stop_gate.py'])) and bool(re.fullmatch('[0-9a-f]{64}',d['docs/vault-spec.md'])))")"
expect_eq "(h) 利用者の資産は含まれない" "False" \
  "$(python3 -c "import json;d=json.load(open('$NMAN'))['files'];print(any(k.startswith(('vault/plans/','vault/tasks/','vault/verdicts/','vault/log/','vault/archive/','vault/designs/')) for k in d))")"
printf -- '- 独自ルール\n' >> "$NTMP/vault/rules/common/roles.md"
bash "$ROOT/scripts/install.sh" "$NTMP" >/dev/null 2>&1
expect_eq "(i) 記録は src のハッシュで dst とは一致しない" "True" \
  "$(python3 -c "
import hashlib, json
h = lambda p: hashlib.sha256(open(p,'rb').read()).hexdigest()
rel = 'vault/rules/common/roles.md'
m = json.load(open('$NMAN'))['files'][rel]
print(m == h('$ROOT/' + rel) and m != h('$NTMP/' + rel))")"
expect_eq "(i) 編集した行はそのまま残る" "1" "$(grep -c '^- 独自ルール$' "$NTMP/vault/rules/common/roles.md")"
rm -rf "$NTMP"

echo "== 参照される scripts の存在チェック =="
RSTMP="$(mktemp -d)"
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
DWMAIN="$(mktemp -d)"
git -C "$DWMAIN" init -q -b main
git -C "$DWMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
dw_run() { ( cd "$DWMAIN" && bash "$ROOT/scripts/discard_worktree.sh" "$1" "$2" ) >/dev/null 2>&1; } # $1=path $2=branch

D_A="$(mktemp -d)"; rmdir "$D_A"
git -C "$DWMAIN" worktree add -q -b worktree-agent-test "$D_A"
dw_run "$D_A" worktree-agent-test; rc_a=$?
list_a="$(cd "$DWMAIN" && git worktree list --porcelain)"
verify_rc=0
(cd "$DWMAIN" && git rev-parse --verify worktree-agent-test) >/dev/null 2>&1; verify_rc=$?
result_a="False"
if [ "$rc_a" -eq 0 ] && ! printf '%s' "$list_a" | grep -q "$D_A" && [ "$verify_rc" -ne 0 ]; then result_a="True"; fi
expect_eq "(a) discard_worktree.sh 正常系: worktree/ブランチとも削除されrc0（git worktree list から消え rev-parse --verify worktree-agent-test が失敗）" "True" "$result_a"

D_B="$(mktemp -d)"; rmdir "$D_B"
git -C "$DWMAIN" worktree add -q -b other-branch "$D_B"
dw_run "$D_B" other-branch; rc_b=$?
list_b="$(cd "$DWMAIN" && git worktree list --porcelain)"
result_b="False"
if [ "$rc_b" -ne 0 ] && printf '%s' "$list_b" | grep -q "$D_B" && [ -d "$D_B" ]; then result_b="True"; fi
expect_eq "(b) discard_worktree.sh 拒否系: ブランチ名がworktree-agent-で始まらない場合は削除されずworktreeが残存" "True" "$result_b"
git -C "$DWMAIN" worktree remove --force "$D_B" >/dev/null 2>&1
git -C "$DWMAIN" branch -D other-branch >/dev/null 2>&1

D_C="$(mktemp -d)"; rmdir "$D_C"
dw_run "$D_C" worktree-agent-x; rc_c=$?
list_c="$(cd "$DWMAIN" && git worktree list --porcelain)"
result_c="False"
if [ "$rc_c" -ne 0 ] && ! printf '%s' "$list_c" | grep -q "$D_C" && [ ! -d "$D_C" ]; then result_c="True"; fi
expect_eq "(c) discard_worktree.sh 拒否系: 未登録パスは削除されず何も変更されない" "True" "$result_c"

D_D="$(mktemp -d)"; rmdir "$D_D"
git -C "$DWMAIN" worktree add -q -b worktree-agent-real "$D_D"
dw_run "$D_D" worktree-agent-fake; rc_d=$?
list_d="$(cd "$DWMAIN" && git worktree list --porcelain)"
result_d="False"
if [ "$rc_d" -ne 0 ] && printf '%s' "$list_d" | grep -q "$D_D" && [ -d "$D_D" ]; then result_d="True"; fi
expect_eq "(d) discard_worktree.sh 拒否系: パスのブランチが指定と不一致の場合は削除されずworktreeが残存" "True" "$result_d"
git -C "$DWMAIN" worktree remove --force "$D_D" >/dev/null 2>&1
git -C "$DWMAIN" branch -D worktree-agent-real >/dev/null 2>&1

rm -rf "$DWMAIN" "$D_A" "$D_B" "$D_C" "$D_D"

D_E_TARGET="$(mktemp -d)"
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
UTMP="$(mktemp -d)"
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
printf -- '- 独自ルール2\n' >> "$UTMP/vault/rules/common/roles.md"
uout="$(bash "$ROOT/scripts/install.sh" --update "$UTMP" 2>&1)"
expect_eq "(k) 編集済みは skip (edited) で報告される" "1" \
  "$(echo "$uout" | grep -c '^skip (edited) vault/rules/common/roles\.md$')"
expect_eq "(k) 編集した行は残る" "1" "$(grep -c '^- 独自ルール2$' "$UTMP/vault/rules/common/roles.md")"
rm -f "$UTMP/.claude/harness-manifest.json"
ubefore="$(shasum "$UTMP/.claude/hooks/stop_gate.py" | cut -d' ' -f1)"
uout="$(bash "$ROOT/scripts/install.sh" --update "$UTMP" 2>&1)"
expect_eq "(l) マニフェスト無し → 既存は update されない" "0" "$(echo "$uout" | grep -c '^update ')"
expect_eq "(l) マニフェスト無し → 既存ファイルは上書きされない" "$ubefore" \
  "$(shasum "$UTMP/.claude/hooks/stop_gate.py" | cut -d' ' -f1)"
rm -rf "$UTMP"

echo "== merge_settings_json.py =="
SMERGE="$ROOT/scripts/merge_settings_json.py"
STMP="$(mktemp -d)"
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

for ent in 'Bash(gh pr merge*)' 'Bash(glab mr merge*)' 'Bash(claude *)'; do
  expect_eq "(approve-settings) deny に $ent がある" "true" \
    "$(jq --arg e "$ent" '.permissions.deny | index($e) != null' "$ROOT/.claude/settings.json")"
done

echo "== install.sh の settings.json 扱い =="
WTMP="$(mktemp -d)"
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
UNTMP="$(mktemp -d)"
bash "$ROOT/scripts/install.sh" "$UNTMP" >/dev/null 2>&1
printf -- '- 独自ルール3\n' >> "$UNTMP/vault/rules/common/roles.md"
mkdir -p "$UNTMP/vault/plans"
echo "dummy" > "$UNTMP/vault/plans/P-DUMMY.md"
uout="$(bash "$ROOT/scripts/uninstall.sh" "$UNTMP" 2>&1)"; urc=$?
expect_eq "(q) uninstall.sh の終了コードが0" "0" "$urc"
expect_eq "(q) 未編集ファイル(stop_gate.py)は削除される" "0" "$([ -f "$UNTMP/.claude/hooks/stop_gate.py" ] && echo 1 || echo 0)"
expect_eq "(q) 編集済みファイル(roles.md)は残る" "1" "$([ -f "$UNTMP/vault/rules/common/roles.md" ] && echo 1 || echo 0)"
expect_eq "(q) 編集した行は保持される" "1" "$(grep -c '^- 独自ルール3$' "$UNTMP/vault/rules/common/roles.md")"
expect_eq "(q) skip (edited) が報告される" "1" "$(echo "$uout" | grep -c '^skip (edited) vault/rules/common/roles\.md$')"
expect_eq "(r) vault/plans のダミーファイルは無傷" "1" "$([ -f "$UNTMP/vault/plans/P-DUMMY.md" ] && echo 1 || echo 0)"
expect_eq "(r) ダミーファイルの内容は変わらない" "dummy" "$(cat "$UNTMP/vault/plans/P-DUMMY.md")"
expect_eq "(s) CLAUDE.md はブロックのみの内容だったため削除される（unmerge_claude_md.py）" "0" "$([ -f "$UNTMP/CLAUDE.md" ] && echo 1 || echo 0)"
expect_eq "(s) unmerge_claude_md.py の remove/delete 報告がある" "1" "$(echo "$uout" | grep -Ec '^(remove|delete) .*CLAUDE\.md$')"
expect_eq "(t) settings.json からハーネス由来の hooks が除去される（unmerge_settings_json.py）" "False" \
  "$(python3 -c "import json;d=json.load(open('$UNTMP/.claude/settings.json'));print(any('plan_guard.py' in h.get('command','') for e in d.get('hooks',{}).get('PostToolUse',[]) for h in e.get('hooks',[])))")"
expect_eq "(t) unmerge_settings_json.py の unmerge 報告がある" "1" "$(echo "$uout" | grep -c '^unmerge .*settings\.json$')"
expect_eq "(u) マニフェストファイル自体も削除される" "0" "$([ -f "$UNTMP/.claude/harness-manifest.json" ] && echo 1 || echo 0)"
rm -rf "$UNTMP"

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
rm -f "$RU_PID" "$RU_ERR"

echo "== model_stats.py =="
MS_PY="$ROOT/scripts/model_stats.py"
MS_DIR="$(mktemp -d)"
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
ms_want="$(printf 'model\ttasks\tfirst_pass_rate\tavg_attempt\tblocked_rate\nhaiku\t4\t0.00\t1.50\t0.75\nsonnet\t1\t1.00\t1.00\t0.00\nunknown\t1\t1.00\t1.00\t0.00')"
ms_got="$(python3 "$MS_PY" "$MS_DIR/P-MS.md")"
expect_eq "(ms-1) フィクスチャ log の集計出力（見出し行・モデル別の行）が期待値と一致" "$ms_want" "$ms_got"
expect_eq "(ms-1) 見出し行がタブ区切りの5列" "5" "$(echo "$ms_got" | head -1 | awk -F'\t' '{print NF}')"
expect_eq "(ms-5) doing→blocked creator= で終わるタスクも creator のモデルに集計される（haiku 4件・blocked 率 0.75）" "$(printf 'haiku\t4\t0.00\t1.50\t0.75')" "$(echo "$ms_got" | grep '^haiku')"
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

echo "== vcs_finish.sh =="
VF_BIN="$TMP/vf_bin"; VF_REC="$TMP/vf_rec.txt"; VF_REPO="$TMP/vf_repo"
mkdir -p "$VF_BIN" "$VF_REPO"
for vf_cmd in gh glab; do
  printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "%%s\\n" "$a"; done > "%s"\nexit 0\n' "$VF_REC" > "$VF_BIN/$vf_cmd"
  chmod +x "$VF_BIN/$vf_cmd"
done
(
  cd "$VF_REPO" && git init -q -b vfmain . \
    && git -c user.name=smoke -c user.email=smoke@example.com commit -q --allow-empty -m init \
    && git config branch.vfmain.remote . && git config branch.vfmain.merge refs/heads/vfmain
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
expect_vf "(vcs_finish) github・引数なし → gh pr create --fill" github $'pr\ncreate\n--fill'
expect_vf "(vcs_finish) github・引数あり → そのまま（--fill なし）" github $'pr\ncreate\n--title\nT\n--body\nB' --title T --body B
expect_vf "(vcs_finish) gitlab・引数なし → glab mr create --fill --yes" gitlab $'mr\ncreate\n--fill\n--yes'
expect_vf "(vcs_finish) gitlab・引数あり → そのまま（--fill なし）" gitlab $'mr\ncreate\n--title\nT\n--body\nB' --title T --body B

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
HLB="$(mktemp -d)"
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

WTBASE="$(mktemp -d)"
WTMAIN="$WTBASE/main"; LEAF="$WTBASE/leaf"
mkdir -p "$WTMAIN"
git -C "$WTMAIN" init -q -b main
git -C "$WTMAIN" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$WTMAIN" worktree add -q "$LEAF" -b wt-leaf
mkdir -p "$LEAF/vault/plans"
expect_eq "(stop_gate worktree) 前提: worktree の .git がファイルである" "yes" "$([ -f "$LEAF/.git" ] && echo yes || echo no)"
echo dirty > "$LEAF/x.txt"
expect "(stop_gate worktree) 未コミットのファイルがある → ブロック" block \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$LEAF" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")" "未コミットの変更があります"
rm -f "$LEAF/x.txt"
expect "(stop_gate worktree) ファイルを消す → 許可" allow \
  "$(printf '%s' "$DEFAULT_STDIN" | CLAUDE_PROJECT_DIR="$LEAF" HARNESS_MAX_ATTEMPTS=3 python3 "$STOP_HOOK")"
git -C "$WTMAIN" worktree remove -q --force "$LEAF"
rm -rf "$WTBASE"

HPC="$(mktemp -d)"
mkdir -p "$HPC/.claude/hooks"
cp "$ROOT"/.claude/hooks/*.py "$HPC/.claude/hooks/"
rm -rf "$HPC/.claude/hooks/__pycache__"
printf '%s' '{}' | env -u PYTHONDONTWRITEBYTECODE CLAUDE_PROJECT_DIR="$HPC" python3 "$HPC/.claude/hooks/agent_write_guard.py" >/dev/null 2>&1
printf '%s' '{}' | env -u PYTHONDONTWRITEBYTECODE CLAUDE_PROJECT_DIR="$HPC" python3 "$HPC/.claude/hooks/plan_guard.py" >/dev/null 2>&1
printf '%s' '{"stop_hook_active":true}' | env -u PYTHONDONTWRITEBYTECODE CLAUDE_PROJECT_DIR="$HPC" python3 "$HPC/.claude/hooks/stop_gate.py" >/dev/null 2>&1
expect_eq "(hooklib-pycache) 3フック実行後に .claude/hooks/__pycache__ が無い" "no" "$([ -e "$HPC/.claude/hooks/__pycache__" ] && echo yes || echo no)"
rm -rf "$HLB" "$HPC"

echo
echo "smoke: pass=$PASS_N fail=$FAIL_N"
[ "$FAIL_N" -eq 0 ]
