#!/usr/bin/env bash
# ホスティング判定と PR/MR 作成を1箇所にまとめる共有スクリプト。
# `run`/`design` スキルの最終手順から呼ばれ、GitHub・GitLab・ホスティング無しの
# 3経路に対応する。マージ（人が行う）は本スクリプトの責務外であり、実行しない。
#
# 使い方: bash scripts/vcs_finish.sh [引数...]（引数なしなら gh は --fill、glab は --fill --yes を既定で付ける）
#   引数がある時は gh pr create / glab mr create にそのまま渡す（既定値は足さない）
#   引数なしで、現在のブランチ（work/<計画IDの英小文字>）の計画票が見つかった時は、--fill の代わりに
#   タイトル「<計画ID>: <ゴールの1行目>」と scripts/pr_body.py の出力（タスク履歴表）を本文として渡す
#
# ホスティング判定は環境変数 HARNESS_VCS_HOST で上書きできる：
#   github | gitlab | none | auto（未指定時の既定値）
# auto の場合は `git remote get-url origin` の値を見て判定する：
#   github.com を含む -> github
#   gitlab を含む     -> gitlab
#   それ以外・origin が無い -> none
set -u

# 引数なしの時の PR/MR 本文を作る。見つかれば pr_title / pr_body を設定して0、無ければ1を返す。
find_plan_body() {
  pr_title=""; pr_body=""
  local branch rest toplevel f id lower plan_id="" goal body
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
      break
    fi
  done
  [ -n "$plan_id" ] || return 1
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
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
      current_branch="$(git rev-parse --abbrev-ref HEAD)"
      git push -u origin "$current_branch"
      push_status=$?
      if [ "$push_status" -ne 0 ]; then
        exit "$push_status"
      fi
    fi
    if [ "$#" -eq 0 ]; then
      if find_plan_body; then
        gh pr create --title "$pr_title" --body "$pr_body"
      else
        gh pr create --fill
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
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
      current_branch="$(git rev-parse --abbrev-ref HEAD)"
      git push -u origin "$current_branch"
      push_status=$?
      if [ "$push_status" -ne 0 ]; then
        exit "$push_status"
      fi
    fi
    if [ "$#" -eq 0 ]; then
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
