#!/usr/bin/env bash
# フックの動作検証。疑似 stdin を渡して stop_gate.py / agent_write_guard.py の判定を確かめる。
# 使い方: bash scripts/smoke.sh   （install 先でも同じ。.claude/hooks/ が同階層にあればよい）
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOP_HOOK="$ROOT/.claude/hooks/stop_gate.py"
TODO_HOOK="$ROOT/.claude/hooks/todo_guard.py"
GUARD_HOOK="$ROOT/.claude/hooks/agent_write_guard.py"
RULES_SH="$ROOT/scripts/rules.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS_N=0; FAIL_N=0

make_todo() { # $1=id $2=status $3=attempt
  mkdir -p "$TMP/vault/verdicts"
  cat > "$TMP/vault/todo.md" <<EOT
# キュー

## タスク
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| $1 | $2 | $3 | - | テスト | |

## 計画
| id | status | title |
|---|---|---|
EOT
}
make_verdict() { # $1=id $2=attempt $3=result
  printf '{"task":"%s","attempt":%s,"result":"%s","checked_at":"2026-01-01 00:00","criteria":[],"reasons":["r1"]}\n' "$1" "$2" "$3" > "$TMP/vault/verdicts/$1.json"
}
DEFAULT_STDIN='{"hook_event_name":"Stop","stop_hook_active":false}'
make_task() { # $1=id $2=受け入れ基準の箇条書き行数
  mkdir -p "$TMP/vault/tasks"
  {
    echo "# $1 テスト"
    echo
    echo "## 受け入れ基準"
    for i in $(seq 1 "$2"); do echo "- 基準$i"; done
    echo
    echo "## 決定済み"
  } > "$TMP/vault/tasks/$1.md"
}
write_verdict() { # $1=id $2=json 文字列（形式検証のテスト用）
  printf '%s' "$2" > "$TMP/vault/verdicts/$1.json"
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
make_todo T-0001 doing 1;                        expect "doing あり・verdict なし → ブロック" block "$(run_stop)" "verifier"
make_todo T-0001 review 1; make_verdict T-0001 1 FAIL; expect "FAIL・attempt=1 → ブロック（doing に戻す）" block "$(run_stop)" "doing に戻し"
make_todo T-0001 doing 3;  make_verdict T-0001 3 FAIL; expect "FAIL・attempt=3・doing → ブロック（blocked にする）" block "$(run_stop)" "blocked"
make_todo T-0001 blocked 3; make_verdict T-0001 3 FAIL; expect "FAIL・attempt=3・blocked → 許可" allow "$(run_stop)"
make_todo T-0001 review 1; make_verdict T-0001 1 PASS; expect "PASS・review → ブロック（done にする）" block "$(run_stop)" "done"
make_todo T-0001 done 1;   make_verdict T-0001 1 PASS; expect "PASS・done → 許可" allow "$(run_stop)"
make_todo T-0001 todo 0;   rm -f "$TMP/vault/verdicts/T-0001.json"; expect "doing/review なし → 許可" allow "$(run_stop)"
make_todo T-0001 review 2; make_verdict T-0001 1 PASS; expect "PASS だが attempt 不一致（古い verdict）→ ブロック（verifier）" block "$(run_stop)" "古い"
make_todo T-0001 review 1; rm -f "$TMP/vault/verdicts/T-0001.json"; expect "stop_hook_active=true → 許可（既定）" allow "$(run_stop '{"hook_event_name":"Stop","stop_hook_active":true}')"
make_todo T-0001 review 1; expect "stop_hook_active=true + HARNESS_STRICT_STOP=1 → ブロック" block "$(printf '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$TMP" HARNESS_STRICT_STOP=1 python3 "$STOP_HOOK")" "verifier"
make_todo T-0001 review 2; make_verdict T-0001 2 FAIL; expect "HARNESS_MAX_ATTEMPTS=2 で attempt=2 FAIL → blocked 指示" block "$(HARNESS_MAX_ATTEMPTS=2 run_stop)" "blocked"

OK_C='{"text":"基準","ok":true,"note":"実行コマンド: x / 出力: y"}'
make_todo T-0001 review 1; write_verdict T-0001 '{"task":"T-0001","attempt":1,"result":"FOO","checked_at":"","criteria":['"$OK_C"'],"reasons":[]}'
expect "(a) result が PASS/FAIL 以外 → ブロック（不正）" block "$(run_stop)" "不正"
make_todo T-0001 review 1; write_verdict T-0001 '{"task":"T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":[{"text":"基準","ok":true}],"reasons":[]}'
expect "(b) criteria の要素に note が無い → ブロック（不正）" block "$(run_stop)" "不正"
make_todo T-0001 review 1; make_task T-0001 3; write_verdict T-0001 '{"task":"T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":['"$OK_C"','"$OK_C"'],"reasons":[]}'
expect "(c) criteria 2件 vs タスク票の基準 3行 → ブロック（不正）" block "$(run_stop)" "一致しません"
rm -f "$TMP/vault/tasks/T-0001.md"
make_todo T-0001 review 1; write_verdict T-0001 '{"task":"T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":[{"text":"基準","ok":true,"note":"  "}],"reasons":[]}'
expect "(d) note が空白のみ → ブロック（不正）" block "$(run_stop)" "不正"
make_todo T-0001 review 1; write_verdict T-0001 '{"task":"T-0001","attempt":1,"result":"PASS","checked_at":"","criteria":['"$OK_C"'],"reasons":"none"}'
expect "(e) reasons が配列でない → ブロック（不正）" block "$(run_stop)" "不正"
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

make_todo T-0001 doing 1
expect_guard "(a) doing 中にメインエージェントが vault/rules/ へ Write → 拒否" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_todo T-0001 todo 0
expect_guard "(b) doing/review 無し・メインエージェントが vault/rules/ へ Write → 許可" allow \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_todo T-0001 doing 1
expect_guard "(c) doing 中に verifier が vault/verdicts/ へ Write → 許可（従来どおり）" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/verdicts/T-0001.json"}}')"
RULES_WRITE_JSON='{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/roles.md"}}'
expect_guard "(d) HARNESS_ALLOW_RULES_WRITE が doing の ID と一致 → 許可" allow \
  "$(printf '%s' "$RULES_WRITE_JSON" | CLAUDE_PROJECT_DIR="$TMP" HARNESS_ALLOW_RULES_WRITE=T-0001 python3 "$GUARD_HOOK")"
expect_guard "(e) HARNESS_ALLOW_RULES_WRITE が doing の ID と不一致 → 拒否" deny \
  "$(printf '%s' "$RULES_WRITE_JSON" | CLAUDE_PROJECT_DIR="$TMP" HARNESS_ALLOW_RULES_WRITE=T-9999 python3 "$GUARD_HOOK")"
expect_guard "(f) HARNESS_ALLOW_RULES_WRITE=1（ID でない値）→ 拒否" deny \
  "$(printf '%s' "$RULES_WRITE_JSON" | CLAUDE_PROJECT_DIR="$TMP" HARNESS_ALLOW_RULES_WRITE=1 python3 "$GUARD_HOOK")"

echo "== todo_guard.py =="
make_todo_rows() { # 各引数が「## タスク」表のデータ行1行
  {
    echo "# キュー"
    echo
    echo "## タスク"
    echo "| id | status | attempt | after | title | question |"
    echo "|---|---|---|---|---|---|"
    for r in "$@"; do echo "$r"; done
    echo
    echo "## 計画"
    echo "| id | status | title |"
    echo "|---|---|---|"
  } > "$TMP/vault/todo.md"
}
run_todo_guard() { printf '{"hook_event_name":"PostToolUse","tool_name":"Edit"}' | CLAUDE_PROJECT_DIR="$TMP" python3 "$TODO_HOOK"; }

make_todo_rows "| T-0001 | doing | 1 | - | A | |" "| T-0002 | doing | 1 | - | B | |"
expect "(a) doing が2件 → ブロック" block "$(run_todo_guard)" "doing"
make_todo_rows "| T-0001 | blocked | 1 | - | A | |"
expect "(b) blocked なのに question が空 → ブロック" block "$(run_todo_guard)" "question"
make_todo_rows "| T-0001 | pending | 0 | - | A | |"
expect "(c) status が5値以外 → ブロック" block "$(run_todo_guard)" "status"
make_todo_rows "| T-0001 | todo | 0 | - | A | |" "| T-0001 | done | 1 | - | B | |"
expect "(d) id が重複 → ブロック" block "$(run_todo_guard)" "重複"
make_todo_rows "| T-0001 | todo | 0 | - | A |"
expect "(e) データ行の列数が6でない → ブロック" block "$(run_todo_guard)" "列数"
make_todo_rows "| T-0001 | done | 1 | - | A | |" "| T-0002 | doing | 2 | T-0001 | B | |" "| T-0003 | blocked | 1 | - | C | 方針を決めてほしい |"
expect "正常な todo.md（doing 1件・blocked に question あり）→ 許可" allow "$(run_todo_guard)"
make_todo_rows
expect "データ行が無い → 許可" allow "$(run_todo_guard)"
EMPTY_DIR="$(mktemp -d)"
expect "todo.md が無い → 許可" allow "$(printf '{}' | CLAUDE_PROJECT_DIR="$EMPTY_DIR" python3 "$TODO_HOOK")"
rm -rf "$EMPTY_DIR"

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

echo
echo "smoke: pass=$PASS_N fail=$FAIL_N"
[ "$FAIL_N" -eq 0 ]
