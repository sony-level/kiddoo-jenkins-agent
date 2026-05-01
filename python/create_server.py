#!/usr/bin/env python3
"""
File    : python/create_server.py
Version : 3.0.0
Purpose : Orchestrator -- runs bash/create_server.sh and sends Discord notifications.
          All tooling (Docker, Ansible, Terraform, Jenkins user) is installed by
          cloud-init on the instance itself.
Author  : kiddoo-infra
Usage   : python3 create_server.py --help
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=True)

from aws import BASH_SCRIPT, run_bash  # noqa: E402
from log import log, warn  # noqa: E402
from notify import ERR, INFO, OK, notify  # noqa: E402


def parse_args():
    p = argparse.ArgumentParser(
        description="Creates the kiddoo-jenkins-agent EC2 Jenkins agent."
    )
    p.add_argument("-r", "--region", default=os.getenv("AWS_REGION", "eu-west-3"))
    p.add_argument("-t", "--type", default=os.getenv("INSTANCE_TYPE", "t3.micro"))
    p.add_argument(
        "-p", "--ssh-port", default=int(os.getenv("SSH_PORT", "2222")), type=int
    )
    p.add_argument("-c", "--ssh-cidr", default=os.getenv("SSH_CIDR"))
    p.add_argument("-k", "--ssh-key-file", default=os.getenv("SSH_PUBLIC_KEY_FILE"))
    p.add_argument(
        "-s", "--volume-size", default=int(os.getenv("ROOT_VOLUME_GIB", "30")), type=int
    )
    p.add_argument("--vpc-id", default=os.getenv("VPC_ID"))
    p.add_argument("--subnet-id", default=os.getenv("SUBNET_ID"))
    p.add_argument("-n", "--dry-run", action="store_true")
    return p.parse_args()


def main():
    args = parse_args()
    if not os.environ.get("DISCORD_WEBHOOK_URL"):
        warn("DISCORD_WEBHOOK_URL not set -- notifications disabled")

    print(f"\n{'='*52}\n  kiddoo-jenkins-agent  |  region={args.region}\n{'='*52}")
    log(f"Instance: {args.type}  SSH port: {args.ssh_port}")

    if args.dry_run:
        subprocess.run([str(BASH_SCRIPT), "--dry-run"], check=False)
        return

    notify(
        "kiddoo-jenkins-agent: creation started",
        "EC2 provisioning running.",
        INFO,
        [
            {"name": "Region", "value": args.region, "inline": True},
            {"name": "Type", "value": args.type, "inline": True},
        ],
    )

    try:
        instance_id, public_ip = run_bash(args)
    except SystemExit:
        notify("kiddoo-jenkins-agent: error", "Bash script failed.", ERR)
        raise

    notify(
        "kiddoo-jenkins-agent: instance running",
        "Cloud-init is installing tools. Check /var/log/kiddoo-jenkins-agent-setup.log.",
        OK,
        [
            {"name": "Instance", "value": instance_id, "inline": True},
            {"name": "Public IP", "value": public_ip, "inline": True},
            {
                "name": "SSH",
                "value": f"ssh -p {args.ssh_port} admin@{public_ip}",
                "inline": False,
            },
        ],
    )

    print(f"\n{'='*52}\n  kiddoo-jenkins-agent created\n{'='*52}")
    print(f"  Instance : {instance_id}")
    print(f"  IP       : {public_ip}")
    print(f"  SSH      : ssh -p {args.ssh_port} admin@{public_ip}")
    print("  Log      : /var/log/kiddoo-jenkins-agent-setup.log  (on instance)\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        warn("Interrupted")
        sys.exit(1)
