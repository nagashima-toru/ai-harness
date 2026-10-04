"""3フック（agent_write_guard.py・plan_guard.py・stop_gate.py）が共通で使う関数を置く（D-011）。

標準ライブラリだけを使い、import した時に副作用（標準出力への出力・ファイルの書き込み）を起こさない。
フック本体ではないので settings.json には登録しない。
"""
import json
import os
import re
import subprocess


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


def delegate_to_worktree(payload, script_name):
    """payload["cwd"] が自リポジトリと異なる git worktree を指す場合、そのルート配下の
    `.claude/hooks/<script_name>` へ判定を委譲する（issue #56）。

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

    delegate_script = os.path.join(worktree_root, ".claude", "hooks", script_name)
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


def plan_id_and_status(path):
    """計画票の frontmatter から (id, status) を返す。読めない・frontmatter が無ければ (None, None)。"""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None, None
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        return None, None
    front = m.group(1)
    id_m = re.search(r"^id:\s*(\S+)\s*$", front, re.MULTILINE)
    status_m = re.search(r"^status:\s*(\S+)\s*$", front, re.MULTILINE)
    plan_id = id_m.group(1) if id_m else os.path.basename(path)[: -len(".md")]
    status = status_m.group(1) if status_m else None
    return plan_id, status


def approved_plans(root):
    """vault/plans/*.md のうち status: approved のもの一覧を [(plan_id, path), ...] で返す。"""
    plans_dir = os.path.join(root, "vault", "plans")
    if not os.path.isdir(plans_dir):
        return []
    out = []
    for name in sorted(os.listdir(plans_dir)):
        if not name.endswith(".md"):
            continue
        path = os.path.join(plans_dir, name)
        plan_id, status = plan_id_and_status(path)
        if status == "approved":
            out.append((plan_id, path))
    return out


def raw_rows(plan_text):
    """「## タスク表」（前方一致）以降のデータ行を生のセルのリストで返す（見出し行・区切り行は除く）。"""
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
