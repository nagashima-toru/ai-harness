#!/usr/bin/env python3
"""log から creator のモデル別に集計してタブ区切りで標準出力に出す。

使い方:
  python3 scripts/model_stats.py [log ファイル ...]
  引数が無ければ vault/log/*.md（vault/archive/ 配下は含めない）を対象にする。

定義は docs/vault-spec.md 7節を参照。

noted_rate（末尾の列）の定義:
  対象タスク（最後の遷移行が →done か →blocked）のうち、verdict の reasons が
  空でない配列のタスクの件数 ÷ 対象タスク数（分母は tasks 列と同じ）。
  verdict の場所は log のパスから決める。log が <base>/log/<計画ID>.md の時は
  <base>/verdicts/<計画ID>/<id>.json（archive の log も同じ規則）。
  log の親ディレクトリ名が log でない時は場所を決められないので指摘なしとして数える。
  verdict が無い・JSON として読めない・reasons が無い／配列でない／空の時も
  指摘なしとして数える（エラーにしない）。verdict の task・attempt・result は見ない。
"""
import glob
import json
import os
import re
import sys

LINE_RE = re.compile(
    r"^- \d{4}-\d{2}-\d{2} \d{2}:\d{2} (\S+) (\w+)→(\w+)(?:\s+(.*))?$"
)
ATTEMPT_RE = re.compile(r"(?:^|\s)attempt=(\d+)")
CREATOR_RE = re.compile(r"(?:^|\s)creator=(\S+)")
HEADER = "model\ttasks\tfirst_pass_rate\tavg_attempt\tblocked_rate\tnoted_rate"


def default_logs():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return sorted(glob.glob(os.path.join(root, "vault", "log", "*.md")))


def has_notes(path, plan, tid):
    """log のパスから verdict を探し、reasons が空でない配列なら True。"""
    logdir = os.path.dirname(os.path.abspath(path))
    if os.path.basename(logdir) != "log":
        return False
    vpath = os.path.join(os.path.dirname(logdir), "verdicts", plan, tid + ".json")
    try:
        with open(vpath, encoding="utf-8") as f:
            reasons = json.load(f).get("reasons")
    except (OSError, ValueError, AttributeError):
        return False
    return isinstance(reasons, list) and len(reasons) > 0


def collect(paths):
    """{計画ID/id: {"last": (from, to, attempt), "creator": str|None}} を返す。"""
    tasks = {}
    for path in paths:
        plan = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as f:
            for raw in f:
                m = LINE_RE.match(raw.rstrip("\n"))
                if not m:
                    continue
                tid, src, dst, rest = m.group(1), m.group(2), m.group(3), m.group(4) or ""
                if tid == "-":
                    continue
                am = ATTEMPT_RE.search(rest)
                attempt = int(am.group(1)) if am else None
                t = tasks.setdefault(f"{plan}/{tid}", {"last": None, "creator": None})
                t["path"], t["plan"], t["tid"] = path, plan, tid
                t["last"] = (src, dst, attempt)
                # 集計キー: doing→review / doing→blocked のうち、最後の creator= 付き行の値。
                # creator= の無い行は読み飛ばし、前の値を残す（無ければ unknown）。
                if src == "doing" and dst in ("review", "blocked"):
                    cm = CREATOR_RE.search(rest)
                    if cm:
                        t["creator"] = cm.group(1)
    return tasks


def main(argv):
    paths = argv[1:] if len(argv) > 1 else default_logs()
    tasks = collect(paths)
    groups = {}
    for t in tasks.values():
        src, dst, attempt = t["last"]
        if dst not in ("done", "blocked"):
            continue
        g = groups.setdefault(
            t["creator"] or "unknown",
            {"n": 0, "first": 0, "attempts": [], "blocked": 0, "noted": 0},
        )
        g["n"] += 1
        if dst == "done" and src == "review" and attempt == 1:
            g["first"] += 1
        if dst == "blocked":
            g["blocked"] += 1
        if has_notes(t["path"], t["plan"], t["tid"]):
            g["noted"] += 1
        g["attempts"].append(attempt if attempt is not None else 1)
    print(HEADER)
    for model in sorted(groups):
        g = groups[model]
        n = g["n"]
        print(
            "\t".join(
                [
                    model,
                    str(n),
                    f"{g['first'] / n:.2f}",
                    f"{sum(g['attempts']) / n:.2f}",
                    f"{g['blocked'] / n:.2f}",
                    f"{g['noted'] / n:.2f}",
                ]
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
