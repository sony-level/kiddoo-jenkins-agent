#!/usr/bin/env python3
"""
File    : python/destroy_server.py
Version : 1.0.0
Purpose : Cleanup orchestrator -- destroys all kiddoo-jenkins-agent AWS resources
          (EC2 instance, EIP, security group, key pair) and sends Discord notifications.
Author  : kiddoo-infra
Usage   : python3 destroy_server.py [--region REGION] [--force]
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=True)

from log import log, warn
from notify import ERR, INFO, OK, notify

BASH_SCRIPT = Path(__file__).resolve().parent.parent / "bash" / "destroy_server.sh"


def parse_args():
    p = argparse.ArgumentParser(description="Destroys all kiddoo-jenkins-agent AWS resources.")
    p.add_argument("-r", "--region", default=os.getenv("AWS_REGION", "eu-west-3"))
    p.add_argument("-f", "--force",  action="store_true", help="Skip confirmation prompt")
    return p.parse_args()


def main():
    args = parse_args()

    print(f"\n{'='*52}\n  kiddoo-jenkins-agent CLEANUP  |  region={args.region}\n{'='*52}")

    notify("kiddoo-jenkins-agent: cleanup started",
           f"Destroying all resources in {args.region}.", INFO)

    cmd = [str(BASH_SCRIPT), "--region", args.region]
    if args.force:
        cmd.append("--force")

    try:
        subprocess.run(cmd, env=os.environ.copy(), check=True)
    except subprocess.CalledProcessError as e:
        notify("kiddoo-jenkins-agent: cleanup failed",
               f"Script exited with code {e.returncode}.", ERR)
        warn(f"Cleanup failed (exit {e.returncode})")
        sys.exit(e.returncode)

    notify("kiddoo-jenkins-agent: cleanup complete",
           "All resources have been destroyed.", OK)
    print(f"\n{'='*52}\n  Cleanup complete\n{'='*52}\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        warn("Interrupted")
        sys.exit(1)
