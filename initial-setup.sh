#!/bin/bash

set -Eeuo pipefail

# ==========================================
# Initial Server Setup
# Debian 13 - Emperor Penguin Project
# ==========================================

TARGET_USER="part"
HOSTNAME="ep4-node"
TIMEZONE="Asia/Tehran"
MAX_LOGINS=5
LIMITS_FILE="/etc/security/limits.conf"

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

source /etc/os-release

if [[ "$ID" != "debian" || "$VERSION_ID" != "13" ]]; then
    print_error "This script requires Debian 13."
    exit 1
fi

for cmd in adduser usermod passwd apt-get hostnamectl timedatectl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "Required command not found: $cmd"
        exit 1
    fi
done

print_success "System requirements verified."

# ---------- 2. User Configuration ----------

print_message "Configuring user: $TARGET_USER"

if ! id "$TARGET_USER" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$TARGET_USER"
    print_success "User created: $TARGET_USER"
else
    print_message "User already exists."
fi

if ! getent group sudo >/dev/null; then
    print_error "sudo group does not exist."
    exit 1
fi

if ! id -nG "$TARGET_USER" | grep -qw sudo; then
    usermod -aG sudo "$TARGET_USER"
    print_success "User added to sudo group."
else
    print_message "User is already in sudo group."
fi

# Ensure the account has a usable password.

PASSWORD_STATUS=$(passwd -S "$TARGET_USER" | awk '{print $2}')

if [[ "$PASSWORD_STATUS" != "P" ]]; then
    print_message "Set a password for $TARGET_USER:"
    passwd "$TARGET_USER"
fi

# ---------- 3. Login Restrictions ----------

print_message "Configuring maximum login sessions..."

for service in login sshd; do
    if ! grep -Eq '^[[:space:]]*session[[:space:]].*pam_limits\.so' "/etc/pam.d/$service"; then
        print_error "pam_limits.so is not configured for $service."
        exit 1
    fi
done

LIMIT_RULE="$TARGET_USER hard maxlogins $MAX_LOGINS"

if ! grep -Eq "^[[:space:]]*$TARGET_USER[[:space:]]+hard[[:space:]]+maxlogins[[:space:]]+$MAX_LOGINS([[:space:]]*(#.*)?$)" "$LIMITS_FILE"; then

    cp -a "$LIMITS_FILE" "$LIMITS_FILE.bak"

    sed -i -E "/^[[:space:]]*$TARGET_USER[[:space:]]+hard[[:space:]]+maxlogins([[:space:]]|$)/d" "$LIMITS_FILE"

    echo "$LIMIT_RULE" >> "$LIMITS_FILE"

    print_success "Maximum login sessions set to $MAX_LOGINS."
else
    print_message "Login restriction already configured."
fi

# ---------- 4. Repository & Packages ----------

print_message "Updating Debian package repositories..."

# apt-get update

print_success "Package lists updated."

print_message "Upgrading installed packages..."

# DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

print_success "System packages upgraded."

# ---------- 5. Hostname ----------

print_message "Configuring hostname..."

if [[ "$(hostnamectl --static)" != "$HOSTNAME" ]]; then
    hostnamectl set-hostname "$HOSTNAME"
    print_success "Hostname changed to $HOSTNAME."
else
    print_message "Hostname is already configured."
fi

# ---------- 6. Timezone ----------

print_message "Configuring timezone..."

CURRENT_TIMEZONE=$(timedatectl show -p Timezone --value)

if [[ "$CURRENT_TIMEZONE" != "$TIMEZONE" ]]; then
    timedatectl set-timezone "$TIMEZONE"
    print_success "Timezone changed to $TIMEZONE."
else
    print_message "Timezone is already configured."
fi

# ---------- 7. Final Verification ----------

print_message "Verifying final configuration..."

id "$TARGET_USER"

echo
echo "Hostname: $(hostnamectl --static)"
echo "Timezone: $(timedatectl show -p Timezone --value)"

echo
grep -E "^[[:space:]]*$TARGET_USER[[:space:]]+hard[[:space:]]+maxlogins" "$LIMITS_FILE"

print_success "Initial server setup completed successfully!"
