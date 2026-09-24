#!/usr/bin/env python3
"""`.claude/settings.json` からハーネス側の hooks と permissions.deny だけを取り除く。

使い方: python3 scripts/unmerge_settings_json.py <src_settings_json> <dst_settings_json>

src はハーネス側の settings.json、dst はインストール先の settings.json。`merge_settings_json.py`
の逆処理として、src が足したエントリだけを dst から除去する。

- dst が無い        → 除去対象も無いので何もせず `skip <dst>`
- 消すものがある    → 消してから `unmerge <dst>`
- 消すものが無い    → 何もせず `skip <dst>`

消すのは次の2つだけで、インストール先が自分で足したものは残す。

- `hooks.<EventName>`：dst の各エントリから、`hooks[].command` が src の同じ EventName の
  どれかのエントリに含まれる command だけを取り除く。除去の結果 `hooks` 配列が空になった
  エントリは配列から削除する
- `permissions.deny`：dst にあって src にもある文字列だけを取り除く

`permissions.allow` は読み取るだけで一切変更しない。

一致判定は command 文字列 / deny 文字列の完全一致のみで行う（matcher の値や hooks エントリの
他フィールドは比較しない）。利用者が harness と偶然同じ文字列を独自に追加していた場合、区別
できずに一緒に消える可能性があるが、これは仕様上の限界として許容する。

unmerge の時だけ `<dst>.bak-<YYYYMMDDHHMMSS>` を残す。ファイルは消さない。
"""
import json
import sys
from datetime import datetime
from pathlib import Path

USAGE = "usage: python3 scripts/unmerge_settings_json.py <src_settings_json> <dst_settings_json>"


def commands(entry):
    """1エントリが持つ hooks[].command の文字列を集合で返す。"""
    out = set()
    for hook in (entry or {}).get("hooks") or []:
        if isinstance(hook, dict) and isinstance(hook.get("command"), str):
            out.add(hook["command"])
    return out


def src_commands_by_event(src_hooks):
    """event ごとに src の command 文字列の集合を返す。"""
    out = {}
    for event, entries in (src_hooks or {}).items():
        if not isinstance(entries, list):
            continue
        known = set()
        for entry in entries:
            known |= commands(entry)
        out[event] = known
    return out


def unmerge_hooks(src_hooks, dst_hooks):
    """src にある command を dst から取り除く。取り除いた数を返す（dst を破壊的に更新する）。"""
    removed = 0
    by_event = src_commands_by_event(src_hooks)
    for event, src_known in by_event.items():
        dst_entries = dst_hooks.get(event)
        if not isinstance(dst_entries, list):
            continue
        new_entries = []
        for entry in dst_entries:
            if not isinstance(entry, dict):
                new_entries.append(entry)
                continue
            hooks = entry.get("hooks")
            if not isinstance(hooks, list):
                new_entries.append(entry)
                continue
            new_hook_list = []
            for hook in hooks:
                if (
                    isinstance(hook, dict)
                    and isinstance(hook.get("command"), str)
                    and hook["command"] in src_known
                ):
                    removed += 1
                    continue
                new_hook_list.append(hook)
            if not new_hook_list:
                # hooks が空になったエントリ自体を削除する
                continue
            entry["hooks"] = new_hook_list
            new_entries.append(entry)
        dst_hooks[event] = new_entries
    return removed


def unmerge_deny(src_deny, dst_deny):
    """src にある deny 文字列を dst から取り除く。取り除いた数を返す（新しいリストを返す）。"""
    src_known = set(src_deny or [])
    new_deny = [item for item in dst_deny if item not in src_known]
    return new_deny, len(dst_deny) - len(new_deny)


def dump(data):
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def main(argv):
    if len(argv) != 3:
        print(USAGE, file=sys.stderr)
        return 2
    src, dst = Path(argv[1]), Path(argv[2])

    try:
        src_data = json.loads(src.read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        print(f"unmerge_settings_json: src を読めない: {err}", file=sys.stderr)
        return 1
    if not isinstance(src_data, dict):
        print(f"unmerge_settings_json: src が JSON オブジェクトでない: {src}", file=sys.stderr)
        return 1

    if not dst.exists():
        print(f"skip {dst}")
        return 0

    try:
        old = dst.read_text(encoding="utf-8")
        dst_data = json.loads(old)
    except (OSError, ValueError) as err:
        print(f"unmerge_settings_json: dst を読めない: {err}", file=sys.stderr)
        return 1
    if not isinstance(dst_data, dict):
        print(f"unmerge_settings_json: dst が JSON オブジェクトでない: {dst}", file=sys.stderr)
        return 1

    dst_hooks = dst_data.get("hooks")
    dst_perms = dst_data.get("permissions")
    dst_deny = (dst_perms or {}).get("deny") if isinstance(dst_perms, dict) else None

    if dst_hooks is not None and not isinstance(dst_hooks, dict):
        print(f"unmerge_settings_json: dst の hooks の型が不正: {dst}", file=sys.stderr)
        return 1
    if dst_deny is not None and not isinstance(dst_deny, list):
        print(f"unmerge_settings_json: dst の permissions.deny の型が不正: {dst}", file=sys.stderr)
        return 1

    removed = 0
    if isinstance(dst_hooks, dict):
        removed += unmerge_hooks(src_data.get("hooks"), dst_hooks)
    if isinstance(dst_deny, list):
        new_deny, deny_removed = unmerge_deny((src_data.get("permissions") or {}).get("deny"), dst_deny)
        if deny_removed:
            dst_perms["deny"] = new_deny
        removed += deny_removed

    if removed == 0:
        # 消すものが無い時は書き換えない
        print(f"skip {dst}")
        return 0
    new = dump(dst_data)

    backup = dst.with_name(f"{dst.name}.bak-{datetime.now().strftime('%Y%m%d%H%M%S')}")
    backup.write_text(old, encoding="utf-8")
    dst.write_text(new, encoding="utf-8")
    print(f"unmerge {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
