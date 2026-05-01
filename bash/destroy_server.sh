#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File    : bash/destroy_server.sh
# Version : 1.0.0
# Purpose : Cleanup script -- terminates the kiddoo-jenkins-agent EC2 instance
#           and removes all associated AWS resources (EIP, SG, key pair).
# Author  : kiddoo-infra
# Prerequisites : aws-cli >= 2, jq
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load .env if present
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source <(grep -v '^\s*#' "${PROJECT_ROOT}/.env" | grep -v '^\s*$')
  set +a
fi

# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

AWS_REGION="${AWS_REGION:-eu-west-3}"
SERVER_NAME="kiddoo-jenkins-agent"
SG_NAME="${SERVER_NAME}-sg"
KEY_NAME="kiddoo-server"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region) AWS_REGION="$2"; shift 2 ;;
    -f|--force)  FORCE=true;      shift ;;
    *) die "Unknown option: '$1'" ;;
  esac
done

# --- Confirmation prompt ------------------------------------------------------
confirm() {
  if [[ "${FORCE}" == "true" ]]; then return 0; fi
  echo ""
  warn "This will permanently destroy ALL '${SERVER_NAME}' resources in ${AWS_REGION}:"
  echo "  - EC2 instances"
  echo "  - Elastic IPs"
  echo "  - Security group '${SG_NAME}'"
  echo "  - Key pair '${KEY_NAME}'"
  echo ""
  read -rp "Are you sure? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
}

# --- Terminate EC2 instances --------------------------------------------------
destroy_instances() {
  log "Looking for running instances tagged '${SERVER_NAME}'..."
  local ids
  ids=$(aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Name,Values=${SERVER_NAME}" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" --output text)

  if [[ -z "$ids" || "$ids" == "None" ]]; then
    warn "No instances found"
    return
  fi

  for id in $ids; do
    log "Terminating instance ${id}..."
    aws ec2 terminate-instances \
      --region "${AWS_REGION}" --instance-ids "${id}" --output text > /dev/null
    ok "Instance ${id} terminating"
  done

  log "Waiting for instances to terminate..."
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated \
    --region "${AWS_REGION}" --instance-ids $ids
  ok "All instances terminated"
}

# --- Release Elastic IPs -----------------------------------------------------
destroy_eips() {
  log "Looking for Elastic IPs tagged '${SERVER_NAME}'..."
  local alloc_ids
  alloc_ids=$(aws ec2 describe-addresses \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Name,Values=${SERVER_NAME}" \
    --query "Addresses[].AllocationId" --output text)

  if [[ -z "$alloc_ids" || "$alloc_ids" == "None" ]]; then
    warn "No Elastic IPs found"
    return
  fi

  for alloc_id in $alloc_ids; do
    # Disassociate first if attached
    local assoc_id
    assoc_id=$(aws ec2 describe-addresses \
      --region "${AWS_REGION}" --allocation-ids "${alloc_id}" \
      --query "Addresses[0].AssociationId" --output text)
    if [[ -n "$assoc_id" && "$assoc_id" != "None" ]]; then
      aws ec2 disassociate-address \
        --region "${AWS_REGION}" --association-id "${assoc_id}"
    fi

    log "Releasing EIP ${alloc_id}..."
    aws ec2 release-address \
      --region "${AWS_REGION}" --allocation-id "${alloc_id}"
    ok "EIP ${alloc_id} released"
  done
}

# --- Delete security group ----------------------------------------------------
destroy_sg() {
  log "Looking for security group '${SG_NAME}'..."
  local sg_id
  sg_id=$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters "Name=group-name,Values=${SG_NAME}" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")

  if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
    warn "Security group '${SG_NAME}' not found"
    return
  fi

  log "Deleting security group ${sg_id}..."
  aws ec2 delete-security-group \
    --region "${AWS_REGION}" --group-id "${sg_id}" > /dev/null
  ok "Security group ${sg_id} deleted"
}

# --- Delete key pair ----------------------------------------------------------
destroy_key_pair() {
  log "Looking for key pair '${KEY_NAME}'..."
  if ! aws ec2 describe-key-pairs \
       --region "${AWS_REGION}" --key-names "${KEY_NAME}" &>/dev/null; then
    warn "Key pair '${KEY_NAME}' not found"
    return
  fi

  log "Deleting key pair '${KEY_NAME}'..."
  aws ec2 delete-key-pair \
    --region "${AWS_REGION}" --key-name "${KEY_NAME}" > /dev/null
  ok "Key pair '${KEY_NAME}' deleted"
}

# --- Main ---------------------------------------------------------------------
main() {
  section "Kiddoo Infra -- Cleanup"
  log "Region: ${AWS_REGION}"

  check_prerequisites
  confirm

  destroy_instances
  destroy_eips
  destroy_sg
  destroy_key_pair

  section "Cleanup complete"
}

main
