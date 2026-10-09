#!/usr/bin/env bash
# ホスティング判定と PR/MR 作成を1箇所にまとめる共有スクリプト。
# `run`/`design` スキルの最終手順から呼ばれ、GitHub・GitLab・ホスティング無しの
# 3経路に対応する。マージ（人が行う）は本スクリプトの責務外であり、実行しない。
#
# 使い方: bash scripts/vcs_finish.sh [引数...]（引数なしなら GitHub は REST の gh api、glab は --fill --yes を既定で付ける）
#   GitHub は GraphQL が使えない環境（Claude Code の Web セッション等）でも通るよう、PR を REST
#   （gh api -X POST repos/<owner>/<repo>/pulls、base は main 固定、head は現在のブランチ）で作り、
#   PR の URL を標準出力に出す。owner/repo は origin の URL から取り、取れなければ push の前に終了コード2で終わる
#   引数がある時は gh pr create / glab mr create にそのまま渡す（既定値は足さない。REST には変換しない）
#   引数なしで、現在のブランチ（work/<計画IDの英小文字>）の計画票が見つかった時は、
#   タイトル「<計画ID>: <ゴールの1行目>」と scripts/pr_body.py の出力（タスク履歴表）を本文として渡す
#   計画が見つからない時の GitHub は、直近コミットの件名と本文をタイトルと本文にする
#   引数なしで HARNESS_PR_BODY_FILE（本文のファイル）が空でない値で設定されている時だけ、その内容を本文として渡す
#   （gh api は -F body=@パス でファイルを読ませ、glab は --description にファイルの中身を渡す）。引数がある時は見ない。
#   読めないファイルなら git push の前に標準エラーへ出して終了コード2で終わる（none の経路では検査しない）
#   HARNESS_PR_TITLE は上の経路でだけ使うタイトル。未設定か空なら計画ID、計画が見つからなければ現在のブランチ名
#
# ホスティング判定は環境変数 HARNESS_VCS_HOST で上書きできる：
#   github | gitlab | none | auto（未指定時の既定値）
# auto の場合は `git remote get-url origin` の値を見て判定する：
#   github.com を含む -> github
#   gitlab を含む     -> gitlab
#   それ以外・origin が無い -> none
set -u

# 現在のブランチ（work/<計画IDの英小文字>）に対応する計画票を探し、plan_id と plan_toplevel を設定する。無ければ1を返す。
find_plan_id() {
  plan_id=""; plan_toplevel=""
  local branch rest toplevel f id lower
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  case "$branch" in
    work/*) rest="${branch#work/}" ;;
    *) return 1 ;;
  esac
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  for f in "$toplevel"/vault/plans/*.md; do
    [ -f "$f" ] || continue
    id="$(basename "$f" .md)"
    lower="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"
    if [ "$lower" = "$rest" ]; then
      plan_id="$id"
      plan_toplevel="$toplevel"
      break
    fi
  done
  [ -n "$plan_id" ] || return 1
  return 0
}

# 引数なしの時の PR/MR 本文を作る。見つかれば pr_title / pr_body を設定して0、無ければ1を返す。
find_plan_body() {
  pr_title=""; pr_body=""
  local goal body toplevel
  find_plan_id || return 1
  toplevel="$plan_toplevel"
  body="$(python3 "$(dirname "$0")/pr_body.py" "$plan_id" 2>/dev/null)" || return 1
  [ -n "$body" ] || return 1
  goal="$(awk '/^# ゴール[[:space:]]*$/ {f=1; next} f && NF {print; exit}' "$toplevel/vault/plans/$plan_id.md")"
  if [ -n "$goal" ]; then
    pr_title="$plan_id: $goal"
  else
    pr_title="$plan_id"
  fi
  pr_body="$body"
  return 0
}

# HARNESS_PR_BODY_FILE の経路のタイトル。HARNESS_PR_TITLE、無ければ計画ID、無ければブランチ名。
notes_title() {
  if [ -n "${HARNESS_PR_TITLE:-}" ]; then
    printf '%s' "$HARNESS_PR_TITLE"
  elif find_plan_id; then
    printf '%s' "$plan_id"
  else
    git rev-parse --abbrev-ref HEAD
  fi
}

# 引数なしで HARNESS_PR_BODY_FILE が空でない時だけ使う。読めなければ push の前に終了コード2で終わる。
use_notes=0
if [ "$#" -eq 0 ] && [ -n "${HARNESS_PR_BODY_FILE:-}" ]; then
  use_notes=1
fi
check_notes() {
  if [ "$use_notes" = 1 ] && [ ! -r "$HARNESS_PR_BODY_FILE" ]; then
    echo "vcs_finish.sh: HARNESS_PR_BODY_FILE が読めません: $HARNESS_PR_BODY_FILE" >&2
    exit 2
  fi
}

host="${HARNESS_VCS_HOST:-auto}"

if [ -z "$host" ] || [ "$host" = "auto" ]; then
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  case "$origin_url" in
    *github.com*)
      host="github"
      ;;
    *gitlab*)
      host="gitlab"
      ;;
    *)
      host="none"
      ;;
  esac
fi

case "$host" in
  github)
    if ! command -v gh >/dev/null 2>&1; then
      echo "vcs_finish.sh: gh コマンドが見つかりません（GitHub は検出済みです）。GitHub CLI をインストールするか、GitHub MCP 等の代替手段で PR を作成してください。" >&2
      exit 127
    fi
    check_notes
    if [ "$#" -eq 0 ]; then
      origin_url="$(git remote get-url origin 2>/dev/null || true)"
      trimmed="${origin_url%/}"
      trimmed="${trimmed%.git}"
      gh_repo=""; gh_owner=""
      case "$trimmed" in
        *[/:]*)
          gh_repo="${trimmed##*[/:]}"
          gh_rest="${trimmed%[/:]*}"
          gh_owner="${gh_rest##*[/:]}"
          ;;
      esac
      if [ -z "$gh_owner" ] || [ -z "$gh_repo" ]; then
        echo "vcs_finish.sh: origin の URL から owner/repo を取れません: $origin_url" >&2
        exit 2
      fi
    fi
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
      current_branch="$(git rev-parse --abbrev-ref HEAD)"
      git push -u origin "$current_branch"
      push_status=$?
      if [ "$push_status" -ne 0 ]; then
        exit "$push_status"
      fi
    fi
    if [ "$#" -eq 0 ]; then
      gh_head="$(git rev-parse --abbrev-ref HEAD)"
      gh_api=(gh api -X POST "repos/$gh_owner/$gh_repo/pulls")
      if [ "$use_notes" = 1 ]; then
        "${gh_api[@]}" -f "title=$(notes_title)" -f "head=$gh_head" -f base=main -F "body=@$HARNESS_PR_BODY_FILE" --jq .html_url
      elif find_plan_body; then
        "${gh_api[@]}" -f "title=$pr_title" -f "head=$gh_head" -f base=main -f "body=$pr_body" --jq .html_url
      else
        "${gh_api[@]}" -f "title=$(git log -1 --format=%s)" -f "head=$gh_head" -f base=main -f "body=$(git log -1 --format=%b)" --jq .html_url
      fi
    else
      gh pr create "$@"
    fi
    exit $?
    ;;
  gitlab)
    if ! command -v glab >/dev/null 2>&1; then
      echo "vcs_finish.sh: glab コマンドが見つかりません（GitLab は検出済みです）。GitLab CLI をインストールするか、GitLab MCP 等の代替手段で MR を作成してください。" >&2
      exit 127
    fi
    check_notes
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
      current_branch="$(git rev-parse --abbrev-ref HEAD)"
      git push -u origin "$current_branch"
      push_status=$?
      if [ "$push_status" -ne 0 ]; then
        exit "$push_status"
      fi
    fi
    if [ "$use_notes" = 1 ]; then
      notes_text="$(cat "$HARNESS_PR_BODY_FILE")"
      glab mr create --title "$(notes_title)" --description "$notes_text" --yes
    elif [ "$#" -eq 0 ]; then
      if find_plan_body; then
        glab mr create --title "$pr_title" --description "$pr_body" --yes
      else
        glab mr create --fill --yes
      fi
    else
      glab mr create "$@"
    fi
    exit $?
    ;;
  none)
    branch="$(git rev-parse --abbrev-ref HEAD)"
    cat <<EOF
ホスティングサービス（GitHub/GitLab）は検出されませんでした。PR/MR の作成はスキップします。
ブランチ「${branch}」の内容を main に取り込むには、人が以下を実行してください：

  git merge --no-ff ${branch}

（本スクリプトはマージを実行しません。main への取り込みは人が行ってください。）
EOF
    exit 0
    ;;
  *)
    echo "vcs_finish.sh: 未知の HARNESS_VCS_HOST 値です: $host（github/gitlab/none/auto のいずれかを指定してください）" >&2
    exit 2
    ;;
esac
