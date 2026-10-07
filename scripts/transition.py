#!/usr/bin/env python3
"""計画票のタスク表の状態遷移を1コマンドで行う（D-012 フェーズ2）。

使い方:
    python3 scripts/transition.py <計画ID> <id>[,<id>...] <遷移先>
        [--question <文> | --question-file <パス>] [--note <補足>] [--no-model]

やること（すべての id の検査を先に済ませ、通った時だけ行う）:
  1. 計画票 vault/plans/<計画ID>.md のタスク表の status・attempt・question を書き換える
  2. vault/log/<計画ID>.md に `- <日時> <id> <旧>→<新> attempt=<n>[ <補足>]` を id の順に追記する
     （日時は UTC+9 固定のスクリプトの実時刻）
  3. 計画票と log だけを `git commit` する（ほかに staged な変更があっても混ぜない）

遷移表は todo→doing・doing→doing・doing→review・doing→blocked・review→done・
review→doing・review→blocked の7つだけ。承認と blocked の解除は扱わない。
review→done は T-02 で verdict の検査を実装するまで扱えない。
`--no-model` は受け付けるだけで、今は何もしない。

終了コード:
    0  遷移した
    1  前提を満たさず何も変えていない（理由は標準エラーに `[transition] ` で出す）
    2  引数の誤り
"""
import sys

sys.dont_write_bytecode = True

import argparse
import datetime
import os
import re
import subprocess

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".claude", "hooks")
)
try:
    import _hooklib
except Exception as exc:  # noqa: BLE001
    sys.stderr.write("[transition] _hooklib を import できません: %s\n" % exc)
    sys.exit(1)

TRANSITIONS = (
    ("todo", "doing"),
    ("doing", "doing"),
    ("doing", "review"),
    ("doing", "blocked"),
    ("review", "done"),
    ("review", "doing"),
    ("review", "blocked"),
)
ATTEMPT_PLUS = (("doing", "doing"), ("review", "doing"))


class Refuse(Exception):
    """前提を満たさない（終了コード1）。"""


def fail(msg):
    sys.stderr.write("[transition] %s\n" % msg)
    sys.exit(1)


def clean_text(s):
    s = s.replace("|", "／")
    s = re.sub(r"\r\n|\r|\n", " ", s)
    return s.strip()


def max_attempts():
    try:
        return int(os.environ.get("HARNESS_MAX_ATTEMPTS", "3"))
    except ValueError:
        return 3


def run_git(root, *args):
    return subprocess.run(
        ["git", "-C", root] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )


def parse_args(argv):
    p = argparse.ArgumentParser(prog="transition.py", description="計画票のタスク表の状態遷移")
    p.add_argument("plan_id")
    p.add_argument("ids")
    p.add_argument("target")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--question")
    g.add_argument("--question-file")
    p.add_argument("--note", default=None)
    p.add_argument("--no-model", action="store_true")
    args = p.parse_args(argv)

    ids = [x.strip() for x in args.ids.split(",")]
    if any(x == "" for x in ids) or len(set(ids)) != len(ids):
        p.error("id の指定が不正です（空の要素または重複）: %s" % args.ids)
    args.id_list = ids

    question = None
    if args.question is not None or args.question_file is not None:
        if args.target != "blocked":
            p.error("--question／--question-file は遷移先が blocked の時だけ指定できます")
        if args.question is not None:
            question = args.question
        else:
            try:
                with open(args.question_file, encoding="utf-8") as f:
                    question = f.read()
            except (OSError, UnicodeDecodeError) as exc:
                p.error("--question-file を読めません: %s" % exc)
    args.question_text = clean_text(question) if question is not None else ""
    args.note_text = clean_text(args.note) if args.note is not None else ""
    return args


def find_row_indexes(lines):
    """タスク表の中の行の位置を {id: 行番号} で返す（raw_rows と同じ規則）。"""
    found = {}
    in_table = False
    for i, line in enumerate(lines):
        if line.startswith("## "):
            in_table = line.strip().startswith("## タスク表")
            continue
        stripped = line.strip()
        if not in_table or not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or cells[0] == "id" or re.fullmatch(r"-*", cells[0]):
            continue
        found.setdefault(cells[0], i)
    return found


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def main(argv):
    args = parse_args(argv)
    plan_id = args.plan_id

    r = run_git(os.getcwd(), "rev-parse", "--show-toplevel")
    if r.returncode != 0 or not r.stdout.strip():
        fail("git リポジトリではありません")
    root = r.stdout.strip()

    plan_rel = "vault/plans/%s.md" % plan_id
    log_rel = "vault/log/%s.md" % plan_id
    plan_path = os.path.join(root, plan_rel)
    log_path = os.path.join(root, log_rel)

    try:
        plan_bytes = read_bytes(plan_path)
        plan_text = plan_bytes.decode("utf-8")
    except (OSError, UnicodeDecodeError):
        fail("計画票を読めません: %s" % plan_rel)
    if _hooklib.frontmatter_status(plan_text) != "approved":
        fail("計画票 %s の status が approved ではありません" % plan_rel)

    r = run_git(root, "rev-parse", "--abbrev-ref", "HEAD")
    branch = r.stdout.strip()
    expected = "work/" + plan_id.lower()
    if r.returncode != 0 or branch != expected:
        fail("現在のブランチ %r が %r ではありません" % (branch, expected))

    tasks = _hooklib.parse_tasks(plan_text)
    by_id = {}
    for t in tasks:
        by_id.setdefault(t["id"], t)
    plan_lines = plan_text.splitlines(True)
    positions = find_row_indexes(plan_lines)

    target = args.target
    limit = max_attempts()
    plans = []  # (id, old, new, attempt)
    olds = set()
    for tid in args.id_list:
        if tid not in by_id or tid not in positions:
            fail("%s はタスク表にありません" % tid)
        row = by_id[tid]
        old = row["status"]
        olds.add(old)
        if (old, target) not in TRANSITIONS:
            fail("%s: %s→%s は遷移表にありません" % (tid, old, target))
        if (old, target) == ("review", "done"):
            fail("review→done は T-02 で verdict の検査を実装するまで扱えません")
        try:
            cur = int(row["attempt"])
        except ValueError:
            fail("%s: attempt が整数ではありません: %r" % (tid, row["attempt"]))
        if old == "todo":
            for dep in [x.strip() for x in row["after"].split(",")]:
                if dep in ("", "-"):
                    continue
                if dep not in by_id or by_id[dep]["status"] != "done":
                    fail("%s: after の %s が done ではありません" % (tid, dep))
            new_attempt = 1
        elif (old, target) in ATTEMPT_PLUS:
            new_attempt = cur + 1
        else:
            new_attempt = cur
        if new_attempt > limit:
            fail("%s: attempt=%d が上限 %d を超えます" % (tid, new_attempt, limit))
        if target == "blocked" and not args.question_text:
            fail("%s: blocked にするには question が必要です" % tid)
        plans.append((tid, old, target, new_attempt))
    if len(olds) != 1:
        fail("渡した id の現在の status がそろっていません: %s" % ", ".join(sorted(olds)))
    old_all = plans[0][1]

    # 書き換え
    new_lines = list(plan_lines)
    for tid, old, new, attempt in plans:
        i = positions[tid]
        line = plan_lines[i]
        body = line.rstrip("\r\n")
        eol = line[len(body):]
        indent = body[: len(body) - len(body.lstrip())]
        cells = [c.strip() for c in body.strip().strip("|").split("|")]
        cells = cells + [""] * (6 - len(cells))
        question = args.question_text if new == "blocked" else ""
        row = "| %s | %s | %d | %s | %s |" % (cells[0], new, attempt, cells[3], cells[4])
        row += (" %s |" % question) if question else " |"
        new_lines[i] = indent + row + eol
    new_plan_bytes = "".join(new_lines).encode("utf-8")

    now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime(
        "%Y-%m-%d %H:%M"
    )
    log_existed = os.path.exists(log_path)
    log_before = read_bytes(log_path) if log_existed else b""
    add = ""
    if log_existed and log_before and not log_before.endswith(b"\n"):
        add = "\n"
    for tid, old, new, attempt in plans:
        line = "- %s %s %s→%s attempt=%d" % (now, tid, old, new, attempt)
        if args.note_text:
            line += " " + args.note_text
        add += line + "\n"
    new_log_bytes = log_before + add.encode("utf-8")

    paths = [plan_rel, log_rel]
    subject = "%s/%s: %s→%s" % (plan_id, ",".join(args.id_list), old_all, target)

    log_dir_created = None
    try:
        with open(plan_path, "wb") as f:
            f.write(new_plan_bytes)
        if not os.path.isdir(os.path.dirname(log_path)):
            os.makedirs(os.path.dirname(log_path))
            log_dir_created = os.path.dirname(log_path)
        with open(log_path, "wb") as f:
            f.write(new_log_bytes)
        err = ""
        r = run_git(root, "add", "--", *paths)
        if r.returncode == 0:
            r = run_git(root, "commit", "-q", "-m", subject, "--", *paths)
        if r.returncode != 0:
            err = r.stderr
    except OSError as exc:
        err = str(exc)
        r = None

    if err:
        with open(plan_path, "wb") as f:
            f.write(plan_bytes)
        if log_existed:
            with open(log_path, "wb") as f:
                f.write(log_before)
        elif os.path.exists(log_path):
            os.remove(log_path)
        if log_dir_created:
            try:
                os.rmdir(log_dir_created)
            except OSError:
                pass
        run_git(root, "reset", "-q", "--", *paths)
        fail("git の操作に失敗したため元に戻しました: %s" % err.strip())

    for tid, old, new, attempt in plans:
        print("%s/%s: %s→%s attempt=%d" % (plan_id, tid, old, new, attempt))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
