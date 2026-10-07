#!/usr/bin/env bash
# P-20261007-diff-gate（T-01）の確認用。planner が置いたフィクスチャで、成果物ではない。
# 一時 git リポジトリを作り、main（base）からブランチ work/b を切って preset の変更をコミットし、
# その中で scripts/diff_gate.py を1回実行する。あわせて diff_gate.check を import して呼ぶ。
# 出力: exit（diff_gate.py の終了コード）/ changed（`git diff --name-only --no-renames main work/b`。参考）/
#       check（check() が返した違反のパスを空白区切り。例外の時は check_error=<例外のクラス名>）/
#       unchanged（実行の前後で HEAD と git status --porcelain が変わらなければ yes）/
#       porcelain（実行後の git status --porcelain）/ stdout・stderr の各節
#
# 使い方: bash vault/tasks/P-20261007-diff-gate/fixtures/try.sh <preset> [diff_gate.py への引数...]
#   引数を省くと `P-TEST T-01 main work/b` で呼ぶ。check() は引数がちょうど4つの時だけ呼ぶ。
#   preset（どれも main の内容は同じ。work/b での変更だけが違う）:
#     ok          宣言どおり：scripts/foo.py 変更・docs/dir/sub/b.md 追加・.claude/hooks/x.py 変更・
#                 .claude/settings.json 変更・.claude/agents/new.md 追加・T-01.md の「進捗」に1行追記
#     empty       work/b にコミットが無い（main と同じ）
#     extra       ok に加えて extra.txt 追加・docs/readme.md 変更（どちらも宣言外）
#     criteria    T-01.md の「受け入れ基準」の1行を書き換える
#     head        T-01.md の1行目（最初の見出しより前の `# T-01 ...`）を書き換える
#     forbidden   vault/plans/P-TEST.md・vault/log/P-TEST.md・vault/rules/common/x.md 変更、
#                 vault/verdicts/P-TEST/T-01.json 追加（4つとも T-01 の「成果物」に宣言がある）
#     selfdecl    T-01.md の「成果物」に `extra.txt` を書き足し、extra.txt を追加する
#     hookundecl  .claude/hooks/y.py 変更（T-01 では宣言外）
#     hooks       .claude/hooks/x.py・.claude/settings.json・.claude/agents/creator.md・scripts/foo.py 変更
#                 （T-02 の「成果物」は `scripts/foo.py` だけ。`try.sh hooks P-TEST T-02 main work/b` で使う）
#     othertask   vault/tasks/P-TEST/T-02.md の「進捗」に1行追記（T-01 では宣言外）
#     rename      git mv scripts/foo.py scripts/bar.py
#     uncommitted ok をコミットしたうえで、extra.txt 追加と docs/readme.md 変更を未コミットで残す
#     newtask     work/b で vault/tasks/P-TEST/T-03.md を追加する（base には無い）
#
# T-01.md の「成果物」の宣言（main の版）:
#   `scripts/foo.py` `docs/dir/` `.claude/hooks/x.py` `.claude/settings.json` `.claude/agents/`
#   `vault/plans/P-TEST.md` `vault/log/P-TEST.md` `vault/rules/common/x.md` `vault/verdicts/P-TEST/`
#   `check_func`（パスでない文字列）
#   「入力」節には `docs/readme.md`・`extra.txt` があるが、成果物ではない
set -u
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
PRESET="${1:-ok}"
[ $# -gt 0 ] && shift
if [ $# -gt 0 ]; then ARGS=("$@"); else ARGS=(P-TEST T-01 main work/b); fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
R="$WORK/repo"
mkdir -p "$R/vault/tasks/P-TEST" "$R/vault/plans" "$R/vault/log" "$R/vault/verdicts/P-TEST" \
  "$R/vault/rules/common" "$R/scripts" "$R/docs/dir" "$R/.claude/hooks" "$R/.claude/agents"

{
  echo "# T-01 確認用のタスク"
  echo
  echo "## 目的"
  echo "確認用"
  echo
  echo "## 入力"
  echo "- \`docs/readme.md\`"
  echo "- \`extra.txt\`"
  echo
  echo "## 成果物"
  echo "- \`scripts/foo.py\`（1ファイル）"
  echo "- \`docs/dir/\`（ディレクトリ）"
  echo "- \`.claude/hooks/x.py\`・\`.claude/settings.json\`・\`.claude/agents/\`"
  echo "- \`vault/plans/P-TEST.md\`・\`vault/log/P-TEST.md\`・\`vault/rules/common/x.md\`・\`vault/verdicts/P-TEST/\`"
  echo "- \`check_func\` 関数"
  echo
  echo "## 受け入れ基準"
  echo "- 基準1"
  echo "- 基準2"
  echo "- 基準3"
  echo
  echo "## 決定済み"
  echo "- なし"
  echo
  echo "## 進捗"
} > "$R/vault/tasks/P-TEST/T-01.md"
{
  echo "# T-02 確認用のタスク2"
  echo
  echo "## 目的"
  echo "確認用"
  echo
  echo "## 入力"
  echo "- なし"
  echo
  echo "## 成果物"
  echo "- \`scripts/foo.py\`（1ファイル）"
  echo
  echo "## 受け入れ基準"
  echo "- 基準1"
  echo "- 基準2"
  echo "- 基準3"
  echo
  echo "## 決定済み"
  echo "- なし"
  echo
  echo "## 進捗"
} > "$R/vault/tasks/P-TEST/T-02.md"
printf -- '---\nid: P-TEST\nstatus: approved\n---\n# ゴール\n確認用\n' > "$R/vault/plans/P-TEST.md"
echo "- 2026-01-01 00:00 - draft→approved" > "$R/vault/log/P-TEST.md"
echo "rule" > "$R/vault/rules/common/x.md"
echo "print(1)" > "$R/scripts/foo.py"
echo "a" > "$R/docs/dir/a.md"
echo "readme" > "$R/docs/readme.md"
echo "x = 1" > "$R/.claude/hooks/x.py"
echo "y = 1" > "$R/.claude/hooks/y.py"
echo "{}" > "$R/.claude/settings.json"
printf -- '---\nname: creator\n---\n' > "$R/.claude/agents/creator.md"

git -C "$R" init -q -b main
git -C "$R" config user.name fixture
git -C "$R" config user.email fixture@example.com
git -C "$R" add -A
git -C "$R" commit -q -m base
git -C "$R" checkout -q -b work/b

T1="$R/vault/tasks/P-TEST/T-01.md"
apply_ok() {
  echo "print(2)" > "$R/scripts/foo.py"
  mkdir -p "$R/docs/dir/sub"
  echo "b" > "$R/docs/dir/sub/b.md"
  echo "x = 2" > "$R/.claude/hooks/x.py"
  echo '{"a": 1}' > "$R/.claude/settings.json"
  printf -- '---\nname: new\n---\n' > "$R/.claude/agents/new.md"
  echo "- 進捗の追記" >> "$T1"
}
replace_line() { # $1=file $2=old line $3=new line
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert old + "\n" in s, old
open(p, "w", encoding="utf-8").write(s.replace(old + "\n", new + "\n", 1))
PY
}

case "$PRESET" in
  ok) apply_ok ;;
  empty) : ;;
  extra) apply_ok; echo "extra" > "$R/extra.txt"; echo "readme2" > "$R/docs/readme.md" ;;
  criteria) replace_line "$T1" "- 基準2" "- 基準2（書き換え）" ;;
  head) replace_line "$T1" "# T-01 確認用のタスク" "# T-01 確認用のタスク（書き換え）" ;;
  forbidden)
    echo "変更" >> "$R/vault/plans/P-TEST.md"
    echo "- 変更" >> "$R/vault/log/P-TEST.md"
    echo "rule2" > "$R/vault/rules/common/x.md"
    echo '{"result":"PASS"}' > "$R/vault/verdicts/P-TEST/T-01.json" ;;
  selfdecl)
    replace_line "$T1" "- \`check_func\` 関数" "- \`check_func\` 関数
- \`extra.txt\`"
    echo "extra" > "$R/extra.txt" ;;
  hookundecl) echo "y = 2" > "$R/.claude/hooks/y.py" ;;
  hooks)
    echo "x = 2" > "$R/.claude/hooks/x.py"
    echo '{"a": 1}' > "$R/.claude/settings.json"
    printf -- '---\nname: creator\nmodel: m\n---\n' > "$R/.claude/agents/creator.md"
    echo "print(2)" > "$R/scripts/foo.py" ;;
  othertask) echo "- 進捗の追記" >> "$R/vault/tasks/P-TEST/T-02.md" ;;
  rename) git -C "$R" mv scripts/foo.py scripts/bar.py ;;
  uncommitted) apply_ok ;;
  newtask) sed 's/^# T-01 /# T-03 /' "$T1" > "$R/vault/tasks/P-TEST/T-03.md" ;;
  *) echo "unknown preset: $PRESET" >&2; exit 9 ;;
esac
git -C "$R" add -A
git -C "$R" commit -q -m "preset $PRESET" >/dev/null 2>&1
if [ "$PRESET" = "uncommitted" ]; then
  echo "extra" > "$R/extra.txt"
  echo "readme2" > "$R/docs/readme.md"
fi

HEAD0="$(git -C "$R" rev-parse HEAD)"
PORC0="$(git -C "$R" status --porcelain | tr '\n' ' ')"
( cd "$R" && python3 "$ROOT/scripts/diff_gate.py" "${ARGS[@]}" ) > "$WORK/out" 2> "$WORK/err"
RC=$?
echo "exit=$RC"
echo "changed=$(git -C "$R" diff --name-only --no-renames main work/b | tr '\n' ' ')"
if [ "${#ARGS[@]}" -eq 4 ]; then
  ( cd "$R" && python3 - "$ROOT/scripts" "$R" "${ARGS[@]}" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
try:
    import diff_gate
    v = diff_gate.check(*sys.argv[2:])
except Exception as e:  # noqa: BLE001
    print("check_error=" + type(e).__name__)
else:
    print("check=" + " ".join(p for p, _ in v))
PY
  )
fi
HEAD1="$(git -C "$R" rev-parse HEAD)"
PORC1="$(git -C "$R" status --porcelain | tr '\n' ' ')"
[ "$HEAD0" = "$HEAD1" ] && [ "$PORC0" = "$PORC1" ] && echo "unchanged=yes" || echo "unchanged=no"
echo "porcelain=$PORC1"
echo "== stdout =="
cat "$WORK/out"
echo "== stderr =="
cat "$WORK/err"
