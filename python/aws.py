"""
File    : python/aws.py
Version : 1.0.0
Purpose : AWS operations -- delegate to the Bash script and fetch instance info.
Author  : kiddoo-infra
"""

import json
import os
import shlex
import subprocess
from pathlib import Path

from log import die, log, ok

BASH_SCRIPT = Path(__file__).resolve().parent.parent / "bash" / "create_server.sh"


def run_bash(args):
    """Execute the Bash orchestrator with the given CLI arguments."""
    if not BASH_SCRIPT.exists():
        die(f"Script not found: {BASH_SCRIPT}")
    cmd = [
        str(BASH_SCRIPT),
        "--region",
        args.region,
        "--type",
        args.type,
        "--ssh-port",
        str(args.ssh_port),
    ]
    if args.volume_size:
        cmd += ["--volume-size", str(args.volume_size)]
    if args.ssh_cidr:
        cmd += ["--ssh-cidr", args.ssh_cidr]
    if args.ssh_key_file:
        cmd += ["--ssh-key-file", args.ssh_key_file]
    if args.vpc_id:
        cmd += ["--vpc-id", args.vpc_id]
    if args.subnet_id:
        cmd += ["--subnet-id", args.subnet_id]
    log(f"Running: {shlex.join(cmd)}")
    try:
        subprocess.run(cmd, env=os.environ.copy(), check=True)
    except subprocess.CalledProcessError as e:
        die(f"Bash script failed (exit {e.returncode})")
    return fetch_instance(args.region)


def fetch_instance(region):
    """Query AWS for the latest running kiddoo-server instance."""
    log("Fetching instance info from AWS...")
    try:
        raw = subprocess.check_output(
            [
                "aws",
                "ec2",
                "describe-instances",
                "--region",
                region,
                "--filters",
                "Name=tag:Name,Values=kiddoo-jenkins-agent",
                "Name=instance-state-name,Values=running",
                "--query",
                "Reservations[-1].Instances[0].{ID:InstanceId,IP:PublicIpAddress}",
                "--output",
                "json",
            ],
            text=True,
        )
        data = json.loads(raw)
        if not data or data.get("ID") in (None, "None"):
            die("Instance not found -- check AWS tags")
        ok(f"Instance: {data['ID']} -- IP: {data['IP']}")
        return data["ID"], data["IP"]
    except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as e:
        die(f"Failed to retrieve instance info: {e}")
