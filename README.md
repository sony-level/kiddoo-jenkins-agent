# kiddoo-server — EC2 Jenkins Agent

Creates an AWS EC2 Debian 13 server configured as a Jenkins agent.

## Prerequisites

- Python >= 3.10, AWS CLI >= 2, `jq`, `curl`
- AWS credentials configured (`aws configure`)
- `pip install -r requirements.txt`

## Configuration

```bash
cp .env.example .env
# Edit .env with your values
```

All variables can be set in `.env` instead of passing CLI flags.

## Quick start

```bash
cd scripts/server/python

# Minimal — default VPC, auto-detected IP
python3 create_server.py

# Custom instance + SSH key
python3 create_server.py --type t3.small --ssh-key-file ~/.ssh/id_ed25519.pub

# With Discord notifications
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/ID/TOKEN" \
  python3 create_server.py

# Dry-run
python3 create_server.py --dry-run
```

## Options

| Flag                 | Default        | Description              |
| -------------------- | -------------- | ------------------------ |
| `-r, --region`       | `eu-west-3`    | AWS region               |
| `-t, --type`         | `t3.micro`     | EC2 instance type        |
| `-p, --ssh-port`     | `2222`         | SSH port                 |
| `-c, --ssh-cidr`     | caller IP/32   | Allowed SSH CIDR         |
| `-k, --ssh-key-file` | —              | SSH public key to import |
| `-s, --volume-size`  | `30`           | Root volume (GiB)        |
| `--vpc-id`           | default VPC    | Target VPC               |
| `--subnet-id`        | default subnet | Target subnet            |
| `-n, --dry-run`      | —              | Plan only                |

## What gets installed (cloud-init)

1. Base packages + Python
2. Docker Engine
3. Ansible
4. Terraform
5. Jenkins agent user
6. SSH hardening + UFW

Logs on instance: `/var/log/kiddoo-server-setup.log`

## Discord notifications

Set `DISCORD_WEBHOOK_URL` to receive provisioning events. Omit to skip silently.
