#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File    : lib/aws_compute.sh
# Version : 1.1.0
# Purpose : AWS compute operations -- AMI lookup, EC2 launch, EIP,
#           instance health validation
# Author  : level-sony
# Requires: lib/utils.sh (log / ok / warn / die), lib/user_data.sh (build_user_data),
#           AWS_REGION, SERVER_NAME, INSTANCE_TYPE, SSH_PORT,
#           ROOT_VOLUME_GIB must be set
# -----------------------------------------------------------------------------

readonly DEBIAN_13_OWNER="136693071363"
readonly DEBIAN_13_FILTER="debian-13-amd64-*"

# --- Find the latest available Debian 13 (amd64) AMI in the target region ----
find_latest_debian_ami() {
  log "Looking for the latest Debian 13 AMI in ${AWS_REGION}..."
  local ami_id
  ami_id=$(aws ec2 describe-images \
    --region "${AWS_REGION}" \
    --owners "${DEBIAN_13_OWNER}" \
    --filters \
      "Name=name,Values=${DEBIAN_13_FILTER}" \
      "Name=state,Values=available" \
      "Name=architecture,Values=x86_64" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)
  [[ "$ami_id" == "None" || -z "$ami_id" ]] \
    && die "No Debian 13 AMI found in ${AWS_REGION}"
  ok "AMI: ${ami_id}"
  echo "${ami_id}"
}

# --- Launch an EC2 instance with the given parameters ------------------------
launch_instance() {
  local ami_id="$1" sg_id="$2" subnet_id="$3" key_name="${4:-}"
  log "Launching EC2 instance (${INSTANCE_TYPE}, AMI: ${ami_id})..."

  local key_args=()
  [[ -n "$key_name" ]] && key_args=(--key-name "${key_name}")

  local block_devs
  block_devs=$(printf \
    '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":%d,"VolumeType":"gp3","DeleteOnTermination":true,"Encrypted":true}}]' \
    "${ROOT_VOLUME_GIB}")

  local tags
  tags="ResourceType=instance,Tags=[\
{Key=Name,Value=${SERVER_NAME}},\
{Key=ManagedBy,Value=script}]"

  local instance_id
  instance_id=$(aws ec2 run-instances \
    --region "${AWS_REGION}" \
    --image-id "${ami_id}" \
    --instance-type "${INSTANCE_TYPE}" \
    --security-group-ids "${sg_id}" \
    --subnet-id "${subnet_id}" \
    --user-data "$(build_user_data)" \
    --block-device-mappings "${block_devs}" \
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
    --tag-specifications "${tags}" \
    "${key_args[@]}" \
    --query "Instances[0].InstanceId" --output text)

  ok "Instance launched: ${instance_id}"
  echo "${instance_id}"
}

# --- Allocate an Elastic IP and associate it with the running instance -------
attach_eip() {
  local instance_id="$1"
  log "Allocating an Elastic IP..."

  local alloc_id
  alloc_id=$(aws ec2 allocate-address \
    --region "${AWS_REGION}" --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[\
{Key=Name,Value=${SERVER_NAME}}]" \
    --query "AllocationId" --output text)

  log "Waiting for instance ${instance_id} to reach 'running'..."
  aws ec2 wait instance-running \
    --region "${AWS_REGION}" --instance-ids "${instance_id}"
  ok "Instance is running"

  aws ec2 associate-address \
    --region "${AWS_REGION}" \
    --instance-id "${instance_id}" \
    --allocation-id "${alloc_id}" \
    --output text > /dev/null

  local public_ip
  public_ip=$(aws ec2 describe-addresses \
    --region "${AWS_REGION}" --allocation-ids "${alloc_id}" \
    --query "Addresses[0].PublicIp" --output text)

  ok "Elastic IP attached: ${public_ip}"
  echo "${public_ip}"
}

# --- Run AWS instance status checks and display results ----------------------
validate_instance() {
  local instance_id="$1"
  log "Running AWS status checks for ${instance_id}..."
  aws ec2 describe-instance-status \
    --region "${AWS_REGION}" \
    --instance-ids "${instance_id}" \
    --query "InstanceStatuses[0].{System:SystemStatus.Status,Instance:InstanceStatus.Status}" \
    --output table
}
