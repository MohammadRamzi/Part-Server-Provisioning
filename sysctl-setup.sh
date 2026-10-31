
#!/usr/bin/env bash

set -Eeuo pipefail

# ==========================================
# Emperor Penguin - Kernel Optimization
# ==========================================

CONFIG_FILE="/etc/sysctl.d/99-emperor-penguin.conf"
BACKUP_DIR="/root/sysctl-backups"

DESIRED_CONFIG=$(cat <<'EOF'
# Emperor Penguin - Kernel Optimization

# Ignore all ICMP Echo requests (Ping)
net.ipv4.icmp_echo_ignore_all = 1

# Reduce swap tendency
vm.swappiness = 10
EOF
)

# ------------------------------------------
# Utility functions
# ------------------------------------------

print_message() {
    local level="$1"
    local message="$2"

    printf '[%s] %s\n' "$level" "$message"
}

error_exit() {
    print_message "ERROR" "$1"
    exit 1
}

# ------------------------------------------
# Error handling
# ------------------------------------------

trap 'error_exit "An unexpected error occurred at line $LINENO."' ERR

# ------------------------------------------
# Pre-checks
# ------------------------------------------

print_message "INFO" "Starting kernel optimization..."

if [[ "$EUID" -ne 0 ]]; then
    error_exit "Please run this script as root or using sudo."
fi

if [[ ! -f /etc/os-release ]]; then
    error_exit "Cannot identify the operating system."
fi

source /etc/os-release

if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "13" ]]; then
    error_exit "This script is designed for Debian 13."
fi

SYSCTL_BIN="/usr/sbin/sysctl"

if [[ ! -x "$SYSCTL_BIN" ]]; then
    error_exit "sysctl was not found. Please install procps first."
fi

print_message "INFO" "System checks passed."

# ------------------------------------------
# Backup existing configuration
# ------------------------------------------

mkdir -p "$BACKUP_DIR"

config_changed=false

if [[ -f "$CONFIG_FILE" ]] &&
   [[ "$(cat "$CONFIG_FILE")" != "$DESIRED_CONFIG" ]]; then

    BACKUP_FILE="$BACKUP_DIR/99-emperor-penguin.conf.$(date +%Y%m%d-%H%M%S)"

    cp -a "$CONFIG_FILE" "$BACKUP_FILE"

    print_message "INFO" "Previous configuration backed up to $BACKUP_FILE"
fi

# ------------------------------------------
# Write configuration
# ------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]] ||
   [[ "$(cat "$CONFIG_FILE")" != "$DESIRED_CONFIG" ]]; then

    printf '%s\n' "$DESIRED_CONFIG" > "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    config_changed=true

    print_message "INFO" "Sysctl configuration updated."

else
    print_message "INFO" "Configuration is already correct."
fi

# ------------------------------------------
# Apply kernel parameters
# ------------------------------------------

if [[ "$config_changed" == true ]]; then

    "$SYSCTL_BIN" -p "$CONFIG_FILE"

    print_message "INFO" "Kernel parameters applied."

else
    print_message "INFO" "No configuration changes detected."
fi

# ------------------------------------------
# Verify configuration
# ------------------------------------------

ICMP_VALUE=$("$SYSCTL_BIN" -n net.ipv4.icmp_echo_ignore_all)
SWAPPINESS_VALUE=$("$SYSCTL_BIN" -n vm.swappiness)

if [[ "$ICMP_VALUE" != "1" ]]; then
    error_exit "ICMP Echo configuration verification failed."
fi

if [[ "$SWAPPINESS_VALUE" != "10" ]]; then
    error_exit "Swappiness configuration verification failed."
fi

print_message "INFO" "Final configuration:"
print_message "INFO" "ICMP Echo Ignore All: $ICMP_VALUE"
print_message "INFO" "VM Swappiness: $SWAPPINESS_VALUE"

print_message "SUCCESS" "Kernel optimization completed successfully."
