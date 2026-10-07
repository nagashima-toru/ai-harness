#!/usr/bin/env python3
"""会話記録（JSONL）の Agent 呼び出し結果から、agent×model の使用量を集計してタブ区切りで出す。

使い方:
  python3 scripts/usage_stats.py [--plan <計画ID>] [ファイルかディレクトリ ...]
  - ファイルの引数はそのファイルを、ディレクトリの引数はその直下の *.jsonl を読む
    （下位のディレクトリは見ない）。
  - 引数が無ければ既定の読み込み先 ~/.claude/projects/<プロジェクトの絶対パスの
    英数字以外をすべて - に置き換えたもの>/*.jsonl を読む。プロジェクトの絶対パスは
    このスクリプトの2つ上のディレクトリ（realpath にしない）。~ は HOME で決める。
    既定の読み込み先のディレクトリが無ければ見出し行だけを出して終了コード0。
  - 存在しない引数があれば標準エラーに「usage_stats.py: 見つかりません: <パス>」を出し、
    何も出力せず終了コード1。引数の誤りは終了コード2（argparse の既定）。
  - --plan <計画ID>: toolUseResult の prompt から P-\\d{8}-[a-z0-9-]+/T-\\d{2} で最初に
    一致したものの「/」より前が計画IDと一致する呼び出しだけを数える。一致が取れない
    呼び出しは数えない。

読む項目:
  各行を JSON として読み、toolUseResult が辞書で、agentType（文字列）・resolvedModel
  （文字列）・totalTokens（数）・totalDurationMs（数）・totalToolUseCount（数）が
  そろっているものを1回の呼び出しとして数える（bool は数として扱わない）。
  それ以外の行（JSON でない・toolUseResult が無い／辞書でない・キーが欠けている／型が違う・
  空行）は黙って読み飛ばす。文字列の agentId があれば、同じ agentId は全ファイルを通して
  最初の1回だけ数える（agentId が無いものは毎回数える）。prompt（文字列）は --plan の時だけ使う。

出力の列（タブ区切り、標準出力。2行目以降は agent、次に model の昇順）:
  agent            agentType
  model            resolvedModel（変換せずそのまま）
  calls            呼び出し回数
  tokens_total     totalTokens の合計（整数）
  tokens_avg       tokens_total / calls（小数1桁）
  duration_avg_s   totalDurationMs の平均を秒にしたもの（小数1桁）
  tool_uses_avg    totalToolUseCount の平均（小数1桁）
  数える呼び出しが0件なら見出し行だけ。

会話記録・vault のどちらにも書かない（読むだけ）。標準ライブラリだけを使う。
"""
import argparse
import glob
import json
import os
import re
import sys

HEADER = "agent\tmodel\tcalls\ttokens_total\ttokens_avg\tduration_avg_s\ttool_uses_avg"
PLAN_RE = re.compile(r"P-\d{8}-[a-z0-9-]+/T-\d{2}")


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def default_dir():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    key = re.sub(r"[^A-Za-z0-9]", "-", root)
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", key)


def expand(args):
    """引数からファイルの一覧を作る。存在しない引数があれば (None, パス)。"""
    files = []
    for a in args:
        if os.path.isdir(a):
            files.extend(sorted(glob.glob(os.path.join(glob.escape(a), "*.jsonl"))))
        elif os.path.exists(a):
            files.append(a)
        else:
            return None, a
    return files, None


def calls(files, plan):
    seen = set()
    for path in files:
        try:
            f = open(path, encoding="utf-8", errors="replace")
        except OSError:
            continue
        with f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    obj = json.loads(raw)
                except ValueError:
                    continue
                r = obj.get("toolUseResult") if isinstance(obj, dict) else None
                if not isinstance(r, dict):
                    continue
                at, rm = r.get("agentType"), r.get("resolvedModel")
                tk, du, tu = (
                    r.get("totalTokens"),
                    r.get("totalDurationMs"),
                    r.get("totalToolUseCount"),
                )
                if not (isinstance(at, str) and isinstance(rm, str)):
                    continue
                if not (is_num(tk) and is_num(du) and is_num(tu)):
                    continue
                aid = r.get("agentId")
                if isinstance(aid, str):
                    if aid in seen:
                        continue
                    seen.add(aid)
                if plan is not None:
                    prompt = r.get("prompt")
                    m = PLAN_RE.search(prompt) if isinstance(prompt, str) else None
                    if not m or m.group(0).split("/")[0] != plan:
                        continue
                yield at, rm, tk, du, tu


def main(argv):
    ap = argparse.ArgumentParser(prog="usage_stats.py")
    ap.add_argument("--plan")
    ap.add_argument("paths", nargs="*")
    ns = ap.parse_args(argv[1:])
    if ns.paths:
        files, missing = expand(ns.paths)
        if files is None:
            print(f"usage_stats.py: 見つかりません: {missing}", file=sys.stderr)
            return 1
    else:
        d = default_dir()
        files = sorted(glob.glob(os.path.join(glob.escape(d), "*.jsonl"))) if os.path.isdir(d) else []
    groups = {}
    for at, rm, tk, du, tu in calls(files, ns.plan):
        g = groups.setdefault((at, rm), [0, 0, 0, 0])
        g[0] += 1
        g[1] += tk
        g[2] += du
        g[3] += tu
    print(HEADER)
    for (at, rm) in sorted(groups):
        n, tk, du, tu = groups[(at, rm)]
        print(
            "\t".join(
                [
                    at,
                    rm,
                    str(n),
                    str(int(tk)),
                    f"{tk / n:.1f}",
                    f"{du / n / 1000:.1f}",
                    f"{tu / n:.1f}",
                ]
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
