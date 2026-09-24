#!/usr/bin/env bash
# ホスティング判定と PR/MR 作成を1箇所にまとめる共有スクリプト。
# `run`/`design` スキルの最終手順から呼ばれ、GitHub・GitLab・ホスティング無しの
# 3経路に対応する。マージ（人が行う）は本スクリプトの責務外であり、実行しない。
#
# 使い方: bash scripts/vcs_finish.sh [gh pr create / glab mr create にそのまま渡す引数...]
#
# ホスティング判定は環境変数 HARNESS_VCS_HOST で上書きできる：
#   github | gitlab | none | auto（未指定時の既定値）
# auto の場合は `git remote get-url origin` の値を見て判定する：
#   github.com を含む -> github
#   gitlab を含む     -> gitlab
#   それ以外・origin が無い -> none
set -u

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
    gh pr create "$@"
    exit $?
    ;;
  gitlab)
    glab mr create "$@"
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
