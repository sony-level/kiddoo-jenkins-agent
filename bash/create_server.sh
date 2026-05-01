#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File    : bash/create_server.sh
# Version : 2.0.0
# Purpose : AWS provisioning engine -- creates an EC2 Debian server configured
#           as a Jenkins agent.  Called exclusively by python/create_server.py.
# Author  : Level sony
# Prerequisites : aws-cli >= 2, jq, curl
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load .env if present (won't override already-set variables)
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source <(grep -v '^\s*#' "${PROJECT_ROOT}/.env" | grep -v '^\s*$')
  set +a
fi

# Load library modules
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"
# shellcheck source=lib/aws_network.sh
source "${SCRIPT_DIR}/lib/aws_network.sh"
# shellcheck source=lib/aws_compute.sh
source "${SCRIPT_DIR}/lib/aws_compute.sh"
# shellcheck source=lib/user_data.sh
source "${SCRIPT_DIR}/lib/user_data.sh"

# --- Default values (can be overridden by CLI flags or environment variables) -
AWS_REGION="${AWS_REGION:-eu-west-3}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
SSH_PORT="${SSH_PORT:-2222}"
ROOT_VOLUME_GIB="${ROOT_VOLUME_GIB:-30}"
SSH_CIDR="${SSH_CIDR:-}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-}"
VPC_ID="${VPC_ID:-}"
SUBNET_ID="${SUBNET_ID:-}"
DRY_RUN=false
SERVER_NAME="kiddoo-jenkins-agent"

# --- Parse CLI arguments ------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region)       AWS_REGION="$2";           shift 2 ;;
    -t|--type)         INSTANCE_TYPE="$2";        shift 2 ;;
    -p|--ssh-port)     SSH_PORT="$2";             shift 2 ;;
    -c|--ssh-cidr)     SSH_CIDR="$2";             shift 2 ;;
    -k|--ssh-key-file) SSH_PUBLIC_KEY_FILE="$2";  shift 2 ;;
    -s|--volume-size)  ROOT_VOLUME_GIB="$2";      shift 2 ;;
       --vpc-id)       VPC_ID="$2";               shift 2 ;;
       --subnet-id)    SUBNET_ID="$2";            shift 2 ;;
    -n|--dry-run)      DRY_RUN=true;              shift ;;
    *) die "Unknown option: '$1'" ;;
  esac
done

# --- Main program -------------------------------------------------------------
main() {
  section "Kiddoo Infra -- EC2 Server Provisioning"
  log "Region       : ${AWS_REGION}"
  log "Instance     : ${INSTANCE_TYPE}"
  log "SSH port     : ${SSH_PORT}"
  log "Volume       : ${ROOT_VOLUME_GIB} GiB"

  check_prerequisites

  if [[ -z "${SSH_CIDR}" ]]; then
    SSH_CIDR="$(get_caller_ip)/32"
    log "SSH CIDR auto-detected: ${SSH_CIDR}"
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    warn "Dry-run mode -- no resources will be created"
    return 0
  fi

  local ami_id vpc_id subnet_id sg_id key_name instance_id public_ip
  ami_id=$(find_latest_debian_ami)
  vpc_id=$(resolve_vpc)
  subnet_id=$(resolve_subnet "${vpc_id}")
  sg_id=$(create_or_get_sg "${vpc_id}" "${SSH_CIDR}")
  key_name=$(import_ssh_key)

  instance_id=$(launch_instance "${ami_id}" "${sg_id}" "${subnet_id}" "${key_name}")
  public_ip=$(attach_eip "${instance_id}")

  wait_for_ssh "${public_ip}" "${SSH_PORT}" || true
  validate_instance "${instance_id}" || true

  print_summary "${instance_id}" "${public_ip}" "${SSH_PORT}"
}

main
