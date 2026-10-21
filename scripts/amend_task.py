#!/usr/bin/env python3
"""タスク票の「成果物」への宣言の追加と「受け入れ基準」の行の差し替えを行い、log に1行残してコミットする。

使い方:
    python3 scripts/amend_task.py <計画ID> <id>
        [--add-deliverable <パス>]... [--replace-criterion <番号> <文>]... [--note <補足>]

`/plan unblock` の回答が成果物の追加や受け入れ基準の差し替えを含む時に使う。
--add-deliverable と --replace-criterion はそれぞれ複数回指定でき、指定した順に適用する。
どちらも1つも無ければ引数の誤り（終了コード2。リポジトリの検査より前に行う）。

やること（すべての検査を先に済ませ、通った時だけ行う）:
  1. --add-deliverable: 「## 成果物」節の最後の空でない行の直後に
     `- `<パス>`（amend_task.py で追加）` を足す。同じパスがバッククォートで宣言済みなら
     足さず `skip <パス>（宣言済み）` を出す
  2. --replace-criterion: 「## 受け入れ基準」節の <番号> 番目の行（行頭が `- ` か `数字. `）を
     `- <文>` の1行に置き換える（<文> の改行は空白に置き換え、`|` は置き換えない）。基準の追加・削除はしない
  3. vault/log/<計画ID>.md に `- <日時> <id> amend <要約>` を1行追記する（`→` は含めない）
  4. タスク票と log だけを `git commit -m "<計画ID>/<id>: amend"` する

計画票は読むだけで書き換えない（status・attempt は変えない）。

終了コード:
    0  適用した
    1  前提を満たさず何も変えていない（理由は標準エラーに `[amend_task] ` で出す）
    2  引数の誤り
"""
import sys

sys.dont_write_bytecode = True

import argparse
import os
import re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import transition
except Exception as exc:  # noqa: BLE001
    sys.stderr.write("[amend_task] transition を import できません: %s\n" % exc)
    sys.exit(1)

_hooklib = transition._hooklib

FORBIDDEN_PREFIXES = ("vault/plans/", "vault/log/", "vault/verdicts/")
ALLOWED_STATUS = ("blocked", "todo")
CRITERION_RE = re.compile(r"^(- |\d+\. )")


def criterion_text(s):
    """基準の文を1行にする。改行だけを空白1つにし、前後の空白を除く（`|` は残す）。"""
    return re.sub(r"\r\n|\r|\n", " ", s).strip()


def fail(msg):
    sys.stderr.write("[amend_task] %s\n" % msg)
    sys.exit(1)


def parse_args(argv):
    p = argparse.ArgumentParser(
        prog="amend_task.py", description="タスク票の成果物の追加と受け入れ基準の差し替え"
    )
    p.add_argument("plan_id")
    p.add_argument("task_id")
    p.add_argument("--add-deliverable", dest="ops_add", action="append", default=[],
                   metavar="PATH", help="「成果物」に宣言を足すパス（複数回指定可）")
    p.add_argument("--replace-criterion", dest="ops_rep", action="append", default=[], nargs=2,
                   metavar=("N", "TEXT"), help="受け入れ基準の N 番目の行を差し替える（複数回指定可）")
    p.add_argument("--note", default=None)
    # 指定順を保つため、argv を自分で走査して適用順を決める
    args = p.parse_args(argv)
    if not args.ops_add and not args.ops_rep:
        p.error("--add-deliverable か --replace-criterion を1つ以上指定します")
    reps = []
    for n, text in args.ops_rep:
        try:
            reps.append((int(n), text))
        except ValueError:
            p.error("--replace-criterion の番号が整数ではありません: %s" % n)
    args.ops_rep = reps
    args.ops = order_ops(argv, args)
    args.note_text = transition.clean_text(args.note) if args.note is not None else ""
    return args


def order_ops(argv, args):
    """argv に現れた順の操作のリスト [("add", パス) | ("rep", 番号, 文)] を返す。"""
    adds = list(args.ops_add)
    reps = list(args.ops_rep)
    ops = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--add-deliverable" and adds:
            ops.append(("add", adds.pop(0)))
            i += 2
        elif a == "--replace-criterion" and reps:
            n, t = reps.pop(0)
            ops.append(("rep", n, t))
            i += 3
        elif a == "--note":
            i += 2
        else:
            i += 1
    # 解析の取りこぼし（--opt=value の形など）は末尾に回す
    ops += [("add", x) for x in adds] + [("rep", n, t) for n, t in reps]
    return ops


def section_range(lines, heading):
    """見出し行の次の行から次の `## ` の手前までの (開始, 終了) を返す。見出しが無ければ None。"""
    start = None
    for i, line in enumerate(lines):
        if line.startswith("## "):
            if start is not None:
                return (start, i)
            if line.rstrip() == heading:
                start = i + 1
    if start is None:
        return None
    return (start, len(lines))


def declared_paths(lines, rng):
    found = []
    for line in lines[rng[0]:rng[1]]:
        for m in re.finditer(r"`([^`\n]+)`", line):
            c = m.group(1).strip()
            if c:
                found.append(c)
    return found


def main(argv):
    args = parse_args(argv)
    plan_id, tid = args.plan_id, args.task_id

    r = transition.run_git(os.getcwd(), "rev-parse", "--show-toplevel")
    if r.returncode != 0 or not r.stdout.strip():
        fail("git リポジトリではありません")
    root = r.stdout.strip()

    plan_rel = "vault/plans/%s.md" % plan_id
    log_rel = "vault/log/%s.md" % plan_id
    task_rel = "vault/tasks/%s/%s.md" % (plan_id, tid)

    try:
        plan_text = transition.read_bytes(os.path.join(root, plan_rel)).decode("utf-8")
    except (OSError, UnicodeDecodeError):
        fail("計画票を読めません: %s" % plan_rel)
    if _hooklib.frontmatter_status(plan_text) != "approved":
        fail("計画票 %s の status が approved ではありません" % plan_rel)

    r = transition.run_git(root, "rev-parse", "--abbrev-ref", "HEAD")
    branch = r.stdout.strip()
    expected = "work/" + plan_id.lower()
    if r.returncode != 0 or branch != expected:
        fail("現在のブランチ %r が %r ではありません" % (branch, expected))

    row = None
    for t in _hooklib.parse_tasks(plan_text):
        if t["id"] == tid:
            row = t
            break
    if row is None:
        fail("%s はタスク表にありません" % tid)
    if row["status"] not in ALLOWED_STATUS:
        fail("%s: status が %s です（blocked か todo の時だけ直せます）" % (tid, row["status"]))

    try:
        task_text = transition.read_bytes(os.path.join(root, task_rel)).decode("utf-8")
    except (OSError, UnicodeDecodeError):
        fail("タスク票を読めません: %s" % task_rel)
    lines = task_text.splitlines(True)
    if section_range(lines, "## 成果物") is None:
        fail("タスク票に「## 成果物」の見出しがありません")
    if section_range(lines, "## 受け入れ基準") is None:
        fail("タスク票に「## 受け入れ基準」の見出しがありません")

    n_crit = _hooklib.count_criteria(task_text)
    for op in args.ops:
        if op[0] == "rep" and not (1 <= op[1] <= n_crit):
            fail("--replace-criterion の番号 %d が範囲外です（1〜%d）" % (op[1], n_crit))
        if op[0] == "add":
            if op[1].strip() == "" or "`" in op[1] or "\n" in op[1]:
                fail("--add-deliverable のパスが不正です: %r" % op[1])
            if op[1].startswith(FORBIDDEN_PREFIXES):
                fail("--add-deliverable のパス %s は宣言しても差分ゲートが違反にします" % op[1])

    out = []
    summary = []
    for op in args.ops:
        if op[0] == "add":
            path = op[1]
            rng = section_range(lines, "## 成果物")
            if path in declared_paths(lines, rng):
                out.append("skip %s（宣言済み）" % path)
                continue
            last = None
            for i in range(rng[0], rng[1]):
                if lines[i].strip():
                    last = i
            if last is None:
                last = rng[0] - 1
            if last >= 0 and not lines[last].endswith(("\n", "\r")):
                lines[last] += "\n"
            lines.insert(last + 1, "- `%s`（amend_task.py で追加）\n" % path)
            out.append("add %s" % path)
            summary.append("成果物追加=%s" % path)
        else:
            num, text = op[1], op[2]
            rng = section_range(lines, "## 受け入れ基準")
            seen = 0
            for i in range(rng[0], rng[1]):
                if CRITERION_RE.match(lines[i]):
                    seen += 1
                    if seen == num:
                        body = lines[i].rstrip("\r\n")
                        eol = lines[i][len(body):] or "\n"
                        lines[i] = "- %s%s" % (criterion_text(text), eol)
                        break
            out.append("replace criterion %d" % num)
            summary.append("基準差し替え=%d" % num)

    if summary:
        if args.note_text:
            summary.append(args.note_text)
        log_line = "- %s %s amend %s" % (transition.now_jst(), tid, " ".join(summary))
        log_path = os.path.join(root, log_rel)
        new_log, _before = transition.log_with_lines(log_path, [log_line])
        new_task = "".join(lines).encode("utf-8")
        transition.commit_files(
            root, [(task_rel, new_task), (log_rel, new_log)],
            "%s/%s: amend" % (plan_id, tid), [task_rel, log_rel],
        )
    for line in out:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
