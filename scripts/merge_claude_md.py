#!/usr/bin/env python3
"""CLAUDE.md にハーネスのブロックを冪等にマージする。

使い方: python3 scripts/merge_claude_md.py <src_claude_md> <dst_claude_md>

src はハーネス側の CLAUDE.md（`<!-- ai-harness:begin ... -->` 〜
`<!-- ai-harness:end -->` のブロックそのもの）。dst はインストール先の CLAUDE.md。

- dst が無い          → src の内容で作成し `create <dst>`
- dst にブロックがある → その範囲だけを src に置換し `update <dst>`
- dst にブロックが無い → 既存本文を残したまま末尾に追記し `merge <dst>`
- 書き換えるものが無い → 何もせず `skip <dst>`

update / merge の時だけ `<dst>.bak-<YYYYMMDDHHMMSS>` を残す。ファイルは消さない。
"""
import re
import sys
from datetime import datetime
from pathlib import Path

BLOCK_RE = re.compile(r"<!-- ai-harness:begin.*?<!-- ai-harness:end -->", re.DOTALL)
USAGE = "usage: python3 scripts/merge_claude_md.py <src_claude_md> <dst_claude_md>"


def main(argv):
    if len(argv) != 3:
        print(USAGE, file=sys.stderr)
        return 2
    src, dst = Path(argv[1]), Path(argv[2])
    try:
        block = src.read_text(encoding="utf-8")
    except OSError as err:
        print(f"merge_claude_md: src を読めない: {err}", file=sys.stderr)
        return 1
    if not BLOCK_RE.search(block):
        print(f"merge_claude_md: src にハーネスのマーカーが無い: {src}", file=sys.stderr)
        return 1
    block = block.rstrip("\n") + "\n"

    if not dst.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(block, encoding="utf-8")
        print(f"create {dst}")
        return 0

    try:
        old = dst.read_text(encoding="utf-8")
    except OSError as err:
        print(f"merge_claude_md: dst を読めない: {err}", file=sys.stderr)
        return 1

    if BLOCK_RE.search(old):
        new = BLOCK_RE.sub(lambda _: block.rstrip("\n"), old, count=1)
        action = "update"
    elif old.strip() == "":
        new = block
        action = "merge"
    else:
        new = old.rstrip("\n") + "\n\n" + block
        action = "merge"

    if new == old:
        print(f"skip {dst}")
        return 0

    backup = dst.with_name(f"{dst.name}.bak-{datetime.now().strftime('%Y%m%d%H%M%S')}")
    backup.write_text(old, encoding="utf-8")
    dst.write_text(new, encoding="utf-8")
    print(f"{action} {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
