#!/bin/bash

set -Eeuo pipefail

# ==========================================
# Emperor Penguin - System Information Monitor
# ==========================================

OUTPUT_DIR="/opt/data/sysinfo"

FILES=(
    "root_processes.log"
    "listening_ports.log"
    "system_users.log"
    "ram_usage.log"
    "opt_disk_usage.log"
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

trap 'error_exit "Unexpected error at line $LINENO."' ERR

# ------------------------------------------
# Pre-checks
# ------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    error_exit "Please run this script as root."
fi

for command in ps ss getent free df awk date; do
    command -v "$command" >/dev/null 2>&1 ||
        error_exit "Required command not found: $command"
done

if [[ ! -d "$OUTPUT_DIR" ]]; then
    error_exit "Output directory does not exist: $OUTPUT_DIR"
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ------------------------------------------
# 1. Root Processes
# ------------------------------------------

ROOT_PROCESSES=$(ps -U root --no-headers | wc -l)

printf '%s | Root Processes: %s\n' \
    "$TIMESTAMP" "$ROOT_PROCESSES" \
    >> "$OUTPUT_DIR/root_processes.log"

# ------------------------------------------
# 2. Listening Ports
# ------------------------------------------

{
    echo "===== $TIMESTAMP ====="
    ss -lntup
    echo
} >> "$OUTPUT_DIR/listening_ports.log"

# ------------------------------------------
# 3. System Users (UID < 1000)
# ------------------------------------------

{
    echo "===== $TIMESTAMP ====="

    awk -F: '$3 < 1000 {
        printf "Username: %-20s UID: %s\n", $1, $3
    }' /etc/passwd

    echo
} >> "$OUTPUT_DIR/system_users.log"

# ------------------------------------------
# 4. RAM Usage
# ------------------------------------------

RAM_INFO=$(free -m | awk '/^Mem:/ {
    printf "Used: %s MB | Total: %s MB",
    $3, $2
}')

printf '%s | %s\n' \
    "$TIMESTAMP" "$RAM_INFO" \
    >> "$OUTPUT_DIR/ram_usage.log"

# ------------------------------------------
# 5. /opt Free Space
# ------------------------------------------

OPT_INFO=$(df -P /opt | awk 'NR==2 {
    printf "Free: %s | Available: %s | Usage: %s",
    $4, $4, $5
}')

printf '%s | /opt %s\n' \
    "$TIMESTAMP" "$OPT_INFO" \
    >> "$OUTPUT_DIR/opt_disk_usage.log"

print_message "SUCCESS" "System information collected successfully."
