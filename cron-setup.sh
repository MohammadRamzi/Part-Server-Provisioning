#!/bin/bash

set -Eeuo pipefail

# ==========================================
# Emperor Penguin - Cron Setup
# ==========================================

OUTPUT_DIR="/opt/data/sysinfo"
SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/sysinfo-monitor.sh"
CRON_FILE="/etc/cron.d/emperor-penguin-monitor"

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

if [[ ! -f "$SCRIPT_PATH" ]]; then
    error_exit "Monitoring script not found: $SCRIPT_PATH"
fi

if ! command -v cron >/dev/null 2>&1; then
    error_exit "Cron is not installed."
fi

# ------------------------------------------
# Prepare output directory
# ------------------------------------------

mkdir -p "$OUTPUT_DIR"
chmod 755 "$OUTPUT_DIR"

for file in \
    root_processes.log \
    listening_ports.log \
    system_users.log \
    ram_usage.log \
    opt_disk_usage.log
do
    touch "$OUTPUT_DIR/$file"
    chmod 644 "$OUTPUT_DIR/$file"
done

chmod 755 "$SCRIPT_PATH"

print_message "INFO" "Output directory prepared."

# ------------------------------------------
# Configure Cron
# ------------------------------------------

CRON_LOG="/var/log/emperor-penguin-monitor.log"

CRON_JOB="*/2 * * * * root $SCRIPT_PATH >> $CRON_LOG 2>&1"

if [[ -f "$CRON_FILE" ]] &&
   [[ "$(cat "$CRON_FILE")" == "$CRON_JOB" ]]; then

    print_message "INFO" "Cron configuration is already correct."

else

    if [[ -f "$CRON_FILE" ]]; then
        cp -a "$CRON_FILE" \
            "${CRON_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    printf '%s\n' "$CRON_JOB" > "$CRON_FILE"
    chmod 644 "$CRON_FILE"

    print_message "INFO" "Cron configuration created."
fi

# ------------------------------------------
# Enable Cron service
# ------------------------------------------

systemctl enable --now cron

if ! systemctl is-active --quiet cron; then
    error_exit "Cron service is not active."
fi

print_message "SUCCESS" "Cron monitoring configured successfully."
