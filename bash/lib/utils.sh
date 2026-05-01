#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File    : lib/utils.sh
# Version : 1.0.0
# Purpose : Utility functions — logging, colors, prerequisites, SSH wait
# Author  : kiddoo-infra
# -----------------------------------------------------------------------------

readonly COLOR_RESET='\033[0m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BOLD='\033[1m'

# --- Logging helpers ----------------------------------------------------------
log()     { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET}    $*" >&2; }
ok()      { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}      $*" >&2; }
warn()    { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET}    $*" >&2; }
die()     { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET}   $*" >&2; exit 1; }
section() {
  echo -e "\n${COLOR_BOLD}================================================${COLOR_RESET}" >&2
  echo -e "${COLOR_BOLD}  $*${COLOR_RESET}" >&2
  echo -e "${COLOR_BOLD}================================================${COLOR_RESET}" >&2
}

# --- Check that required tools and AWS credentials are available --------------
check_prerequisites() {
  local missing=()
  for cmd in aws jq curl; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -gt 0 ]] && die "Missing required tools: ${missing[*]}"

  aws sts get-caller-identity --region "${AWS_REGION}" --output text &>/dev/null \
    || die "AWS credentials are not configured or region '${AWS_REGION}' is unreachable"
  ok "Prerequisites verified"
}

# --- Retrieve the public IP of the machine running this script ----------------
get_caller_ip() {
  curl -sf --max-time 5 https://checkip.amazonaws.com \
    || curl -sf --max-time 5 https://api.ipify.org \
    || die "Cannot determine public IP -- pass --ssh-cidr manually"
}

# --- Poll SSH port until it responds or timeout is reached -------------------
# Usage: wait_for_ssh <ip> <port> [max_attempts]
wait_for_ssh() {
  local ip="$1" port="$2" attempts="${3:-30}"
  log "Waiting for SSH on ${ip}:${port}..."
  for _ in $(seq 1 "${attempts}"); do
    if timeout 5 bash -c "echo > /dev/tcp/${ip}/${port}" 2>/dev/null; then
      ok "SSH is available on ${ip}:${port}"
      return 0
    fi
    echo -n "."
    sleep 10
  done
  echo ""
  warn "SSH not available after $((attempts * 10))s -- the server may still be booting"
  return 1
}

# --- Print final connection summary ------------------------------------------
print_summary() {
  local instance_id="$1" public_ip="$2" ssh_port="$3"
  echo ""
  section "Server is ready"
  echo -e "  Instance   : ${COLOR_GREEN}${instance_id}${COLOR_RESET}" >&2
  echo -e "  Public IP  : ${COLOR_GREEN}${public_ip}${COLOR_RESET}" >&2
  echo -e "  SSH        : ${COLOR_GREEN}ssh -p ${ssh_port} admin@${public_ip}${COLOR_RESET}" >&2
  echo "" >&2
  log "The server is provisioning itself via cloud-init."
  log "Check /var/log/kiddoo-server-setup.log on the instance for progress."
}
