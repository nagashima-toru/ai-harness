#!/usr/bin/env python3
"""計画一式を除去する前に PR 本文へ写す「計画の記録」を Markdown で標準出力に出す。

使い方: python3 scripts/plan_record.py <計画ID>
読み込み先は <リポジトリのルート>/vault/plans/<計画ID>.md と
<リポジトリのルート>/vault/log/<計画ID>.md（ルートはカレントディレクトリの
`git rev-parse --show-toplevel`、取れなければカレントディレクトリ）。ファイルには書き込まない。

出力の形（この順・この見出し。末尾は改行1つ）:
  ## 計画の記録

  ### ゴール
  <計画票の `# ゴール` か `## ゴール` の次の行から次の見出し行の前まで。無ければ（なし）>

  ### タスク表
  <計画票で最初の `| id | status ...` 見出し行から続く `|` 始まりの行をそのまま。無ければ（なし）>

  ### log
  <details>
  <summary>log の全行</summary>

  <log ファイルの中身をそのまま>

  </details>

終了コード: 0 出力した／1 計画票か log が無い（無いもの1つにつき標準エラーに
`plan_record.py: 見つかりません: <パス>` を出し、標準出力には何も出さない）／2 引数の誤り
"""
import argparse
import os
import re
import subprocess
import sys

HEADING = re.compile(r"^#{1,6}\s")


def repo_root():
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    except OSError:
        return os.getcwd()
    if r.returncode == 0 and r.stdout.strip():
        return r.stdout.strip()
    return os.getcwd()


def goal_section(lines):
    start = None
    for i, ln in enumerate(lines):
        if ln.strip() in ("# ゴール", "## ゴール"):
            start = i + 1
            break
    if start is None:
        return ["（なし）"]
    body = []
    for ln in lines[start:]:
        if HEADING.match(ln):
            break
        body.append(ln)
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    return body or ["（なし）"]


def table_rows(lines):
    for i, ln in enumerate(lines):
        s = ln.lstrip()
        if not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip().strip("|").split("|")]
        if len(cells) >= 2 and cells[0] == "id" and cells[1] == "status":
            rows = []
            for ln2 in lines[i:]:
                if not ln2.lstrip().startswith("|"):
                    break
                rows.append(ln2)
            return rows
    return ["（なし）"]


def main():
    ap = argparse.ArgumentParser(prog="plan_record.py")
    ap.add_argument("plan_id")
    args = ap.parse_args()  # 引数の誤りは argparse が終了コード2で終わる

    root = repo_root()
    plan_path = os.path.join(root, "vault", "plans", args.plan_id + ".md")
    log_path = os.path.join(root, "vault", "log", args.plan_id + ".md")
    missing = [p for p in (plan_path, log_path) if not os.path.isfile(p)]
    if missing:
        for p in missing:
            print("plan_record.py: 見つかりません: %s" % p, file=sys.stderr)
        return 1

    with open(plan_path, encoding="utf-8") as f:
        plan_lines = f.read().splitlines()
    with open(log_path, encoding="utf-8") as f:
        log_text = f.read().rstrip("\n")

    out = ["## 計画の記録", "", "### ゴール"]
    out += goal_section(plan_lines)
    out += ["", "### タスク表"]
    out += table_rows(plan_lines)
    out += ["", "### log", "<details>", "<summary>log の全行</summary>", ""]
    if log_text:
        out += log_text.split("\n")
    out += ["", "</details>"]
    sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
