#!/usr/bin/env python3
"""計画の verdict の reasons を `<id>: <reason>` の形で1行ずつ標準出力に出す。

使い方: python3 scripts/verdict_notes.py <計画ID> [--dir <ディレクトリ>]
読み込み先は既定で <リポジトリのルート>/vault/verdicts/<計画ID>/ の *.json。
--dir を渡すとそのディレクトリ（<id>.json を直接持つ）の *.json を読み、計画 ID は使わない
（相対パスはカレントディレクトリ基準）。ファイルには書き込まない。

出力: reasons が空でない verdict について、要素ごとに `<id>: <reason>` を1行
（id はファイル名から .json を除いたもの。ファイル名順）。要素内の改行は空白1つにする。
出す行が無ければ `指摘なし` の1行だけを出す。
JSON として読めない・reasons が無い／配列でない verdict は読み飛ばし、標準エラーに
`verdict_notes.py: 読み飛ばした: <パス>` を出す（終了コードは0のまま）。

終了コード: 0 出力した（「指摘なし」を含む）／1 読み込み先のディレクトリが無い／2 引数の誤り
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys


def repo_root():
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    except OSError:
        return os.getcwd()
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    return os.getcwd()


def main():
    ap = argparse.ArgumentParser(prog="verdict_notes.py")
    ap.add_argument("plan_id")
    ap.add_argument("--dir", dest="dir")
    args = ap.parse_args()  # 引数の誤りは argparse が終了コード2で終わる

    d = args.dir if args.dir else os.path.join(repo_root(), "vault", "verdicts", args.plan_id)
    if not os.path.isdir(d):
        print("verdict_notes.py: ディレクトリが無い: %s" % d, file=sys.stderr)
        return 1

    lines = []
    for path in sorted(glob.glob(os.path.join(glob.escape(d), "*.json"))):
        tid = os.path.basename(path)[:-len(".json")]
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = None
        reasons = data.get("reasons") if isinstance(data, dict) else None
        if not isinstance(reasons, list):
            print("verdict_notes.py: 読み飛ばした: %s" % path, file=sys.stderr)
            continue
        for r in reasons:
            text = r if isinstance(r, str) else str(r)
            lines.append("%s: %s" % (tid, re.sub(r"[\r\n]", " ", text)))

    if not lines:
        lines = ["指摘なし"]
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
