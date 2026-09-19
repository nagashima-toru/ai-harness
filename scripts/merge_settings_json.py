#!/usr/bin/env python3
"""`.claude/settings.json` にハーネス側の hooks と permissions.deny を冪等にマージする。

使い方: python3 scripts/merge_settings_json.py <src_settings_json> <dst_settings_json>

src はハーネス側の settings.json、dst はインストール先の settings.json。

- dst が無い        → src の内容で作成し `create <dst>`
- 足すものがある    → 足してから `merge <dst>`
- 足すものが無い    → 何もせず `skip <dst>`

足すのは次の2つだけで、インストール先が自分で足したものは消さない。

- `hooks.<EventName>`：src のエントリのうち、`hooks[].command` がどれも dst の同じ
  EventName に無いものだけを、matcher ごと配列の末尾に追加する
- `permissions.deny`：src にあって dst に無い文字列だけを src の並び順で末尾に追加する

`permissions.allow` は読み取るだけで一切変更しない（インストール先が許可を足すための列で、
ハーネスが上書きしてよいものではないため）。

merge の時だけ `<dst>.bak-<YYYYMMDDHHMMSS>` を残す。ファイルは消さない。
"""
import json
import sys
from datetime import datetime
from pathlib import Path

USAGE = "usage: python3 scripts/merge_settings_json.py <src_settings_json> <dst_settings_json>"


def commands(entry):
    """1エントリが持つ hooks[].command の文字列を集合で返す。"""
    out = set()
    for hook in (entry or {}).get("hooks") or []:
        if isinstance(hook, dict) and isinstance(hook.get("command"), str):
            out.add(hook["command"])
    return out


def merge_hooks(src_hooks, dst_hooks):
    """src の hooks を dst に足す。足した数を返す（dst を破壊的に更新する）。"""
    added = 0
    for event, src_entries in (src_hooks or {}).items():
        if not isinstance(src_entries, list):
            continue
        dst_entries = dst_hooks.setdefault(event, [])
        if not isinstance(dst_entries, list):
            continue
        known = set()
        for entry in dst_entries:
            known |= commands(entry)
        for entry in src_entries:
            if commands(entry) & known:
                continue
            dst_entries.append(entry)
            known |= commands(entry)
            added += 1
    return added


def merge_deny(src_deny, dst_deny):
    """src の deny を dst に足す。足した数を返す（dst を破壊的に更新する）。"""
    added = 0
    known = set(dst_deny)
    for item in src_deny or []:
        if item in known:
            continue
        dst_deny.append(item)
        known.add(item)
        added += 1
    return added


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
        print(f"merge_settings_json: src を読めない: {err}", file=sys.stderr)
        return 1

    if not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(dump(src_data), encoding="utf-8")
        print(f"create {dst}")
        return 0

    try:
        old = dst.read_text(encoding="utf-8")
        dst_data = json.loads(old)
    except (OSError, ValueError) as err:
        print(f"merge_settings_json: dst を読めない: {err}", file=sys.stderr)
        return 1
    if not isinstance(dst_data, dict):
        print(f"merge_settings_json: dst が JSON オブジェクトでない: {dst}", file=sys.stderr)
        return 1

    dst_hooks = dst_data.setdefault("hooks", {})
    dst_perms = dst_data.setdefault("permissions", {})
    dst_deny = dst_perms.setdefault("deny", [])
    if not isinstance(dst_hooks, dict) or not isinstance(dst_deny, list):
        print(f"merge_settings_json: dst の hooks / permissions.deny の型が不正: {dst}", file=sys.stderr)
        return 1

    added = merge_hooks(src_data.get("hooks"), dst_hooks)
    added += merge_deny((src_data.get("permissions") or {}).get("deny"), dst_deny)

    if added == 0:
        # 足すものが無い時は書き換えない（整形の違いだけで dst を触らない）
        print(f"skip {dst}")
        return 0
    new = dump(dst_data)

    backup = dst.with_name(f"{dst.name}.bak-{datetime.now().strftime('%Y%m%d%H%M%S')}")
    backup.write_text(old, encoding="utf-8")
    dst.write_text(new, encoding="utf-8")
    print(f"merge {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
