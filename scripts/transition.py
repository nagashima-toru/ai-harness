#!/usr/bin/env python3
"""計画票のタスク表の状態遷移を1コマンドで行う（D-012 フェーズ2・フェーズ4）。

使い方:
    python3 scripts/transition.py <計画ID> <id>[,<id>...] <遷移先>
        [--question <文> | --question-file <パス>] [--note <補足>] [--no-model]
        [--worktree <パス> --branch <ブランチ> --plan-head <sha>]

やること（すべての id の検査を先に済ませ、通った時だけ行う）:
  1. 計画票 vault/plans/<計画ID>.md のタスク表の status・attempt・question を書き換える
  2. vault/log/<計画ID>.md に `- <日時> <id> <旧>→<新> attempt=<n>[ <補足>]` を id の順に追記する
     （日時は UTC+9 固定のスクリプトの実時刻）
  3. 計画票と log だけを `git commit` する（ほかに staged な変更があっても混ぜない）

遷移表は todo→doing・doing→doing・doing→review・doing→blocked・review→done・
review→doing・review→blocked の7つだけ。承認と blocked の解除は扱わない。
review→done は、各 id に正しい PASS の verdict があり（_hooklib.done_rows_without_pass）
attempt が一致する時だけ行い、verdict もコミットに含める。
doing→review・doing→blocked の行に creator=<model>、review→done・review→doing・
review→blocked の行に verifier=<model> を付ける（対象リポジトリの .claude/agents/<name>.md の
frontmatter の model。無ければ付けない）。`--no-model` で付けない。

--worktree（フェーズ4。今は遷移先 review だけ。id は1つ）:
  creator が作業した worktree を渡すと、review の前の処理を1コマンドで行う。
  --worktree と --branch は両方そろえ、review では --plan-head も必須。--note は下で決まる
  自動の補足の後ろに付く。
  検査（どれかに当たれば何も変えず終了コード1）: フェーズ2の検査、worktree とブランチの検証
  （ブランチ名が worktree-agent- で始まる・git worktree list にそのパスがありブランチが
  一致する。scripts/discard_worktree.sh と同じ条件）、--plan-head が40桁の sha に解決できる。
  1. worktree の未コミット分があれば git add -A して
     `<計画ID>/<id>: creator 成果物をオーケストレーターが収集` でコミットする
  2. plan_head..branch の新規コミットが無ければ doing→blocked にして worktree を残す（終了コード4）
  3. scripts/diff_gate.py の check で宣言外の変更を調べる（GateError は終了コード1）
  4. 違反なし: log に `<id> worktree path=<realpath> branch=<ブランチ> plan_head=<sha>` の
     記録行と doing→review の行を書いてコミットする（終了コード0）
  5. 違反あり: attempt+1 が HARNESS_MAX_ATTEMPTS 以内なら、タスク票の「進捗」に差し戻しの
     1行を足し、doing→doing（attempt+1）にして worktree とブランチを破棄する（終了コード3）。
     超えるなら doing→blocked にして worktree を残す（終了コード4）

終了コード:
    0  review／done にした
    1  前提を満たさず何も変えていない（理由は標準エラーに `[transition] ` で出す）
    2  引数の誤り
    3  差し戻した（doing→doing。creator を呼び直す）
    4  blocked にした
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
BRANCH_PREFIX = "worktree-agent-"


# モデルを記録する遷移 -> 行のキー名（agents のファイル名と同じ）
MODEL_AGENT = {
    ("doing", "review"): "creator",
    ("doing", "blocked"): "creator",
    ("review", "done"): "verifier",
    ("review", "doing"): "verifier",
    ("review", "blocked"): "verifier",
}


def agent_model(root, name):
    """対象リポジトリの .claude/agents/<name>.md の frontmatter の model。取れなければ None。"""
    try:
        with open(os.path.join(root, ".claude", "agents", name + ".md"), encoding="utf-8") as f:
            return _hooklib.frontmatter_value(f.read(), "model")
    except (OSError, UnicodeDecodeError):
        return None


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
    p.add_argument("--worktree", default=None)
    p.add_argument("--branch", default=None)
    p.add_argument("--plan-head", dest="plan_head", default=None)
    args = p.parse_args(argv)

    ids = [x.strip() for x in args.ids.split(",")]
    if any(x == "" for x in ids) or len(set(ids)) != len(ids):
        p.error("id の指定が不正です（空の要素または重複）: %s" % args.ids)
    args.id_list = ids

    if args.worktree is None:
        if args.branch is not None or args.plan_head is not None:
            p.error("--branch／--plan-head は --worktree と一緒に指定します")
    else:
        if args.branch is None:
            p.error("--worktree には --branch も指定します")
        if len(ids) != 1:
            p.error("--worktree を使う時の id は1つだけです")
        if args.target != "review":
            p.error(
                "--worktree は遷移先 review にだけ対応しています（%s はまだ対応していません）"
                % args.target
            )
        if args.plan_head is None:
            p.error("review で --worktree を使う時は --plan-head が必要です")

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


# ---- 共通部品（フェーズ2の書き換え・コミットと、フェーズ4の worktree 用） ----


def now_jst():
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime(
        "%Y-%m-%d %H:%M"
    )


def rewrite_rows(plan_lines, positions, plans, question_text):
    """plans: (id, old, new, attempt)。計画票の行を書き換えた全文（bytes）を返す。"""
    new_lines = list(plan_lines)
    for tid, _old, new, attempt in plans:
        i = positions[tid]
        line = plan_lines[i]
        body = line.rstrip("\r\n")
        eol = line[len(body):]
        indent = body[: len(body) - len(body.lstrip())]
        cells = [c.strip() for c in body.strip().strip("|").split("|")]
        cells = cells + [""] * (6 - len(cells))
        question = question_text if new == "blocked" else ""
        row = "| %s | %s | %d | %s | %s |" % (cells[0], new, attempt, cells[3], cells[4])
        row += (" %s |" % question) if question else " |"
        new_lines[i] = indent + row + eol
    return "".join(new_lines).encode("utf-8")


def log_with_lines(log_path, lines):
    """log の現在の中身に lines（改行なしの文字列のリスト）を足した bytes と、元の bytes を返す。"""
    existed = os.path.exists(log_path)
    before = read_bytes(log_path) if existed else b""
    add = ""
    if existed and before and not before.endswith(b"\n"):
        add = "\n"
    for line in lines:
        add += line + "\n"
    return before + add.encode("utf-8"), before


def commit_files(root, files, subject, paths):
    """files: (相対パス, 新しい bytes) のリストを書き、paths だけを1回でコミットする。

    失敗したら書いたファイルを元に戻して終了コード1（fail）。
    """
    saved = []  # (絶対パス, 元の bytes または None)
    created_dirs = []
    err = ""
    try:
        for rel, data in files:
            path = os.path.join(root, rel)
            saved.append((path, read_bytes(path) if os.path.exists(path) else None))
        for rel, data in files:
            path = os.path.join(root, rel)
            d = os.path.dirname(path)
            if not os.path.isdir(d):
                os.makedirs(d)
                created_dirs.append(d)
            with open(path, "wb") as f:
                f.write(data)
        r = run_git(root, "add", "--", *paths)
        if r.returncode == 0:
            r = run_git(root, "commit", "-q", "-m", subject, "--", *paths)
        if r.returncode != 0:
            err = r.stderr
    except OSError as exc:
        err = str(exc)

    if err:
        for path, before in saved:
            try:
                if before is not None:
                    with open(path, "wb") as f:
                        f.write(before)
                elif os.path.exists(path):
                    os.remove(path)
            except OSError:
                pass
        for d in reversed(created_dirs):
            try:
                os.rmdir(d)
            except OSError:
                pass
        run_git(root, "reset", "-q", "--", *paths)
        fail("git の操作に失敗したため元に戻しました: %s" % err.strip())


def verify_worktree(root, worktree, branch):
    """discard_worktree.sh と同じ条件で検証し、realpath を返す。通らなければ fail。"""
    if not branch.startswith(BRANCH_PREFIX):
        fail("ブランチ名が '%s' で始まっていません: %s" % (BRANCH_PREFIX, branch))
    target = os.path.realpath(worktree)
    r = run_git(root, "worktree", "list", "--porcelain")
    if r.returncode != 0:
        fail("git worktree list に失敗しました: %s" % r.stderr.strip())
    found = False
    matching = False
    actual = ""
    for line in r.stdout.splitlines():
        if line.startswith("worktree "):
            matching = os.path.realpath(line[len("worktree "):]) == target
            if matching:
                found = True
                actual = ""
        elif line.startswith("branch refs/heads/") and matching:
            actual = line[len("branch refs/heads/"):]
    if not found:
        fail("指定パスは登録済み worktree ではありません: %s" % target)
    if actual != branch:
        fail("登録済み worktree のブランチが指定と一致しません: 実際=%s 指定=%s" % (actual, branch))
    return target


def resolve_commit(root, ref):
    r = run_git(root, "rev-parse", "--verify", "--quiet", ref + "^{commit}")
    sha = r.stdout.strip()
    if r.returncode != 0 or len(sha) != 40:
        fail("--plan-head を commit に解決できません: %s" % ref)
    return sha


def collect_worktree(worktree, plan_id, tid):
    """worktree の未コミット分があればコミットする。失敗したら index を戻して fail。"""
    r = run_git(worktree, "status", "--porcelain")
    if r.returncode != 0:
        fail("worktree の git status に失敗しました: %s" % r.stderr.strip())
    if not r.stdout.strip():
        return
    msg = "%s/%s: creator 成果物をオーケストレーターが収集" % (plan_id, tid)
    r = run_git(worktree, "add", "-A")
    if r.returncode == 0:
        r = run_git(worktree, "commit", "-q", "-m", msg)
    if r.returncode != 0:
        err = r.stderr.strip()
        run_git(worktree, "reset", "-q")
        fail("worktree の収集コミットに失敗しました: %s" % err)


def count_new_commits(root, plan_head, branch):
    r = run_git(root, "rev-list", "--count", "%s..%s" % (plan_head, branch))
    try:
        if r.returncode != 0:
            raise ValueError(r.stderr)
        return int(r.stdout.strip())
    except ValueError:
        fail("新規コミットの数を数えられません: %s" % r.stderr.strip())


def run_diff_gate(root, plan_id, tid, plan_head, branch):
    """宣言外の変更を [(パス, 理由), ...] で返す。解決できなければ fail。"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import diff_gate
    except Exception as exc:  # noqa: BLE001
        fail("diff_gate を import できません: %s" % exc)
    try:
        return diff_gate.check(root, plan_id, tid, plan_head, branch)
    except diff_gate.GateError as exc:
        fail("差分ゲートを実行できません: %s" % exc)


def discard_worktree(root, worktree, branch):
    """worktree とブランチを破棄する。失敗したら警告を出して False。"""
    ok = True
    r = run_git(root, "worktree", "remove", "--force", worktree)
    if r.returncode != 0:
        sys.stderr.write("[transition] worktree の破棄に失敗しました: %s\n" % r.stderr.strip())
        ok = False
    r = run_git(root, "branch", "-D", branch)
    if r.returncode != 0:
        sys.stderr.write("[transition] ブランチの破棄に失敗しました: %s\n" % r.stderr.strip())
        ok = False
    return ok


def worktree_record(now, tid, path, branch, plan_head):
    return "- %s %s worktree path=%s branch=%s plan_head=%s" % (now, tid, path, branch, plan_head)


def transition_line(now, tid, old, new, attempt, model, note):
    line = "- %s %s %s→%s attempt=%d" % (now, tid, old, new, attempt)
    if model:
        line += " %s=%s" % (MODEL_AGENT[(old, new)], model)
    if note:
        line += " " + note
    return line


def review_with_worktree(args, root, plan_id, plan_rel, log_rel, plan_bytes, plan_lines,
                         positions, tid, cur, model):
    """--worktree 付きの doing→review。終了コードを返す。"""
    worktree = verify_worktree(root, args.worktree, args.branch)
    plan_head = resolve_commit(root, args.plan_head)
    branch = args.branch
    plan_path = os.path.join(root, plan_rel)
    log_path = os.path.join(root, log_rel)

    collect_worktree(worktree, plan_id, tid)

    violations = None
    if count_new_commits(root, plan_head, branch) > 0:
        violations = run_diff_gate(root, plan_id, tid, plan_head, branch)
        paths_text = ", ".join(v[0] for v in violations)
    now = now_jst()
    record = worktree_record(now, tid, worktree, branch, plan_head)
    limit = max_attempts()

    def finish(old, new, attempt, question, note, extra_files, discard):
        new_plan = rewrite_rows(plan_lines, positions, [(tid, old, new, attempt)], question)
        user_note = args.note_text
        full_note = (note + " " + user_note).strip() if user_note else note
        m = model if (old, new) in MODEL_AGENT else None
        lines = [] if discard else [record]
        lines.append(transition_line(now, tid, old, new, attempt, m, full_note))
        new_log, _before = log_with_lines(log_path, lines)
        files = [(plan_rel, new_plan), (log_rel, new_log)] + extra_files
        paths = [f[0] for f in files]
        commit_files(root, files, "%s/%s: %s→%s" % (plan_id, tid, old, new), paths)
        return note

    if violations is None:
        # 新規コミット無し
        question = clean_text("worktree に新規コミットが無い（マージ対象の差分が無い）")
        finish("doing", "blocked", cur, question, "新規コミット無し", [], False)
        print("%s/%s: doing→blocked attempt=%d %s。worktree を残した" % (plan_id, tid, cur, question))
        return 4

    if not violations:
        finish("doing", "review", cur, "", "", [], False)
        print("%s/%s: doing→review attempt=%d" % (plan_id, tid, cur))
        return 0

    note = clean_text("宣言外の変更: %s" % paths_text)
    progress_line = clean_text("- 差し戻し（attempt=%d）: 宣言外の変更 %s" % (cur, paths_text))
    task_rel = "vault/tasks/%s/%s.md" % (plan_id, tid)
    try:
        task_bytes = read_bytes(os.path.join(root, task_rel))
    except OSError as exc:
        fail("タスク票を読めません: %s (%s)" % (task_rel, exc))
    if task_bytes and not task_bytes.endswith(b"\n"):
        task_bytes += b"\n"
    task_new = task_bytes + (progress_line + "\n").encode("utf-8")

    if cur + 1 <= limit:
        finish("doing", "doing", cur + 1, "", note, [(task_rel, task_new)], True)
        ok = discard_worktree(root, worktree, branch)
        print("%s/%s: doing→doing attempt=%d %s。worktree を破棄した" % (plan_id, tid, cur + 1, note))
        return 3

    finish("doing", "blocked", cur, note, note, [(task_rel, task_new)], False)
    print("%s/%s: doing→blocked attempt=%d %s。worktree を残した" % (plan_id, tid, cur, note))
    return 4


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
    cur_attempts = {}
    for tid in args.id_list:
        if tid not in by_id or tid not in positions:
            fail("%s はタスク表にありません" % tid)
        row = by_id[tid]
        old = row["status"]
        olds.add(old)
        if (old, target) not in TRANSITIONS:
            fail("%s: %s→%s は遷移表にありません" % (tid, old, target))
        try:
            cur = int(row["attempt"])
        except ValueError:
            fail("%s: attempt が整数ではありません: %r" % (tid, row["attempt"]))
        cur_attempts[tid] = cur
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

    if (old_all, target) == ("review", "done"):
        done_rows = []
        for tid, _old, _new, _attempt in plans:
            row = dict(by_id[tid])
            row["status"] = "done"
            done_rows.append(row)
        bad = _hooklib.done_rows_without_pass(root, plan_id, done_rows)
        if bad:
            for tid, reason in bad:
                sys.stderr.write("[transition] %s/%s: %s\n" % (plan_id, tid, reason))
            sys.exit(1)

    model = None
    if not args.no_model:
        if (old_all, target) in MODEL_AGENT:
            model = agent_model(root, MODEL_AGENT[(old_all, target)])
        elif args.worktree is not None:
            model = agent_model(root, "creator")

    if args.worktree is not None:
        tid = args.id_list[0]
        return review_with_worktree(
            args, root, plan_id, plan_rel, log_rel, plan_bytes, plan_lines, positions,
            tid, cur_attempts[tid], model,
        )

    # 書き換え
    new_plan_bytes = rewrite_rows(plan_lines, positions, plans, args.question_text)
    now = now_jst()
    lines = [
        transition_line(now, tid, old, new, attempt, model, args.note_text)
        for tid, old, new, attempt in plans
    ]
    new_log_bytes, _before = log_with_lines(log_path, lines)

    paths = [plan_rel, log_rel]
    if (old_all, target) == ("review", "done"):
        paths += ["vault/verdicts/%s/%s.json" % (plan_id, tid) for tid in args.id_list]
    subject = "%s/%s: %s→%s" % (plan_id, ",".join(args.id_list), old_all, target)

    commit_files(root, [(plan_rel, new_plan_bytes), (log_rel, new_log_bytes)], subject, paths)

    for tid, old, new, attempt in plans:
        print("%s/%s: %s→%s attempt=%d" % (plan_id, tid, old, new, attempt))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
