#!/usr/bin/env bash
# 起点のコミットを明示して creator 用の worktree とそのブランチを作る。
# 使い方: bash scripts/add_worktree.sh <PLAN_HEAD>
# run スキルは手順3で creator の worktree をこのスクリプトで作る。Agent ツールの worktree 隔離が
# 計画ブランチ以外から切ることがある（Issue #209）ため、計画ブランチの HEAD（PLAN_HEAD）を
# 起点に明示する。<PLAN_HEAD> は commit に解決し、今の HEAD と同じかどうかは見ない。
# パスは <ルート>/.claude/worktrees/agent-<x>、ブランチ名は worktree-agent-<x>（<x> は8桁の
# 英小文字の16進）。discard_worktree.sh と transition.py の check_worktree の検証を通る形。
# 成功時だけ標準出力に1行 `path=<realpath> branch=<ブランチ名> plan_head=<40桁の sha>` を出す。
# 実行はカレント作業ディレクトリの git リポジトリ（run のメインの作業ツリー）を前提とする
# （`git -C` の指定は不要）。コミットはしない。
# 終了コード: 0=作った / 1=<PLAN_HEAD> を commit に解決できない・git リポジトリの外・
# 名前が5回続けて当たった・git worktree add の失敗 / 2=引数の誤り
set -eu

USAGE="usage: bash scripts/add_worktree.sh <PLAN_HEAD>"
BRANCH_PREFIX="worktree-agent-"

if [ $# -ne 1 ]; then
  echo "$USAGE" >&2
  exit 2
fi

PLAN_HEAD_ARG="$1"

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "add_worktree: git リポジトリの外です" >&2
  exit 1
fi

if ! SHA="$(git rev-parse --verify --quiet "${PLAN_HEAD_ARG}^{commit}")" || [ -z "$SHA" ]; then
  echo "add_worktree: commit に解決できません: $PLAN_HEAD_ARG" >&2
  exit 1
fi

WT_PARENT="$ROOT/.claude/worktrees"
NAME=""
WT_PATH=""
BRANCH=""
tries=0
while [ "$tries" -lt 5 ]; do
  tries=$((tries + 1))
  x="$(python3 -c "import secrets;print(secrets.token_hex(4))")"
  if [ ! -e "$WT_PARENT/agent-$x" ] && ! git show-ref --verify --quiet "refs/heads/${BRANCH_PREFIX}$x"; then
    NAME="$x"
    WT_PATH="$WT_PARENT/agent-$x"
    BRANCH="${BRANCH_PREFIX}$x"
    break
  fi
done

if [ -z "$NAME" ]; then
  echo "add_worktree: 名前が5回続けて既存と重なりました" >&2
  exit 1
fi

mkdir -p "$WT_PARENT"
if ! ERR="$(git worktree add -q -b "$BRANCH" "$WT_PATH" "$SHA" 2>&1 >/dev/null)"; then
  echo "$ERR" >&2
  exit 1
fi

REAL="$(python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$WT_PATH")"
echo "path=$REAL branch=$BRANCH plan_head=$SHA"
