#!/usr/bin/env python3
"""作業ブランチの差分を、base の版のタスク票の「成果物」と照らし合わせる（D-012 フェーズ3）。

使い方:
    python3 scripts/diff_gate.py <計画ID> <id> <base> <branch>

対象リポジトリは実行時のカレントディレクトリの `git rev-parse --show-toplevel`。
見るのは `git diff <base> <branch>` のコミット済みの差分だけ（未コミット・未追跡は対象外）。
リポジトリの状態は変えない（読むだけ）。

宣言: base の版の vault/tasks/<計画ID>/<id>.md の「## 成果物」節にあるバッククォートで
囲まれた文字列。末尾が `/` なら前方一致、それ以外は完全一致。

判定（1つのパスに理由は1つ。最初に当たったものを使う）:
  1. vault/plans/・vault/log/・vault/verdicts/・vault/rules/ 配下 -> 違反（宣言があっても）
  2. 自分のタスク票 -> 「## 進捗」以外の節が base と同じなら許す。違えば違反
  3. 宣言に一致 -> 許す
  4. それ以外 -> 違反

違反1件につき標準出力に `<パス>: <理由>` を1行出す。import して
`check(root, plan_id, task_id, base, branch)` で `[(パス, 理由), ...]` を得られる。
base/branch が解決できない・base にタスク票が無い・git が失敗した時は GateError。

終了コード:
    0  違反なし
    1  違反あり
    2  引数の誤り・base にタスク票が無い・git コマンドが失敗した
"""
import sys

sys.dont_write_bytecode = True

import argparse
import re
import subprocess

FORBIDDEN_PREFIXES = ("vault/plans/", "vault/log/", "vault/verdicts/", "vault/rules/")
REASON_FORBIDDEN = "%s 配下は宣言があっても変更できない"
REASON_TASK = "タスク票の「進捗」以外の節が変わっている"
REASON_UNDECLARED = "「成果物」に宣言されていない"


class GateError(Exception):
    pass


def _git(root, args):
    try:
        proc = subprocess.run(
            ["git", "-C", root] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        raise GateError("git を実行できません: %s" % exc)
    return proc


def _git_ok(root, args):
    proc = _git(root, args)
    if proc.returncode != 0:
        msg = proc.stderr.decode("utf-8", "replace").strip()
        raise GateError("git %s に失敗しました: %s" % (" ".join(args), msg))
    return proc.stdout


def _verify_commit(root, ref):
    proc = _git(root, ["rev-parse", "--verify", "--quiet", ref + "^{commit}"])
    if proc.returncode != 0:
        raise GateError("コミットとして解決できません: %s" % ref)


def _split_sections(text):
    """`## ` 見出しで (見出し, 本文) の並びに分ける。先頭の見出し前は見出し None。"""
    sections = []
    heading = None
    body = []
    for line in text.split("\n"):
        if line.startswith("## "):
            sections.append((heading, "\n".join(body)))
            heading = line.rstrip()
            body = []
        else:
            body.append(line)
    sections.append((heading, "\n".join(body)))
    return sections


def _declared(text):
    cands = []
    for heading, body in _split_sections(text):
        if heading != "## 成果物":
            continue
        for m in re.finditer(r"`([^`\n]+)`", body):
            c = m.group(1).strip()
            if c:
                cands.append(c)
    return cands


def _matches(path, cands):
    for c in cands:
        if c.endswith("/"):
            if path.startswith(c):
                return True
        elif path == c:
            return True
    return False


def _non_progress(text):
    return [s for s in _split_sections(text) if s[0] != "## 進捗"]


def _show(root, ref, path):
    proc = _git(root, ["show", "%s:%s" % (ref, path)])
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8")


def check(root, plan_id, task_id, base, branch):
    _verify_commit(root, base)
    _verify_commit(root, branch)
    task_path = "vault/tasks/%s/%s.md" % (plan_id, task_id)
    base_text = _show(root, base, task_path)
    if base_text is None:
        raise GateError("base (%s) にタスク票がありません: %s" % (base, task_path))
    cands = _declared(base_text)
    out = _git_ok(
        root,
        ["-c", "core.quotePath=false", "diff", "--name-only", "--no-renames", "-z", base, branch],
    )
    paths = [p for p in out.decode("utf-8").split("\0") if p]
    violations = []
    for p in paths:
        reason = None
        prefix = next((x for x in FORBIDDEN_PREFIXES if p.startswith(x)), None)
        if prefix:
            reason = REASON_FORBIDDEN % prefix
        elif p == task_path:
            branch_text = _show(root, branch, task_path)
            if branch_text is None or _non_progress(base_text) != _non_progress(branch_text):
                reason = REASON_TASK
        elif not _matches(p, cands):
            reason = REASON_UNDECLARED
        if reason:
            violations.append((p, reason))
    return violations


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="diff_gate.py",
        description="作業ブランチの差分を base の版のタスク票の「成果物」と照らし合わせる",
    )
    parser.add_argument("plan_id")
    parser.add_argument("task_id")
    parser.add_argument("base")
    parser.add_argument("branch")
    args = parser.parse_args(argv)
    try:
        try:
            proc = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        except OSError as exc:
            raise GateError("git を実行できません: %s" % exc)
        if proc.returncode != 0:
            raise GateError("git リポジトリではありません")
        root = proc.stdout.decode("utf-8").strip()
        violations = check(root, args.plan_id, args.task_id, args.base, args.branch)
    except GateError as exc:
        sys.stderr.write("[diff_gate] %s\n" % exc)
        return 2
    for path, reason in violations:
        sys.stdout.write("%s: %s\n" % (path, reason))
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
