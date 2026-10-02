#!/usr/bin/env python3
"""PreToolUse フック：サブエージェントごとに書き込み先を制限する。

- verifier : vault/verdicts/ 配下のみ
- planner  : vault/plans/ と vault/tasks/ 配下のみ
対象ツール : Write / Edit / MultiEdit / NotebookEdit（パス判定）、Bash（`analyze_bash_writes` で解析できた時は
             実際の書き込み対象で判定し、解析できない時は従来のリダイレクト・破壊的コマンドの簡易判定）
メインエージェントや他のサブエージェントには何もしない。

改ざん防止：上記とは別に、agent_type を問わず（メインエージェント含む）vault/rules/ 配下への
書き込みを常に拒否する。タスクの状態（todo/doing/review）や承認済み計画の有無は問わない。
作成エージェントがタスク中にルールを書き換え、verifier の判定基準を自分で緩めるのを防ぐ。
ルール変更を成果物とするタスクは、実パスではなく vault/tasks/<計画ID>/<id>-proposal.md に
下書きし、verifier はそこを検証する。実体（vault/rules/ 配下）への反映は人が手作業で行う
（docs/vault-spec.md 第12節）。

上記の拒否は、Write 系ツールのパス判定に加え、Bash 経由で `gh api` や GitHub Contents API
（api.github.com / raw.githubusercontent.com 等）へ直接 curl するリモート書き込み経路も対象にする
（issue #6）。
vault/rules/ と会話記録（~/.claude/projects/）の Bash 判定は、`analyze_bash_writes` で解析できた時だけ
実際の書き込み対象で判定し、解析できない形（コマンド置換・サブシェル・インタプリタ・変数や glob を
含む対象など）は従来の判定（BASH_WRITE_PATTERNS 等）に落とす（fail-closed。issue #91）。
引数・引用符内・ヒアドキュメント本文に文字列があるだけの誤検知を解消するための精密化。

creator（run から呼ばれる作成エージェント）向けの拒否リスト：creator は成果物パス（repo 全体に
及びうる）と vault/tasks/ への書き込みは許可されるが、vault/plans/・vault/log/ への書き込みは
agent_type を問わない他の判定と同じく常に拒否する。計画票のタスク表の状態更新とログ追記は、
呼び出し元のオーケストレーター（run のメインセッション）に一本化するための制限（D-003 フェーズ2）。
ALLOWED の許可リスト方式とは異なり、拒否リスト方式で実装する。
Bash は `analyze_bash_writes` で解析できた時は実際の書き込み対象だけで判定する（解析不能は従来判定）。

done タスクへの書き込み拒否：agent_type を問わず（メインセッション含む）、書き込み先が
vault/tasks/<計画ID>/<id>.md または vault/verdicts/<計画ID>/<id>.json で、対応する計画票
（vault/plans/<計画ID>.md）のタスク表でその id の status が done の場合は拒否する。計画票が
見つからない・その id の行が無い・読めない場合は許可する（fail-open）。タスク表の解析規則は
plan_guard.py の raw_rows と同じものをこのファイル内にコピーして使う（他ファイルへの import は
しない方針を踏襲、D-010 フェーズ2 / issue #76）。解除口は作らない。
ただし Bash の書き込み動詞が git add / git commit だけのコマンドは対象外（ステージ・コミットは
ファイルの内容を変えないため。run/SKILL.md 手順6.3.4 の done 後の add・commit を通す。issue #84）。
他の書き込み動詞・リダイレクト・コマンド置換が混ざる場合は従来どおり拒否する。
解析できた時は `git add`/`git commit` の対象を除いた実際の書き込み対象で判定する（issue #87）。
解析できない形（`$(` 等）は従来の `is_git_stage_or_commit_only` を含む判定に落とす。
"""
import json
import os
import re
import shlex
import subprocess
import sys

GIT_COMMIT_PATTERN = r"\bgit\s+commit\b"
GIT_PREOPT_COMMIT_PATTERN = r"\bgit\s+-[^;&|\n]*\bcommit\b"
GITHUB_API_HOSTS = ("api.github.com", "raw.githubusercontent.com", "githubusercontent.com")

ALLOWED = {
    "verifier": ["vault/verdicts/"],
    "planner": ["vault/plans/", "vault/tasks/"],
}
DENIED_FOR_CREATOR = ("vault/plans/", "vault/log/")
PLAN_TASK_COLUMNS = ("id", "status", "attempt", "after", "title", "question")
TASK_FILE_RE = re.compile(r"^vault/tasks/([^/]+)/([^/]+)\.md$")
VERDICT_FILE_RE = re.compile(r"^vault/verdicts/([^/]+)/([^/]+)\.json$")
BASH_WRITE_PATTERNS = [
    r"(^|[^<>])>{1,2}\s*(?!&)\S",     # リダイレクト（`2>&1` のような N>&M fd 複製は書き込みとみなさない）
    r"\btee\b",
    r"\b(rm|mv|cp|touch|mkdir|chmod|chown)\b",
    r"\bgit\s+(add|commit|push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)\b",
    r"\bsed\s+-i\b",
]
# BASH_WRITE_PATTERNS から、リダイレクトと git add / git commit を除いたもの
# （is_git_stage_or_commit_only が「git add / git commit 以外の書き込み動詞」を見分けるために使う）
OTHER_WRITE_PATTERNS = [
    r"\btee\b",
    r"\b(rm|mv|cp|touch|mkdir|chmod|chown)\b",
    r"\bgit\s+(push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)\b",
    r"\bsed\s+-i\b",
]
SEGMENT_SEPARATORS = (";", "&&", "||", "|", "&")


def mask_angle_placeholders(text):
    """`<...>`（`<`・`>`・空白を含まない区間）を同じ文字数の空白に置換したテキストを返す。

    `<n>`・`<計画ID>` のような plan/task 票の山括弧プレースホルダーの閉じ `>` を、
    シェルのリダイレクトと誤認しないようにするための前処理（issue #54）。書き込み判定にのみ使い、
    deny() のエラーメッセージ表示には元のテキストを使うこと（マスクすると空白だらけで読みにくくなる）。
    """
    return re.sub(r"<[^<>\s]+>", lambda m: " " * len(m.group(0)), text)


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }, ensure_ascii=False))
    sys.exit(0)


def normalize(path, root):
    if not path:
        return ""
    ap = os.path.abspath(os.path.join(root, path)) if not os.path.isabs(path) else os.path.abspath(path)
    ap = os.path.realpath(ap)
    root = os.path.realpath(root)
    rel = os.path.relpath(ap, root)
    return rel.replace(os.sep, "/")


def existing_ancestor(dir_path):
    """dir_path 自身、または存在する祖先ディレクトリまで `os.path.dirname()` で遡って返す。

    worktree 内でまだ作成されていないネストしたディレクトリ配下に書き込もうとした場合、
    `git -C <存在しないpath> rev-parse --show-toplevel` は exit 128 で失敗する（issue #24）。
    worktree のルート自体は常に存在するため、存在するディレクトリまで遡ってから
    `git -C` に渡せば正しく worktree のルートを解決できる。
    """
    if not dir_path:
        return None
    probe = dir_path
    while probe and not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            # ルートまで遡っても見つからない（ほぼ起こらない）場合は諦める
            return None
        probe = parent
    return probe or None


def git_toplevel(dir_path):
    """dir_path から `git rev-parse --show-toplevel` を試みる。

    worktree 内から呼ばれた場合はその worktree のルートを返す。非 git・取得失敗時は None
    （呼び出し側で既存のフォールバック順に進む＝fail-open）。
    """
    if not dir_path:
        return None
    dir_path = existing_ancestor(dir_path)
    if not dir_path:
        return None
    try:
        out = subprocess.run(
            ["git", "-C", dir_path, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    top = out.stdout.strip()
    return top or None


def resolve_root(tool, tool_input, payload):
    """書き込み先パスの正規化に使う root を求める。

    Write/Edit/MultiEdit/NotebookEdit では対象 file_path の親ディレクトリを起点に、
    Bash では payload.cwd を起点に、それぞれ `git rev-parse --show-toplevel` で
    worktree のルートを優先的に求める。取得できない場合のみ既存の
    CLAUDE_PROJECT_DIR → payload.cwd → os.getcwd() の優先順にフォールバックする。
    """
    fallback = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    probe_dir = None
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if path:
            abs_path = path if os.path.isabs(path) else os.path.abspath(os.path.join(fallback, path))
            probe_dir = os.path.dirname(abs_path)
    elif tool == "Bash":
        cwd = payload.get("cwd") or ""
        if cwd:
            probe_dir = cwd
    if probe_dir:
        top = git_toplevel(probe_dir)
        if top:
            return top
    return fallback


def current_branch(root):
    """現在のブランチ名を返す。非 git リポジトリ・エラー・detached HEAD 等は None（fail-open）。"""
    try:
        out = subprocess.run(
            ["git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    branch = out.stdout.strip()
    return branch or None


DESTRUCTIVE_BASH_PATTERN = (
    r"\b(rm|mv|cp|git\s+(add|commit|push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)"
    r"|sed\s+-i|tee)\b"
)


def extract_bash_write_targets(cmd):
    """コマンド文字列からリダイレクト先と mkdir/cp/touch/rm/mv の書き込み対象パスを抽出する。

    フラグ（`-` で始まるトークン）は対象パスに含めない。コマンド区切り（`;`/`&`/`|`）は
    またいで拾わない。`cp`/`mv` は読み取り元（先行する非フラグ引数）を書き込み対象に含めず、
    最後の非フラグ引数（コピー・移動先）だけを対象にする。`mkdir`/`touch`/`rm` は全ての
    非フラグ引数がそれぞれ書き込み（作成・削除）対象になる。抽出できたパスが1つも無ければ
    呼び出し側で fail-closed（拒否）とする。
    """
    cmd = mask_angle_placeholders(cmd)
    targets = re.findall(r">{1,2}\s*([^\s;&|]+)", cmd)
    for m in re.finditer(r"\b(mkdir|cp|touch|rm|mv)\b([^;&|]*)", cmd):
        verb = m.group(1)
        args = [tok for tok in m.group(2).split() if not tok.startswith("-")]
        if not args:
            continue
        if verb in ("cp", "mv"):
            targets.append(args[-1])
        else:
            targets.extend(args)
    return targets


def is_outside_root(path, root):
    """正規化したパスが root の外（root 配下でない）かどうかを返す。"""
    rel = normalize(path, root)
    return rel == ".." or rel.startswith("../")


def targets_vault_rules_remote(cmd):
    """gh api / curl で GitHub Contents API を直接叩き vault/rules/ を書き換えようとしていないか判定する。

    gh api の contents パスは "repos/<owner>/<repo>/contents/vault/rules/..." のように
    先頭に接頭辞が付き、normalize() では "vault/rules/" 始まりと判定できない。そのため
    既存の path 正規化とは別に、コマンド文字列に "vault/rules/" というリテラルが
    含まれるかを直接見る（誤検知より見逃しを避ける方針。D-002 の設計思想を踏襲）。
    """
    if "vault/rules/" not in cmd:
        return False
    if re.search(r"\bgh\s+api\b", cmd):
        return True
    if re.search(r"\bcurl\b", cmd) and any(h in cmd for h in GITHUB_API_HOSTS):
        return True
    return False


class _Unparseable(Exception):
    """analyze_bash_writes が解析を諦める（None を返す）ための内部例外。"""


# 解析しないコマンド語（basename で照合）。サブシェル・インタプリタ・任意コマンドを起動するもの。
UNPARSEABLE_COMMANDS = frozenset((
    "cd", "pushd", "popd", "eval", "exec", "source", ".", "bash", "sh", "zsh", "dash", "env", "sudo",
    "nohup", "time", "timeout", "nice", "command", "builtin", "xargs", "find", "awk", "gawk", "perl",
    "python", "python3", "ruby", "node",
))
# シェルの制御構文の語（コマンド位置に来ると後続のコマンドを見落とすので解析しない）
SHELL_KEYWORDS = frozenset((
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
    "select", "function", "coproc", "{", "}", "!",
))
GIT_WRITE_SUBCOMMANDS = frozenset((
    "rm", "mv", "checkout", "switch", "reset", "restore", "clean", "stash", "merge", "rebase", "push",
))
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
PUNCT_ONLY_RE = re.compile(r"^[();<>|&]+$")
SEPARATOR_RE = re.compile(r"^[;&|]+$")


def _strip_heredocs(cmd):
    """ヒアドキュメント本文を取り除き、引用符外の改行を `;` に置き換えた文字列を返す。

    引用符外の `<<`・`<<-` の区切り語を見つけ、次の行から区切り語だけの行までの本文を捨てる。
    引用符内の改行はそのまま残す。区切り語の行が見つからない・展開される本文（区切り語を引用符で
    囲まない）に `$(` かバッククォートがある場合は _Unparseable。
    """
    out = []
    n = len(cmd)
    i = 0
    quote = None
    pending = []  # (区切り語, <<- か, 区切り語が引用符付きか)
    while i < n:
        c = cmd[i]
        if quote == "'":
            out.append(c)
            if c == "'":
                quote = None
            i += 1
            continue
        if quote == '"':
            if c == "\\" and i + 1 < n:
                out.append(cmd[i:i + 2])
                i += 2
                continue
            out.append(c)
            if c == '"':
                quote = None
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            if cmd[i + 1] == "\n":
                out.append(" ")
            else:
                out.append(cmd[i:i + 2])
            i += 2
            continue
        if c in "'\"":
            quote = c
            out.append(c)
            i += 1
            continue
        if c == "\n":
            out.append(" ; ")
            i += 1
            for delim, dash, quoted in pending:
                found = False
                body = []
                while i < n:
                    e = cmd.find("\n", i)
                    if e < 0:
                        e = n
                    line = cmd[i:e]
                    i = min(e + 1, n)
                    if (line.lstrip("\t") if dash else line) == delim:
                        found = True
                        break
                    body.append(line)
                if not found:
                    raise _Unparseable()
                if not quoted and any("$(" in b or "`" in b for b in body):
                    raise _Unparseable()
            pending = []
            continue
        if c == "<" and cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            j = i + 2
            dash = False
            if j < n and cmd[j] == "-":
                dash = True
                j += 1
            while j < n and cmd[j] in " \t":
                j += 1
            delim = []
            quoted = False
            while j < n and cmd[j] not in " \t\n;&|<>()":
                ch = cmd[j]
                if ch in "'\"":
                    quoted = True
                    k = cmd.find(ch, j + 1)
                    if k < 0:
                        raise _Unparseable()
                    delim.append(cmd[j + 1:k])
                    j = k + 1
                    continue
                if ch == "\\" and j + 1 < n:
                    quoted = True
                    delim.append(cmd[j + 1])
                    j += 2
                    continue
                delim.append(ch)
                j += 1
            word = "".join(delim)
            if not word:
                raise _Unparseable()
            pending.append((word, dash, quoted))
            out.append(cmd[i:i + 2])  # 区切り語本体は次の周回で通常どおり出力される
            i += 2
            continue
        out.append(c)
        i += 1
    if quote is not None or pending:
        raise _Unparseable()
    return "".join(out)


def _split_positional(args):
    """フラグ（`-` で始まるトークン）を除いた引数を返す。`--` の後はすべて引数。"""
    out = []
    after_dd = False
    for a in args:
        if after_dd:
            out.append(a)
        elif a == "--":
            after_dd = True
        elif not a.startswith("-"):
            out.append(a)
    return out


def _copy_move_targets(args):
    """cp / mv の対象（全ての非フラグ引数＋-t <dir>・--target-directory=<dir> の dir）。"""
    tdir = None
    rest = []
    after_dd = False
    k = 0
    while k < len(args):
        a = args[k]
        if after_dd:
            rest.append(a)
        elif a == "--":
            after_dd = True
        elif a == "--target-directory" or (not a.startswith("--") and a.startswith("-") and a.endswith("t")):
            if k + 1 >= len(args):
                raise _Unparseable()
            tdir = args[k + 1]
            k += 1
        elif a.startswith("--target-directory="):
            tdir = a.split("=", 1)[1]
        elif a.startswith("-t") and not a.startswith("--") and len(a) > 2:
            tdir = a[2:]
        elif not a.startswith("-"):
            rest.append(a)
        k += 1
    if tdir is not None:
        rest.append(tdir)
    return rest


def _segment_writes(words, redirects, writes):
    """1セグメント（コマンド語＋引数）の書き込みを writes に追加する。解析できなければ _Unparseable。"""
    for r in redirects:
        writes.append(("redirect", r))
    idx = 0
    while idx < len(words) and ASSIGNMENT_RE.match(words[idx]):
        idx += 1
    if idx >= len(words):
        return
    cmd_word = words[idx]
    args = words[idx + 1:]
    if "$" in cmd_word:
        raise _Unparseable()
    base = os.path.basename(cmd_word)
    if cmd_word in SHELL_KEYWORDS or base in SHELL_KEYWORDS or base in UNPARSEABLE_COMMANDS:
        raise _Unparseable()
    if base == "git":
        if not args:
            return
        if args[0].startswith("-"):
            raise _Unparseable()
        sub, rest = args[0], args[1:]
        if sub == "add":
            for t in _split_positional(rest) or [""]:
                writes.append(("git-add", t))
        elif sub == "commit":
            writes.append(("git-commit", ""))
        elif sub in GIT_WRITE_SUBCOMMANDS:
            for t in _split_positional(rest) or [""]:
                writes.append(("git-write", t))
        return
    if base == "tee":
        writes.extend(("tee", t) for t in _split_positional(args))
    elif base == "sed":
        before_dd = args[:args.index("--")] if "--" in args else args
        in_place = any(
            a == "--in-place" or a.startswith("--in-place=")
            or (a.startswith("-") and not a.startswith("--") and "i" in a)
            for a in before_dd
        )
        if in_place:
            writes.extend(("sed-i", t) for t in _split_positional(args))
    elif base in ("cp", "mv"):
        # 人の回答（A）：全ての非フラグ引数を対象にする。-t <dir>・--target-directory=<dir> は dir も対象にする
        writes.extend((base, t) for t in _copy_move_targets(args))
    elif base in ("rm", "mkdir", "touch", "chmod", "chown"):
        writes.extend((base, t) for t in _split_positional(args))


def analyze_bash_writes(cmd):
    """Bash コマンド文字列を shlex で解析し、実際の書き込み対象 [(verb, target), ...] を返す（issue #91）。

    書き込みが無ければ空リスト。解析できない形は None（呼び出し側は従来の判定に落とす＝fail-closed）：
    コマンド置換・プロセス置換・サブシェル・シェルの制御構文・インタプリタや任意コマンドを起動する
    コマンド語・変数や glob を含む書き込み対象・shlex が読めない形・区切り語の無いヒアドキュメント。
    ヒアドキュメント本文と引用符内の文字列は書き込み対象にしない。verb は redirect・tee・sed-i・
    cp・mv・rm・mkdir・touch・chmod・chown・git-add・git-commit・git-write。
    """
    try:
        text = _strip_heredocs(cmd)
        if any(s in text for s in ("$(", "`", "<(", ">(")):
            return None
        lex = shlex.shlex(text, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
        writes = []
        words, redirects = [], []

        def flush():
            if words or redirects:
                _segment_writes(words, redirects, writes)
            words.clear()
            redirects.clear()

        i = 0
        while i < len(tokens):
            tok = tokens[i]
            if not PUNCT_ONLY_RE.match(tok):
                words.append(tok)
                i += 1
                continue
            if "(" in tok or ")" in tok:
                return None
            if SEPARATOR_RE.match(tok):
                if tok not in (";", "&&", "||", "|", "|&", "&"):
                    return None
                flush()
                i += 1
                continue
            nxt = tokens[i + 1] if i + 1 < len(tokens) else None
            if tok in (">", ">>", ">|", "&>", "&>>", ">&", "<", "<&", "<<", "<<-", "<<<"):
                if nxt is None or PUNCT_ONLY_RE.match(nxt):
                    return None
                # `2>` のような前置の fd 番号は別トークンになるので、引数から外す
                if tok.startswith((">", "&>")) and words and words[-1].isdigit():
                    words.pop()
                if tok in (">", ">>", ">|", "&>", "&>>"):
                    redirects.append(nxt)
                elif tok == ">&" and not re.fullmatch(r"\d+-?|-", nxt):
                    redirects.append(nxt)
                i += 2
                continue
            return None
        flush()
        for _, target in writes:
            if any(ch in target for ch in "$*?[{"):
                return None
        return writes
    except (_Unparseable, ValueError):
        return None


def _legacy_targets_vault_rules_bash(cmd, root):
    """従来の Bash 判定（解析できない形のフォールバック）。"""
    masked = mask_angle_placeholders(cmd)
    if not any(re.search(p, masked) for p in BASH_WRITE_PATTERNS):
        return False
    redirect_targets = re.findall(r">{1,2}\s*([^\s;&|]+)", masked)
    path_like = re.findall(r"[^\s'\"]*vault/rules/[^\s'\"]*", cmd)
    candidates = redirect_targets + path_like
    return any(normalize(t, root).startswith("vault/rules/") for t in candidates)


def targets_vault_rules(tool, tool_input, root):
    """この呼び出しが vault/rules/ 配下への書き込みを試みているか判定する。

    Bash は analyze_bash_writes で解析できた時だけ実際の書き込み対象で判定し、
    None（解析不能）の時は従来の判定に落とす（issue #91）。
    """
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        return normalize(path, root).startswith("vault/rules/")
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if targets_vault_rules_remote(cmd):
            return True
        writes = analyze_bash_writes(cmd)
        if writes is None:
            return _legacy_targets_vault_rules_bash(cmd, root)
        return any(normalize(t, root).startswith("vault/rules/") for _, t in writes if t)
    return False


def transcript_dir():
    """会話記録の置き場 ~/.claude/projects/（末尾 `/` 付き。projects-x などを誤検出しない）を返す。"""
    return os.path.realpath(os.path.expanduser("~/.claude/projects")) + "/"


def is_under_transcript_dir(path, root):
    """path（`~` 表記・絶対・相対）を展開・正規化して ~/.claude/projects/ 配下か判定する。"""
    if not path:
        return False
    expanded = os.path.expanduser(path)
    if not os.path.isabs(expanded):
        expanded = os.path.join(root, expanded)
    ap = os.path.realpath(os.path.abspath(expanded))
    base = transcript_dir()
    return ap + "/" == base or ap.startswith(base)


def targets_transcript_dir(tool, tool_input, root):
    """この呼び出しが ~/.claude/projects/ 配下（会話記録）への書き込みを試みているか判定する（D-010 フェーズ4）。

    承認の裏付けにする会話記録をエージェントが書き換えて人の発言を偽造するのを防ぐ。
    Bash は analyze_bash_writes で解析できた時だけ実際の書き込み対象で判定する。None（解析不能）の時は
    従来の判定：BASH_WRITE_PATTERNS で書き込み動詞を判定し、対象は extract_bash_write_targets と
    `.claude/projects/` を含む path-like トークンから求める（読み取り専用コマンドは対象外）。
    """
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        return is_under_transcript_dir(path, root)
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        writes = analyze_bash_writes(cmd)
        if writes is not None:
            return any(is_under_transcript_dir(t, root) for _, t in writes if t)
        masked = mask_angle_placeholders(cmd)
        if not any(re.search(p, masked) for p in BASH_WRITE_PATTERNS):
            return False
        candidates = extract_bash_write_targets(cmd)
        candidates += re.findall(r"[^\s'\"]*\.claude/projects[^\s'\"]*", cmd)
        return any(is_under_transcript_dir(t.rstrip(")`;"), root) for t in candidates)
    return False


def targets_creator_denied_paths(tool, tool_input, root):
    """creator が vault/plans/・vault/log/ へ書き込もうとしていないか判定する（拒否リスト方式）。

    creator の成果物パスは repo 全体になりうるため ALLOWED の許可リスト方式は使わず、
    vault/rules/ の改ざん防止判定（targets_vault_rules）と同じ考え方で、書き込んではいけない
    2パスだけを直接判定する。
    """
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        return normalize(path, root).startswith(DENIED_FOR_CREATOR)
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        writes = analyze_bash_writes(cmd)
        if writes is not None:
            return any(normalize(t, root).startswith(DENIED_FOR_CREATOR) for _, t in writes if t)
        masked = mask_angle_placeholders(cmd)
        if not any(re.search(p, masked) for p in BASH_WRITE_PATTERNS):
            return False
        redirect_targets = re.findall(r">{1,2}\s*([^\s;&|]+)", masked)
        path_like = re.findall(r"[^\s'\"]*vault/(?:plans|log)/[^\s'\"]*", cmd)
        candidates = redirect_targets + path_like
        return any(normalize(t, root).startswith(DENIED_FOR_CREATOR) for t in candidates)
    return False


def plan_raw_rows(plan_text):
    """plan_guard.py の raw_rows と同じ規則（他ファイルへの import はしない方針を踏襲）。

    「## タスク表」（前方一致）以降のデータ行を生のセルのリストで返す（見出し行・区切り行は除く）。
    """
    rows = []
    in_table = False
    for line in plan_text.splitlines():
        if line.startswith("## "):
            in_table = line.strip().startswith("## タスク表")
            continue
        stripped = line.strip()
        if not in_table or not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or cells[0] == "id" or re.fullmatch(r"-*", cells[0]):
            continue
        rows.append(cells)
    return rows


def plan_task_status(root, plan_id, task_id):
    """vault/plans/<plan_id>.md のタスク表から task_id の status を返す。

    計画票が無い・読めない・該当行が無い場合は None（fail-open。呼び出し側で許可に倒す）。
    """
    path = os.path.join(root, "vault", "plans", f"{plan_id}.md")
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None
    for cells in plan_raw_rows(text):
        if len(cells) < 5:
            continue
        cells = list(cells) + [""] * (6 - len(cells))
        row = dict(zip(PLAN_TASK_COLUMNS, cells[:6]))
        if row["id"] == task_id:
            return row["status"]
    return None


def match_task_or_verdict_path(rel):
    """rel（normalize() 済みのパス）が vault/tasks/<計画ID>/<id>.md または
    vault/verdicts/<計画ID>/<id>.json にマッチしたら (plan_id, id) を返す。マッチしなければ None。
    """
    m = TASK_FILE_RE.match(rel)
    if m:
        return m.group(1), m.group(2)
    m = VERDICT_FILE_RE.match(rel)
    if m:
        return m.group(1), m.group(2)
    return None


def is_git_stage_or_commit_only(cmd):
    """Bash コマンドの書き込み動詞が git add / git commit だけか判定する（issue #84）。

    True になるのは次を全て満たす時：
    - 改行・`$(`・バッククォート・`<(`・`>(` を含まず、shlex でトークン化できる
    - `;`・`&&`・`||`・`|`・`&` 以外の記号だけのトークン（リダイレクト・サブシェル）が無い
    - `git add` / `git commit` で始まるセグメントが1つ以上あり、それ以外のセグメントは
      OTHER_WRITE_PATTERNS にマッチしない
    どれか1つでも満たさなければ False（従来の判定に進む＝fail-closed）。引用符内の文字列は
    shlex が1トークンにまとめるので、commit メッセージ中のパス文字列は書き込み対象にならない。
    """
    if "\n" in cmd or "\r" in cmd or any(s in cmd for s in ("$(", "`", "<(", ">(")):
        return False
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return False
    segments = [[]]
    for tok in tokens:
        if tok in SEGMENT_SEPARATORS:
            segments.append([])
        elif re.fullmatch(r"[();<>|&]+", tok):
            return False
        else:
            segments[-1].append(tok)
    staged = False
    for seg in segments:
        if not seg:
            continue
        if seg[0] == "git" and len(seg) >= 2 and seg[1] in ("add", "commit"):
            staged = True
            continue
        text = " ".join(seg)
        if any(re.search(p, text) for p in OTHER_WRITE_PATTERNS):
            return False
    return staged


def find_done_task_write(tool, tool_input, root):
    """この呼び出しが done なタスクの vault/tasks/ または vault/verdicts/ を書き込もうと
    しているか判定する。該当すれば (plan_id, task_id, rel) を返し、それ以外は None を返す
    （マッチしない・計画票が無い・done でない場合は全て None＝fail-open）。
    """
    candidates = []
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        candidates.append(path)
    elif tool == "Bash":
        cmd = tool_input.get("command") or ""
        writes = analyze_bash_writes(cmd)
        if writes is not None:
            # 解析できた：git add / git commit は内容を変えないので除き、実際の書き込み対象だけで判定する
            candidates.extend(t for v, t in writes if t and v not in ("git-add", "git-commit"))
        else:
            masked = mask_angle_placeholders(cmd)
            if not any(re.search(p, masked) for p in BASH_WRITE_PATTERNS):
                return None
            if is_git_stage_or_commit_only(cmd):
                return None
            candidates.extend(extract_bash_write_targets(cmd))
            candidates.extend(re.findall(r"[^\s'\")]*vault/(?:tasks|verdicts)/[^\s'\")]*", cmd))
    for cand in candidates:
        rel = normalize(cand.rstrip(")\"'`"), root)
        matched = match_task_or_verdict_path(rel)
        if not matched:
            continue
        plan_id, task_id = matched
        if plan_task_status(root, plan_id, task_id) == "done":
            return plan_id, task_id, rel
    return None


PLAN_FILE_RE = re.compile(r"^vault/plans/([^/]+)\.md$")


def frontmatter_status(text):
    """先頭の `---` から次の `---` までの frontmatter の `status:` の値を返す。無ければ None。本文は見ない。"""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r"^status:\s*(\S*)", line)
        if m:
            return m.group(1).strip("\"'")
    return None


def apply_edit(text, old, new, replace_all):
    """Edit 1回分を適用する。old が見つからない場合は None。"""
    if not old or old not in text:
        return None
    return text.replace(old, new) if replace_all else text.replace(old, new, 1)


def content_after_write(tool, tool_input, current):
    """Write/Edit/MultiEdit 適用後のファイル内容を組み立てる。組み立てられない（適用失敗等）時は None。"""
    if tool == "Write":
        content = tool_input.get("content")
        return content if isinstance(content, str) else None
    if tool == "Edit":
        if current is None:
            return None
        return apply_edit(current, tool_input.get("old_string") or "",
                          tool_input.get("new_string") or "", bool(tool_input.get("replace_all")))
    if tool == "MultiEdit":
        if current is None:
            return None
        text = current
        for e in tool_input.get("edits") or []:
            text = apply_edit(text, e.get("old_string") or "", e.get("new_string") or "",
                              bool(e.get("replace_all")))
            if text is None:
                return None
        return text
    return None


def find_plan_approval(tool, tool_input, root):
    """この呼び出しが計画票の承認（status が approved でない状態から approved にする）なら計画 ID を返す。"""
    if tool not in ("Write", "Edit", "MultiEdit"):
        return None
    path = tool_input.get("file_path") or ""
    m = PLAN_FILE_RE.match(normalize(path, root))
    if not m:
        return None
    abs_path = path if os.path.isabs(path) else os.path.join(root, path)
    try:
        with open(abs_path, encoding="utf-8") as f:
            current = f.read()
    except Exception:
        current = None
    after = content_after_write(tool, tool_input, current)
    if after is None:
        return None
    before_status = frontmatter_status(current) if current is not None else None
    if before_status != "approved" and frontmatter_status(after) == "approved":
        return m.group(1)
    return None


def human_messages(transcript_path):
    """会話記録（JSONL）から人の発言（type=user・content が文字列・isMeta が真でない行）を返す。

    読めない（パスが無い・ファイルが無い・どの行も JSON でない）場合も空リストを返す。
    """
    if not transcript_path:
        return []
    try:
        with open(os.path.expanduser(transcript_path), encoding="utf-8") as f:
            lines = f.read().splitlines()
    except Exception:
        return []
    out = []
    for line in lines:
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict) or obj.get("type") != "user" or obj.get("isMeta"):
            continue
        msg = obj.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        if isinstance(content, str):
            out.append(content)
    return out


def is_approve_command(text, plan_id):
    """人の発言が `/plan approve <plan_id>`（スラッシュコマンド形式または文形式）か判定する。"""
    if "<command-name>/plan</command-name>" in text:
        for args in re.findall(r"<command-args>(.*?)</command-args>", text, re.S):
            if args.strip() == f"approve {plan_id}":
                return True
    m = re.match(r"^/plan\s+approve\s+(\S+)", text.lstrip())
    return bool(m) and m.group(1) == plan_id


def find_plan_unblocks(tool, tool_input, root):
    """この呼び出しが計画票のタスク表で blocked の行を blocked 以外にするなら (計画 ID, [id...]) を返す。

    書き込み前に blocked で、書き込み後に同じ id の行があり status が blocked でないものが解除。
    ファイルが無い・組み立てられない・行が消えるだけの場合は解除に当たらない（None）。
    """
    if tool not in ("Write", "Edit", "MultiEdit"):
        return None
    path = tool_input.get("file_path") or ""
    m = PLAN_FILE_RE.match(normalize(path, root))
    if not m:
        return None
    abs_path = path if os.path.isabs(path) else os.path.join(root, path)
    try:
        with open(abs_path, encoding="utf-8") as f:
            current = f.read()
    except Exception:
        return None
    after = content_after_write(tool, tool_input, current)
    if after is None:
        return None
    after_status = {}
    for cells in plan_raw_rows(after):
        if len(cells) >= 2:
            after_status[cells[0]] = cells[1]
    ids = []
    for cells in plan_raw_rows(current):
        if len(cells) >= 2 and cells[1] == "blocked":
            new = after_status.get(cells[0])
            if new is not None and new != "blocked":
                ids.append(cells[0])
    return (m.group(1), ids) if ids else None


def is_unblock_command(text, plan_id, task_id):
    """人の発言が `/plan unblock <plan_id> <task_id>`（スラッシュコマンド形式または文形式）か判定する。

    後ろに回答が続いてよい。計画 ID・タスク ID は空白区切りのトークンで完全一致を比べる。
    """
    want = ["unblock", plan_id, task_id]
    if "<command-name>/plan</command-name>" in text:
        for args in re.findall(r"<command-args>(.*?)</command-args>", text, re.S):
            if args.split()[:3] == want:
                return True
    t = text.lstrip()
    if t.startswith("/plan") and t[5:6].isspace():
        return t[5:].split()[:3] == want
    return False


def delegate_to_worktree(payload):
    """payload["cwd"] が自リポジトリと異なる git worktree を指す場合、そのルート配下の
    `.claude/hooks/agent_write_guard.py` へ判定を委譲する（issue #56 / D-008 フェーズ1）。

    委譲に成功した場合は委譲先の stdout をそのまま文字列で返す（呼び出し側はそれをそのまま
    自分の stdout として出し exit 0 する）。委譲しない・できない場合は None を返し、
    呼び出し側は通常どおりメインリポジトリ側のローカル判定に進む（fail-open）。

    二重委譲防止：委譲先プロセスの環境変数に `_HOOK_DELEGATED=1` をセットして呼び出す。
    自分自身の環境で既に `_HOOK_DELEGATED` が設定されている場合は委譲せず、必ず
    ローカル判定にフォールバックする（委譲は1段まで）。
    """
    if os.environ.get("_HOOK_DELEGATED"):
        return None

    cwd = payload.get("cwd") or ""
    if not cwd:
        return None
    worktree_root = git_toplevel(cwd)
    if not worktree_root:
        return None

    self_root = os.environ.get("CLAUDE_PROJECT_DIR") or git_toplevel(os.path.dirname(os.path.abspath(__file__)))
    if not self_root:
        return None
    if os.path.abspath(worktree_root) == os.path.abspath(self_root):
        return None

    delegate_script = os.path.join(worktree_root, ".claude", "hooks", "agent_write_guard.py")
    if not os.path.isfile(delegate_script):
        return None

    env = os.environ.copy()
    env["_HOOK_DELEGATED"] = "1"
    try:
        result = subprocess.run(
            ["python3", delegate_script],
            input=json.dumps(payload),
            capture_output=True, text=True, timeout=20, env=env,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def is_git_commit_command(cmd):
    """Bash コマンドが実際に git commit を実行するかを返す（issue #91）。

    analyze_bash_writes が解析できた時は git-commit の組があるかだけを見る。
    解析できない形（None）は従来の正規表現と git -<opt> … commit の形で判定する（fail-closed）。
    """
    writes = analyze_bash_writes(cmd)
    if writes is None:
        return bool(re.search(GIT_COMMIT_PATTERN, cmd) or re.search(GIT_PREOPT_COMMIT_PATTERN, cmd))
    return any(verb == "git-commit" for verb, _ in writes)


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    delegated_stdout = delegate_to_worktree(payload)
    if delegated_stdout is not None:
        sys.stdout.write(delegated_stdout)
        sys.exit(0)

    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    root = resolve_root(tool, tool_input, payload)

    # main 直接コミット拒否：agent_type を問わず、現在のブランチが main の時は git commit を拒否する。
    # 非 git リポジトリ・ブランチ取得不能（detached HEAD 等）は fail-open（この判定は素通り）。
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        # 解析できた時は実際に実行される git commit だけを見る。解析できない形は従来の正規表現と
        # git -<opt> … commit の形で判定する（issue #91）。
        if is_git_commit_command(cmd) and current_branch(root) == "main":
            deny(
                f"[agent_write_guard] main への直接コミットはできません。"
                f"ブランチを切ってください（work/<計画IDの英小文字>）: {cmd[:120]}"
            )

    # 改ざん防止：agent_type を問わず、vault/rules/ への書き込みは常に拒否する
    # （タスクの状態や承認済み計画の有無を問わない。解除口は無い）
    if targets_vault_rules(tool, tool_input, root):
        deny(
            "[agent_write_guard] vault/rules/ へは書き込めません。"
            "ルール変更が成果物のタスクは vault/tasks/<計画ID>/<id>-proposal.md に下書きし、"
            "実体への反映は人が手作業で行います。"
        )

    # 会話記録の改ざん防止：agent_type を問わず、~/.claude/projects/ 配下への書き込みは常に拒否する
    # （解除口は無い。承認判定 T-03 が会話記録を裏付けにするための前提）
    if targets_transcript_dir(tool, tool_input, root):
        deny("[agent_write_guard] ~/.claude/projects/ 配下（会話記録）へは書き込めません。")

    agent = payload.get("agent_type") or ""

    # 計画票の承認（draft→approved）は、人が /plan approve <計画ID> で指示した時だけ許可する（D-010 フェーズ4）。
    # agent_type が空（メインセッション）で、会話記録に一致する人の発言がある、または会話記録が読めない時は許可。
    approved_plan = find_plan_approval(tool, tool_input, root)
    if approved_plan:
        deny_reason = (
            f"[agent_write_guard] {approved_plan} の承認（status を approved にすること）は、"
            f"人が /plan approve {approved_plan} で指示した時だけ許可されます。"
        )
        if agent:
            deny(deny_reason)
        humans = human_messages(payload.get("transcript_path"))
        if humans and not any(is_approve_command(t, approved_plan) for t in humans):
            deny(deny_reason)

    # blocked の解除（blocked→他）は、人が /plan unblock <計画ID> <id> で指示した時だけ許可する（D-010 フェーズ5）。
    # agent_type が空で、会話記録に一致する人の発言がある、または会話記録が読めない時は許可。
    unblock = find_plan_unblocks(tool, tool_input, root)
    if unblock:
        plan_id, task_ids = unblock
        humans = human_messages(payload.get("transcript_path")) if not agent else []
        for tid in task_ids:
            if agent or (humans and not any(is_unblock_command(t, plan_id, tid) for t in humans)):
                deny(
                    f"[agent_write_guard] {plan_id}/{tid} の blocked の解除（status を blocked 以外にすること）は、"
                    f"人が /plan unblock {plan_id} {tid} で指示した時だけ許可されます。"
                )

    # done タスクへの書き込み拒否：agent_type を問わず、対応する計画票で status が done な
    # id の vault/tasks/・vault/verdicts/ への書き込みは常に拒否する（解除口は無い）。
    done_target = find_done_task_write(tool, tool_input, root)
    if done_target:
        plan_id, task_id, rel = done_target
        deny(
            f"[agent_write_guard] {plan_id}/{task_id} は status が done のため、"
            f"{rel} へは書き込めません。"
        )

    # creator 向けの拒否リスト：計画票・ログへの書き込みはオーケストレーターに一本化する
    # （ALLOWED の許可リストには creator を加えない。成果物パスは repo 全体になりうるため）
    if agent == "creator" and targets_creator_denied_paths(tool, tool_input, root):
        deny(
            "[agent_write_guard] creator は vault/plans/・vault/log/ に書き込めません。"
            "計画票の状態更新とログ追記は呼び出し元のオーケストレーター（run のメインセッション）が行います。"
        )

    if agent not in ALLOWED:
        sys.exit(0)

    allowed = ALLOWED[agent]
    allowed_text = " / ".join(allowed)

    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        rel = normalize(path, root)
        if not any(rel.startswith(a) for a in allowed):
            deny(f"[agent_write_guard] {agent} は {allowed_text} 以外に書き込めません: {path}")
        sys.exit(0)

    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        masked_cmd = mask_angle_placeholders(cmd)
        parsed = analyze_bash_writes(cmd)
        if parsed is not None:
            # 解析できた時は、実際の書き込み対象だけで判定する（issue #91）
            if not parsed:
                sys.exit(0)
            if any(v in ("git-add", "git-commit", "git-write") for v, _ in parsed):
                deny(f"[agent_write_guard] {agent} の Bash では書き込み・破壊的操作を行えません（{allowed_text} へのリダイレクトのみ可）: {cmd[:120]}")
            if all(is_outside_root(t, root) for _, t in parsed):
                sys.exit(0)
            inside = [(v, t) for v, t in parsed if not is_outside_root(t, root)]
            if all(v in ("cp", "mv") for v, _ in inside):
                # root 内は読み取り元だけで、コピー・移動先が root の外なら許可する
                dests = extract_bash_write_targets(cmd)
                if dests and all(is_outside_root(t, root) for t in dests):
                    sys.exit(0)
            if all(v in ("redirect", "mkdir", "touch") and normalize(t, root).startswith(tuple(allowed))
                   for v, t in inside):
                sys.exit(0)
            deny(f"[agent_write_guard] {agent} の Bash では書き込み・破壊的操作を行えません（{allowed_text} へのリダイレクトのみ可）: {cmd[:120]}")
        if any(re.search(p, masked_cmd) for p in BASH_WRITE_PATTERNS):
            write_targets = extract_bash_write_targets(cmd)
            # 対象パスがすべて root（リポジトリ）の外なら許可する（issue #27）。
            # トレードオフ：/etc/passwd のようなシステムファイルへの書き込みも root 外である以上
            # 許可してしまうが、root 外を一律許可する方式を選んだ結果として受け入れる
            # （過度に複雑な許可リスト方式にはしない）。対象パスが1つも抽出できない場合や、
            # root 内のパスが1つでも混ざる場合はこの許可を適用せず、既存どおり fail-closed に倒す。
            if write_targets and all(is_outside_root(t, root) for t in write_targets):
                sys.exit(0)
            # 許可ディレクトリだけを対象にしたリダイレクトは通す
            targets = re.findall(r">{1,2}\s*([^\s;&|]+)", masked_cmd)
            if targets and all(normalize(t, root).startswith(tuple(allowed)) for t in targets) \
                    and not re.search(DESTRUCTIVE_BASH_PATTERN, cmd):
                sys.exit(0)
            deny(f"[agent_write_guard] {agent} の Bash では書き込み・破壊的操作を行えません（{allowed_text} へのリダイレクトのみ可）: {cmd[:120]}")
    sys.exit(0)


if __name__ == "__main__":
    main()
