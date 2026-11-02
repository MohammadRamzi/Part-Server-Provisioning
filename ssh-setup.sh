#!/bin/bash

set -Eeuo pipefail

# ==========================================
# SSH Server Configuration
# Debian 13 - Emperor Penguin Project
# ==========================================

SSH_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSH_CONFIG="$SSH_CONFIG_DIR/00-emperor-penguin.conf"
SSH_CONFIG_MAIN="/etc/ssh/sshd_config"
BANNER_FILE="/etc/issue.net"

SSH_PORT=2222
SSH_USER="part"
SSH_INTERVAL=300
BANNER_MESSAGE="Hello from Emperor Penguin"

# ---------- Helper Functions ----------

print_message() {
    echo -e "\n[INFO] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
}

error_handler() {
    print_error "Script failed at line $1"
}

trap 'error_handler $LINENO' ERR

# ---------- 1. Pre-checks ----------

print_message "Checking system requirements..."

if [[ $EUID -ne 0 ]]; then
    print_error "Please run this script as root."
    exit 1
fi

if ! command -v sshd >/dev/null 2>&1; then
    print_error "OpenSSH Server is not installed."
    exit 1
fi

if ! id "$SSH_USER" >/dev/null 2>&1; then
    print_error "SSH user '$SSH_USER' does not exist."
    exit 1
fi

if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*\.conf' "$SSH_CONFIG_MAIN"; then
    print_error "Expected SSH Include directive not found."
    exit 1
fi

print_success "Requirements verified."

# ---------- 2. Backup ----------

print_message "Backing up SSH configuration..."

BACKUP_DIR="/root/ssh-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

cp -a "$SSH_CONFIG_MAIN" "$BACKUP_DIR/"
cp -a "$SSH_CONFIG_DIR" "$BACKUP_DIR/"
cp -a "$BANNER_FILE" "$BACKUP_DIR/" 2>/dev/null || true

print_success "Backup created at $BACKUP_DIR."

# ---------- 3. Install OpenSSH Server ----------

print_message "Checking OpenSSH Server..."

if ! dpkg-query -W -f='${Status}' openssh-server 2>/dev/null | grep -q "install ok installed"; then
    print_error "OpenSSH Server is not installed."
    exit 1
fi

systemctl enable ssh

print_success "OpenSSH Server is installed and enabled."

# ---------- 4. Configure Banner ----------

print_message "Configuring SSH Banner..."

printf '%s\n' "$BANNER_MESSAGE" > "$BANNER_FILE"
chmod 644 "$BANNER_FILE"

print_success "SSH Banner configured."

# ---------- 5. Configure SSH ----------

print_message "Creating SSH configuration..."

mkdir -p "$SSH_CONFIG_DIR"

cat > "$SSH_CONFIG" <<EOF
# Emperor Penguin Project - SSH Configuration

Port $SSH_PORT

PermitRootLogin no
AllowUsers $SSH_USER

Banner $BANNER_FILE

ClientAliveInterval $SSH_INTERVAL
EOF

chmod 644 "$SSH_CONFIG"

print_success "SSH configuration written."

# ---------- 6. Validate Configuration ----------

print_message "Validating SSH configuration..."

if ! sshd -t; then
    print_error "Invalid SSH configuration. Service was not reloaded."
    exit 1
fi

EFFECTIVE_CONFIG=$(sshd -T)

check_setting() {
    local key="$1"
    local expected="$2"

    if ! grep -Fxq "$key $expected" <<< "$EFFECTIVE_CONFIG"; then
        print_error "Unexpected SSH setting: $key"
        exit 1
    fi
}

check_setting "port" "$SSH_PORT"
check_setting "permitrootlogin" "no"
check_setting "banner" "$BANNER_FILE"
check_setting "clientaliveinterval" "$SSH_INTERVAL"

if ! grep -Fxq "allowusers $SSH_USER" <<< "$EFFECTIVE_CONFIG"; then
    print_error "AllowUsers is not configured correctly."
    exit 1
fi

print_success "SSH configuration validated."

# ---------- 7. Reload SSH ----------

print_message "Reloading SSH service..."

systemctl reload ssh

if ! systemctl is-active --quiet ssh; then
    print_error "SSH service is not active."
    exit 1
fi

print_success "SSH service reloaded."

# ---------- 8. Final Verification ----------

print_message "Final SSH configuration..."

sshd -T | grep -E '^(port|permitrootlogin|allowusers|banner|clientaliveinterval|clientalivecountmax) '

echo

ss -tlnp | grep ssh

print_success "SSH configuration completed successfully!"
