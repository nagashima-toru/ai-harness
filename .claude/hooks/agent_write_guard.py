#!/usr/bin/env python3
"""PreToolUse フック：サブエージェントごとに書き込み先を制限する。

- verifier : vault/verdicts/ 配下のみ
- planner  : vault/plans/ と vault/tasks/ 配下のみ
対象ツール : Write / Edit / MultiEdit / NotebookEdit（パス判定）、Bash（リダイレクトや破壊的コマンドの簡易判定）
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

creator（run から呼ばれる作成エージェント）向けの拒否リスト：creator は成果物パス（repo 全体に
及びうる）と vault/tasks/ への書き込みは許可されるが、vault/plans/・vault/log/ への書き込みは
agent_type を問わない他の判定と同じく常に拒否する。計画票のタスク表の状態更新とログ追記は、
呼び出し元のオーケストレーター（run のメインセッション）に一本化するための制限（D-003 フェーズ2）。
ALLOWED の許可リスト方式とは異なり、拒否リスト方式で実装する。
"""
import json
import os
import re
import subprocess
import sys

GIT_COMMIT_PATTERN = r"\bgit\s+commit\b"
GITHUB_API_HOSTS = ("api.github.com", "raw.githubusercontent.com", "githubusercontent.com")

ALLOWED = {
    "verifier": ["vault/verdicts/"],
    "planner": ["vault/plans/", "vault/tasks/"],
}
DENIED_FOR_CREATOR = ("vault/plans/", "vault/log/")
BASH_WRITE_PATTERNS = [
    r"(^|[^<>])>{1,2}\s*(?!&)\S",     # リダイレクト（`2>&1` のような N>&M fd 複製は書き込みとみなさない）
    r"\btee\b",
    r"\b(rm|mv|cp|touch|mkdir|chmod|chown)\b",
    r"\bgit\s+(add|commit|push|checkout|switch|reset|restore|clean|stash|merge|rebase|rm|mv)\b",
    r"\bsed\s+-i\b",
]


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


def targets_vault_rules(tool, tool_input, root):
    """この呼び出しが vault/rules/ 配下への書き込みを試みているか判定する。"""
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        return normalize(path, root).startswith("vault/rules/")
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if targets_vault_rules_remote(cmd):
            return True
        if not any(re.search(p, cmd) for p in BASH_WRITE_PATTERNS):
            return False
        redirect_targets = re.findall(r">{1,2}\s*([^\s;&|]+)", cmd)
        path_like = re.findall(r"[^\s'\"]*vault/rules/[^\s'\"]*", cmd)
        candidates = redirect_targets + path_like
        return any(normalize(t, root).startswith("vault/rules/") for t in candidates)
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
        if not any(re.search(p, cmd) for p in BASH_WRITE_PATTERNS):
            return False
        redirect_targets = re.findall(r">{1,2}\s*([^\s;&|]+)", cmd)
        path_like = re.findall(r"[^\s'\"]*vault/(?:plans|log)/[^\s'\"]*", cmd)
        candidates = redirect_targets + path_like
        return any(normalize(t, root).startswith(DENIED_FOR_CREATOR) for t in candidates)
    return False


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    root = resolve_root(tool, tool_input, payload)

    # main 直接コミット拒否：agent_type を問わず、現在のブランチが main の時は git commit を拒否する。
    # 非 git リポジトリ・ブランチ取得不能（detached HEAD 等）は fail-open（この判定は素通り）。
    if tool == "Bash":
        cmd = tool_input.get("command") or ""
        if re.search(GIT_COMMIT_PATTERN, cmd) and current_branch(root) == "main":
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

    agent = payload.get("agent_type") or ""

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
        if any(re.search(p, cmd) for p in BASH_WRITE_PATTERNS):
            write_targets = extract_bash_write_targets(cmd)
            # 対象パスがすべて root（リポジトリ）の外なら許可する（issue #27）。
            # トレードオフ：/etc/passwd のようなシステムファイルへの書き込みも root 外である以上
            # 許可してしまうが、root 外を一律許可する方式を選んだ結果として受け入れる
            # （過度に複雑な許可リスト方式にはしない）。対象パスが1つも抽出できない場合や、
            # root 内のパスが1つでも混ざる場合はこの許可を適用せず、既存どおり fail-closed に倒す。
            if write_targets and all(is_outside_root(t, root) for t in write_targets):
                sys.exit(0)
            # 許可ディレクトリだけを対象にしたリダイレクトは通す
            targets = re.findall(r">{1,2}\s*([^\s;&|]+)", cmd)
            if targets and all(normalize(t, root).startswith(tuple(allowed)) for t in targets) \
                    and not re.search(DESTRUCTIVE_BASH_PATTERN, cmd):
                sys.exit(0)
            deny(f"[agent_write_guard] {agent} の Bash では書き込み・破壊的操作を行えません（{allowed_text} へのリダイレクトのみ可）: {cmd[:120]}")
    sys.exit(0)


if __name__ == "__main__":
    main()
