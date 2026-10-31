#!/usr/bin/env python3
"""Run a command with a wall-clock timeout and an output-size cap; kill its whole process group on either.

usage: runlimited.py --timeout SECONDS --max-bytes N --out FILE [--cwd DIR] -- CMD [ARGS...]
Combined stdout+stderr is written to FILE (at most N bytes, then a marker line). stdin is /dev/null.
Prints one JSON line on stdout: {"exit": N, "timed_out": bool, "truncated": bool, "dur_s": float}.
exit is the command's status, -SIGNAL when it died of a signal. Own exit status: 0, or 2 on usage errors.
SIGTERM/SIGINT to this process kill the command's group too and report "interrupted": true.
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import threading
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=float, required=True)
    ap.add_argument("--max-bytes", type=int, default=1 << 20)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cwd", default=None)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()
    cmd = args.cmd[1:] if args.cmd[:1] == ["--"] else args.cmd
    if not cmd:
        ap.error("no command")
    state = {"timed_out": False, "truncated": False, "interrupted": False}
    start = time.monotonic()
    try:
        proc = subprocess.Popen(cmd, cwd=args.cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, start_new_session=True)
    except OSError as exc:
        with open(args.out, "w") as fh:
            fh.write("runlimited: cannot start: %s\n" % exc)
        print(json.dumps({"exit": 127, "timed_out": False, "truncated": False, "interrupted": False, "dur_s": 0.0}))
        return 0

    def kill_group():
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass

    def on_signal(signum, frame):
        state["interrupted"] = True
        kill_group()

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    def pump():
        written = 0
        with open(args.out, "wb") as fh:
            while True:
                chunk = proc.stdout.read(65536)
                if not chunk:
                    break
                room = args.max_bytes - written
                if room > 0:
                    fh.write(chunk[:room])
                    written += min(len(chunk), room)
                if len(chunk) > room and not state["truncated"]:
                    state["truncated"] = True
                    fh.write(b"\n[runlimited: output limit of %d bytes reached, command killed]\n" % args.max_bytes)
                    kill_group()
                    break

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    deadline = start + args.timeout
    while proc.poll() is None:
        if time.monotonic() >= deadline:
            state["timed_out"] = True
            kill_group()
            break
        time.sleep(0.02)
    proc.wait()
    kill_group()  # stray children that outlived the command
    reader.join(5)
    code = proc.returncode
    print(json.dumps({"exit": code, "timed_out": state["timed_out"], "truncated": state["truncated"],
                      "interrupted": state["interrupted"], "dur_s": round(time.monotonic() - start, 3)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
