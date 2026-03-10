#!/usr/bin/env python3
"""
Run RaidInspector bridge fetch in a loop for faster remote refresh workflows.

This script repeatedly invokes fetch_from_queue.py with your preferred flags.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import time


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run RaidInspector bridge fetch loop")
    parser.add_argument("--python", default=sys.executable, help="Python interpreter used to run fetch_from_queue.py")
    parser.add_argument("--fetch-script", default="", help="Path to fetch_from_queue.py (auto-resolved if omitted)")
    parser.add_argument("--raid-inspector-sv", required=True, help="Path to RaidInspector.lua SavedVariables")
    parser.add_argument("--bridge-output", required=True, help="Path to RaidInspectorBridge.lua output")
    parser.add_argument("--interval", type=float, default=30.0, help="Seconds to sleep between fetch cycles")
    parser.add_argument("--once", action="store_true", help="Run a single cycle and exit")
    parser.add_argument("--verbose", action="store_true", help="Print command and cycle logs")
    parser.add_argument(
        "--fetch-args",
        nargs=argparse.REMAINDER,
        help="Additional args passed through to fetch_from_queue.py",
    )
    return parser.parse_args()


def resolve_fetch_script(path_arg: str) -> pathlib.Path:
    if path_arg:
        return pathlib.Path(path_arg)
    return pathlib.Path(__file__).with_name("fetch_from_queue.py")


def main() -> int:
    args = parse_args()
    fetch_script = resolve_fetch_script(args.fetch_script)
    if not fetch_script.exists():
        print(f"Fetch script not found: {fetch_script}")
        return 2

    if args.interval < 1.0:
        args.interval = 1.0

    passthrough = list(args.fetch_args or [])
    if passthrough and passthrough[0] == "--":
        passthrough = passthrough[1:]

    cycle = 0
    while True:
        cycle += 1
        cmd = [
            args.python,
            str(fetch_script),
            "--raid-inspector-sv",
            args.raid_inspector_sv,
            "--bridge-output",
            args.bridge_output,
        ]
        cmd.extend(passthrough)

        if args.verbose:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] cycle={cycle}")
            print("  " + " ".join(cmd))

        result = subprocess.run(cmd, check=False)
        if result.returncode != 0:
            print(f"Cycle {cycle} failed with exit code {result.returncode}")

        if args.once:
            return result.returncode

        try:
            time.sleep(args.interval)
        except KeyboardInterrupt:
            print("Stopped daemon loop")
            return 0


if __name__ == "__main__":
    raise SystemExit(main())
