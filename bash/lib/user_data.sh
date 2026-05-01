#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File    : lib/user_data.sh
# Version : 1.0.0
# Purpose : Build and base64-encode the cloud-init user data script that
#           configures the instance as a Jenkins agent.
# Author  : Level sony
# Requires: lib/utils.sh (log), SSH_PORT and DISCORD_WEBHOOK_URL must be set
# -----------------------------------------------------------------------------

# --- Build and base64-encode the cloud-init user data script -----------------
# Sets up the server as a Jenkins agent:
#   1. System update + base packages + Python
#   2. Docker Engine
#   3. Ansible   (via gist)
#   4. Terraform (via gist)
#   5. SSH hardening + UFW
# Discord notifications are sent after each step.
build_user_data() {
  sed \
    -e "s/__SSH_PORT__/${SSH_PORT}/g" \
    -e "s|__DISCORD_WEBHOOK_URL__|${DISCORD_WEBHOOK_URL:-}|g" \
    <<'SCRIPT' | base64 -w 0
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export HOME="/root"

DISCORD_WEBHOOK_URL="__DISCORD_WEBHOOK_URL__"
LOG_FILE="/var/log/kiddoo-server-setup.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# Send an embed notification to Discord
discord_step() {
  local desc="$1" color="${2:-3447003}"
  [[ -z "${DISCORD_WEBHOOK_URL}" ]] && return 0
  curl -sf -X POST "${DISCORD_WEBHOOK_URL}" \
    -H "Content-Type: application/json" \
    --max-time 10 \
    -d "{\"embeds\":[{\"title\":\"kiddoo-server\",\"description\":\"${desc}\",\"color\":${color}}]}" \
    || true
}

# --- Step 1: system update and base packages ----------------------------------
discord_step "Step 1/4: updating system and installing base packages..." 3447003
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget git vim unzip ca-certificates \
  gnupg lsb-release fail2ban ufw \
  python3 python3-pip python3-venv python3-dev
discord_step "Step 1/4: base packages ready" 5763719

# --- Step 2: Docker Engine ----------------------------------------------------
discord_step "Step 2/4: installing Docker Engine..." 3447003
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -qq
apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
discord_step "Step 2/4: Docker Engine installed and started" 5763719

# --- Step 3: Ansible ----------------------------------------------------------
discord_step "Step 3/4: installing Ansible..." 3447003
curl -fsSL \
  "https://gist.githubusercontent.com/sony-level/cc7cea1bbc154009949fde84b00b5c27/raw/b3cb26482e41da2778de510aa6c38ca13ab5f966/install-ansible.sh" \
  | bash
discord_step "Step 3/4: Ansible installed" 5763719

# --- Step 4: Terraform --------------------------------------------------------
discord_step "Step 4/4: installing Terraform..." 3447003
curl -fsSL \
  "https://gist.githubusercontent.com/sony-level/cc042b1e61aef2165ff192cf43f738db/raw/eb96c203e2c48c16e89555f442bd65240e659695/install-terraform.sh" \
  | bash
discord_step "Step 4/4: Terraform installed" 5763719

# --- SSH hardening ------------------------------------------------------------
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
Port __SSH_PORT__
 PermitRootLogin no
 PasswordAuthentication no
ChallengeResponseAuthentication no
X11Forwarding no
MaxAuthTries 3
AllowAgentForwarding no
EOF

# --- Firewall -----------------------------------------------------------------
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow __SSH_PORT__/tcp comment "SSH"
ufw --force enable

systemctl restart ssh || systemctl restart sshd
touch /var/lib/cloud/instance/server-bootstrapped
discord_step "kiddoo-server is ready as a Jenkins agent" 5763719
SCRIPT
}
