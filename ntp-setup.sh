#!/bin/bash

set -Eeuo pipefail

# Configuration
CONFIG_DIR="/etc/systemd/timesyncd.conf.d"
CONFIG_FILE="${CONFIG_DIR}/10-iran-ntp.conf"

NTP_SERVERS=(
    "0.ir.pool.ntp.org"
    "1.ir.pool.ntp.org"
    "2.ir.pool.ntp.org"
    "3.ir.pool.ntp.org"
)

SERVICE="systemd-timesyncd"

# Logging
print_message() {
    local type="$1"
    shift
    printf '[%s] %s\n' "$type" "$*"
}

error_handler() {
    local exit_code=$?
    print_message "ERROR" "Script failed at line ${BASH_LINENO[0]} (exit code: ${exit_code})."
    exit "$exit_code"
}

trap error_handler ERR

# Root check
if [[ "$EUID" -ne 0 ]]; then
    print_message "ERROR" "Please run this script with sudo."
    exit 1
fi

print_message "INFO" "Starting NTP configuration..."

# Check Debian version
if [[ ! -f /etc/os-release ]]; then
    print_message "ERROR" "/etc/os-release not found."
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
    print_message "ERROR" "This script requires Debian 13."
    exit 1
fi

# Check required commands
for cmd in systemctl timedatectl systemd-analyze; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_message "ERROR" "Required command not found: $cmd"
        exit 1
    fi
done

# Install systemd-timesyncd if needed
if ! dpkg-query -W -f='${Status}' systemd-timesyncd 2>/dev/null | grep -q "install ok installed"; then
    print_message "INFO" "Installing systemd-timesyncd..."

    if ! apt-get update || ! apt-get install -y systemd-timesyncd; then
        print_message "ERROR" "Package installation failed. Check repository access."
        exit 1
    fi
else
    print_message "INFO" "systemd-timesyncd is already installed."
fi

# Check for conflicting time synchronization services
for service in chrony.service ntp.service ntpsec.service; do
    if systemctl is-active --quiet "$service"; then
        print_message "ERROR" "Conflicting time service is active: $service"
        exit 1
    fi
done

# Create configuration directory
mkdir -p "$CONFIG_DIR"

# Prepare desired configuration
desired_config=$(printf '[Time]\nNTP=%s\n' "${NTP_SERVERS[*]}")

# Update configuration only if needed
if [[ ! -f "$CONFIG_FILE" ]] || [[ "$(cat "$CONFIG_FILE")" != "$desired_config" ]]; then
    if [[ -f "$CONFIG_FILE" ]]; then
        cp -a "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    printf '%s\n' "$desired_config" > "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    print_message "INFO" "NTP configuration updated."
else
    print_message "INFO" "NTP configuration is already correct."
fi

# Enable and restart service
systemctl enable "$SERVICE"
systemctl restart "$SERVICE"

# Verify effective configuration
effective_config=$(systemd-analyze cat-config systemd/timesyncd.conf)

if ! grep -Fq "NTP=${NTP_SERVERS[*]}" <<< "$effective_config"; then
    print_message "ERROR" "NTP configuration verification failed."
    exit 1
fi

# Verify service state
if ! systemctl is-active --quiet "$SERVICE"; then
    print_message "ERROR" "NTP service is not running."
    exit 1
fi

print_message "INFO" "NTP service is active."

# Display synchronization status
print_message "INFO" "Current time synchronization status:"
timedatectl status
timedatectl timesync-status

print_message "SUCCESS" "NTP configuration completed."
