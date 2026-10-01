#!/usr/bin/env python3
"""無人実行（cron・CI）用ラッパー。HARNESS_RUN_CMD をタイムアウト付きで実行する。

環境変数:
  HARNESS_RUN_CMD     実行するコマンド（既定: claude -p "/run"）。shlex.split で分割し、シェルは経由しない
  HARNESS_RUN_TIMEOUT 秒（整数、既定: 3600）

終了コード:
  子の終了コード / シグナルで死んだ子は 128+シグナル番号 / タイムアウト 124
  設定不正 2 / コマンドが見つからない 127
"""
import os
import shlex
import signal
import subprocess
import sys

DEFAULT_CMD = 'claude -p "/run"'
DEFAULT_TIMEOUT = 3600
KILL_GRACE = 10


def killpg(pgid, sig):
    try:
        os.killpg(pgid, sig)
    except ProcessLookupError:
        pass


def main():
    cmd_str = os.environ.get("HARNESS_RUN_CMD") or DEFAULT_CMD
    raw = os.environ.get("HARNESS_RUN_TIMEOUT")
    if raw is None or raw == "":
        timeout = DEFAULT_TIMEOUT
    else:
        try:
            timeout = int(raw)
        except ValueError:
            timeout = 0
        if timeout <= 0:
            print("run_unattended: invalid HARNESS_RUN_TIMEOUT: %r" % raw, file=sys.stderr)
            return 2

    try:
        argv = shlex.split(cmd_str)
    except ValueError as e:
        print("run_unattended: invalid HARNESS_RUN_CMD: %s" % e, file=sys.stderr)
        return 2
    if not argv:
        print("run_unattended: empty HARNESS_RUN_CMD", file=sys.stderr)
        return 2

    try:
        proc = subprocess.Popen(argv, start_new_session=True)
    except FileNotFoundError:
        print("run_unattended: command not found: %s" % argv[0], file=sys.stderr)
        return 127

    pgid = proc.pid
    try:
        rc = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print("run_unattended: timeout %ds" % timeout, file=sys.stderr)
        sys.stderr.flush()
        killpg(pgid, signal.SIGTERM)
        try:
            proc.wait(timeout=KILL_GRACE)
        except subprocess.TimeoutExpired:
            killpg(pgid, signal.SIGKILL)
            proc.wait()
        return 124
    except KeyboardInterrupt:
        killpg(pgid, signal.SIGTERM)
        proc.wait()
        return 130

    if rc < 0:
        return 128 + (-rc)
    return rc


if __name__ == "__main__":
    sys.exit(main())
