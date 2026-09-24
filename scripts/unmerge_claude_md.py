#!/usr/bin/env python3
"""CLAUDE.md からハーネスのマーカーブロックだけを取り除く（merge_claude_md.py の逆処理）。

使い方: python3 scripts/unmerge_claude_md.py <target_claude_md>

target はブロックを取り除きたい CLAUDE.md（`<!-- ai-harness:begin ... -->` 〜
`<!-- ai-harness:end -->` を含む想定）。

- target が無い、またはブロックが無い → 何もせず `skip <target>`
- ブロック除去後の残りが空白のみ        → ファイルごと削除し `delete <target>`
- ブロック除去後に他の本文が残る        → ブロックだけ除去し `remove <target>`

delete / remove の時だけ `<target>.bak-<YYYYMMDDHHMMSS>` を残す。
"""
import re
import sys
from datetime import datetime
from pathlib import Path

BLOCK_RE = re.compile(r"<!-- ai-harness:begin.*?<!-- ai-harness:end -->", re.DOTALL)
USAGE = "usage: python3 scripts/unmerge_claude_md.py <target_claude_md>"


def main(argv):
    if len(argv) != 2:
        print(USAGE, file=sys.stderr)
        return 2
    target = Path(argv[1])

    if not target.exists():
        print(f"skip {target}")
        return 0

    try:
        old = target.read_text(encoding="utf-8")
    except OSError as err:
        print(f"unmerge_claude_md: target を読めない: {err}", file=sys.stderr)
        return 1

    if not BLOCK_RE.search(old):
        print(f"skip {target}")
        return 0

    new = BLOCK_RE.sub("", old, count=1)

    backup = target.with_name(f"{target.name}.bak-{datetime.now().strftime('%Y%m%d%H%M%S')}")
    backup.write_text(old, encoding="utf-8")

    if new.strip() == "":
        target.unlink()
        print(f"delete {target}")
        return 0

    target.write_text(new, encoding="utf-8")
    print(f"remove {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
