#!/usr/bin/env python3
"""Run one benchmark process and report its peak resident set size."""

import os
import resource
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: measure_rss.py <output-log> <program> [args...]", file=sys.stderr)
        return 2

    output_path, *command = sys.argv[1:]
    with open(output_path, "w", encoding="utf-8") as output:
        completed = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=False)

    peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    if sys.platform != "darwin":
        peak *= 1024
    if peak <= 0:
        print("could not measure child peak RSS", file=sys.stderr)
        return 1
    print(f"max_rss_bytes={peak}")
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
