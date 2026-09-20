#!/usr/bin/env bash
# フックの動作検証。疑似 stdin を渡して stop_gate.py / agent_write_guard.py の判定を確かめる。
# 使い方: bash scripts/smoke.sh   （install 先でも同じ。.claude/hooks/ が同階層にあればよい）
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOP_HOOK="$ROOT/.claude/hooks/stop_gate.py"
PLAN_GUARD_HOOK="$ROOT/.claude/hooks/plan_guard.py"
GUARD_HOOK="$ROOT/.claude/hooks/agent_write_guard.py"
RULES_SH="$ROOT/scripts/rules.sh"
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

make_plan_task T-0001 doing 1
expect_guard "(a) doing 中にメインエージェントが vault/rules/ へ Write → 拒否" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_plan_task T-0001 todo 0
expect_guard "(b) doing/review 無し・メインエージェントが vault/rules/ へ Write → 許可" allow \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_plan_task T-0001 doing 1
expect_guard "(c) doing 中に verifier が vault/verdicts/ へ Write → 許可（従来どおり）" allow \
  "$(run_guard '{"agent_type":"verifier","tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/verdicts/T-0001.json"}}')"
RULES_WRITE_JSON='{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/roles.md"}}'
expect_guard "(d) HARNESS_ALLOW_RULES_WRITE が doing の ID と一致 → 許可" allow \
  "$(printf '%s' "$RULES_WRITE_JSON" | CLAUDE_PROJECT_DIR="$TMP" HARNESS_ALLOW_RULES_WRITE=T-0001 python3 "$GUARD_HOOK")"
expect_guard "(e) HARNESS_ALLOW_RULES_WRITE が doing の ID と不一致 → 拒否" deny \
  "$(printf '%s' "$RULES_WRITE_JSON" | CLAUDE_PROJECT_DIR="$TMP" HARNESS_ALLOW_RULES_WRITE=T-9999 python3 "$GUARD_HOOK")"
expect_guard "(f) HARNESS_ALLOW_RULES_WRITE=1（ID でない値）→ 拒否" deny \
  "$(printf '%s' "$RULES_WRITE_JSON" | CLAUDE_PROJECT_DIR="$TMP" HARNESS_ALLOW_RULES_WRITE=1 python3 "$GUARD_HOOK")"
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
expect_guard "(g) approved な計画票が0件・vault/rules/ へ Write → 許可" allow \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
make_plan "P-A" "approved" "| T-0001 | todo | 0 | - | A | |"
make_plan "P-B" "approved" "| T-0001 | doing | 1 | - | B | |"
expect_guard "(h) approved な計画票が2件以上・どちらかに doing あり・vault/rules/ へ Write → 拒否" deny \
  "$(run_guard '{"tool_name":"Write","tool_input":{"file_path":"'"$TMP"'/vault/rules/common/a.md"}}')"
rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"

GTMP="$(mktemp -d)"
git -C "$GTMP" init -q -b main
git -C "$GTMP" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
expect_guard "(i) main で git commit → 拒否" deny \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
git -C "$GTMP" checkout -q -b work/p-test
expect_guard "(j) work ブランチで git commit → 許可" allow \
  "$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$GTMP" python3 "$GUARD_HOOK")"
rm -rf "$GTMP"

echo "== plan_guard.py =="
run_plan_guard() { printf '{"hook_event_name":"PostToolUse","tool_name":"Edit"}' | CLAUDE_PROJECT_DIR="$TMP" python3 "$PLAN_GUARD_HOOK"; }

rm -rf "$TMP/vault/plans"; mkdir -p "$TMP/vault/plans"
make_plan "P-TEST" "approved" "| T-0001 | doing | 1 | - | A | |" "| T-0002 | doing | 1 | - | B | |"
expect "(a) doing が2件 → ブロック" block "$(run_plan_guard)" "doing"
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
rm -rf "$STMP"

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
rm -rf "$WTMP"

echo
echo "smoke: pass=$PASS_N fail=$FAIL_N"
[ "$FAIL_N" -eq 0 ]
