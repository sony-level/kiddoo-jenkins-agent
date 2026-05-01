#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File    : lib/aws_network.sh
# Version : 1.0.0
# Purpose : AWS network operations -- VPC, subnet, security group, SSH key pair
# Author  : kiddoo-infra
# Requires: lib/utils.sh (log / ok / warn / die), AWS_REGION,
#           SERVER_NAME, SSH_PORT must be set by the caller
# -----------------------------------------------------------------------------

# --- Resolve VPC: use VPC_ID if set, otherwise fall back to the default VPC --
resolve_vpc() {
  if [[ -n "${VPC_ID:-}" ]]; then
    ok "VPC (provided): ${VPC_ID}"
    echo "${VPC_ID}"
    return
  fi
  local id
  id=$(aws ec2 describe-vpcs \
    --region "${AWS_REGION}" \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" --output text)
  [[ "$id" == "None" || -z "$id" ]] \
    && die "No default VPC found -- set VPC_ID=vpc-xxx"
  ok "VPC (default): ${id}"
  echo "${id}"
}

# --- Resolve subnet: use SUBNET_ID if set, otherwise use the first default ---
resolve_subnet() {
  local vpc_id="$1"
  if [[ -n "${SUBNET_ID:-}" ]]; then
    ok "Subnet (provided): ${SUBNET_ID}"
    echo "${SUBNET_ID}"
    return
  fi
  local id
  id=$(aws ec2 describe-subnets \
    --region "${AWS_REGION}" \
    --filters "Name=vpc-id,Values=${vpc_id}" "Name=default-for-az,Values=true" \
    --query "Subnets[0].SubnetId" --output text)
  [[ "$id" == "None" || -z "$id" ]] \
    && die "No default subnet found -- set SUBNET_ID=subnet-xxx"
  ok "Subnet (default): ${id}"
  echo "${id}"
}

# --- Create security group if it does not exist, or return the existing one --
create_or_get_sg() {
  local vpc_id="$1" ssh_cidr="$2"
  local sg_name="${SERVER_NAME}-sg"

  local existing
  existing=$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters "Name=group-name,Values=${sg_name}" "Name=vpc-id,Values=${vpc_id}" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")

  if [[ "$existing" != "None" && -n "$existing" ]]; then
    warn "Security group '${sg_name}' already exists (${existing}), reusing it"
    echo "${existing}"
    return
  fi

  log "Creating security group '${sg_name}'..."
  local sg_id
  sg_id=$(aws ec2 create-security-group \
    --region "${AWS_REGION}" \
    --group-name "${sg_name}" \
    --description "SG ${SERVER_NAME} - SSH ${ssh_cidr} port ${SSH_PORT}" \
    --vpc-id "${vpc_id}" \
    --query "GroupId" --output text)

  # Allow SSH inbound only from the authorized CIDR
  aws ec2 authorize-security-group-ingress \
    --region "${AWS_REGION}" \
    --group-id "${sg_id}" \
    --protocol tcp --port "${SSH_PORT}" --cidr "${ssh_cidr}" \
    --output text > /dev/null

  aws ec2 create-tags \
    --region "${AWS_REGION}" --resources "${sg_id}" \
    --tags "Key=Name,Value=${sg_name}" \
           "Key=ManagedBy,Value=script"

  ok "Security group created: ${sg_id}"
  echo "${sg_id}"
}

# --- Import an SSH public key as an EC2 key pair if it does not exist --------
import_ssh_key() {
  local key_file="${SSH_PUBLIC_KEY_FILE:-}"
  if [[ -z "$key_file" ]]; then
    echo ""
    return
  fi

  local key_name="kiddoo-server"
  if aws ec2 describe-key-pairs \
       --region "${AWS_REGION}" --key-names "${key_name}" &>/dev/null; then
    warn "Key pair '${key_name}' already exists, reusing it"
  else
    log "Importing SSH public key '${key_name}'..."
    aws ec2 import-key-pair \
      --region "${AWS_REGION}" \
      --key-name "${key_name}" \
      --public-key-material "fileb://${key_file}" \
      --no-cli-pager > /dev/null 2>&1
    ok "Key pair '${key_name}' imported"
  fi
  echo "${key_name}"
}
