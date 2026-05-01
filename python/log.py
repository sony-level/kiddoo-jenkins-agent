"""
File    : python/log.py
Version : 1.0.0
Purpose : Colored logging helpers used across the Python orchestrator.
Author  : kiddoo-infra
"""

import sys


def log(m):
    print(f"[INFO]  {m}", flush=True)


def ok(m):
    print(f"[OK]    {m}", flush=True)


def warn(m):
    print(f"[WARN]  {m}", flush=True)


def die(m):
    print(f"[ERROR] {m}", file=sys.stderr)
    sys.exit(1)
