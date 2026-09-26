#!/usr/bin/env bash
# 対象を検証してから worktree とそのブランチを破棄する。
# 使い方: bash scripts/discard_worktree.sh <worktree のパス> <ブランチ名>
# `git branch -D` は .claude/settings.json の permissions.deny で直接の Bash 呼び出しを
# 拒否されているため（issue #34）、run スキルの FAIL 再試行時（手順6.3.2）はこのスクリプト
# 経由で worktree とブランチを破棄する。このスクリプトはブランチ名が `worktree-agent-` で
# 始まること、かつ指定パスが `git worktree list --porcelain` に登録済みでそのブランチが
# 指定ブランチ名と一致することを確認してから削除する。どちらか一方でも満たさなければ何も
# 削除せず、理由を標準エラーに出して非0で終わる。実行はカレント作業ディレクトリの git
# リポジトリ（計画ブランチ側のメインの作業ツリー）を前提とする（`git -C` の指定は不要）。
set -eu

USAGE="usage: bash scripts/discard_worktree.sh <worktree のパス> <ブランチ名>"
BRANCH_PREFIX="worktree-agent-"

if [ $# -ne 2 ]; then
  echo "$USAGE" >&2
  exit 2
fi

WORKTREE_ARG="$1"
BRANCH_NAME="$2"

case "$BRANCH_NAME" in
  "$BRANCH_PREFIX"*) ;;
  *)
    echo "discard_worktree: ブランチ名が '$BRANCH_PREFIX' で始まっていません: $BRANCH_NAME" >&2
    exit 1
    ;;
esac

TARGET_PATH="$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$WORKTREE_ARG")"

FOUND=0
MATCHING=0
ACTUAL_BRANCH=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      wpath="${line#worktree }"
      if [ "$wpath" = "$TARGET_PATH" ]; then
        FOUND=1
        MATCHING=1
        ACTUAL_BRANCH=""
      else
        MATCHING=0
      fi
      ;;
    "branch refs/heads/"*)
      if [ "$MATCHING" -eq 1 ]; then
        ACTUAL_BRANCH="${line#branch refs/heads/}"
      fi
      ;;
  esac
done < <(git worktree list --porcelain)

if [ "$FOUND" -ne 1 ]; then
  echo "discard_worktree: 指定パスは登録済み worktree ではありません: $TARGET_PATH" >&2
  exit 1
fi

if [ "$ACTUAL_BRANCH" != "$BRANCH_NAME" ]; then
  echo "discard_worktree: 登録済み worktree のブランチが指定と一致しません: 実際=$ACTUAL_BRANCH 指定=$BRANCH_NAME" >&2
  exit 1
fi

git worktree remove --force "$TARGET_PATH"
git branch -D "$BRANCH_NAME"
