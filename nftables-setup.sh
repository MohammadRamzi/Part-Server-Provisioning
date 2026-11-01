#!/bin/bash

set -Eeuo pipefail

# ==========================================
# Emperor Penguin - Nftables Setup
# ==========================================

CONFIG_FILE="/etc/nftables.conf"
DOMAIN="deb.debian.org"
SSH_PORT="2222"

TEMP_CONFIG=""
BACKUP_RULESET=""
BACKUP_CONFIG=""
CONFIG_EXISTED=false
BACKUP_CREATED=false

# ------------------------------------------
# Utility Functions
# ------------------------------------------

print_message() {
    local type="$1"
    local message="$2"

    case "$type" in
        INFO)    echo "[INFO] $message" ;;
        SUCCESS) echo "[SUCCESS] $message" ;;
        WARNING) echo "[WARNING] $message" ;;
        ERROR)   echo "[ERROR] $message" >&2 ;;
    esac
}

error_exit() {
    print_message "ERROR" "$1"
    exit 1
}

cleanup() {
    [[ -n "$TEMP_CONFIG" && -f "$TEMP_CONFIG" ]] && rm -f "$TEMP_CONFIG"
    [[ -n "$BACKUP_RULESET" && -f "$BACKUP_RULESET" ]] && rm -f "$BACKUP_RULESET"
    [[ -n "$BACKUP_CONFIG" && -f "$BACKUP_CONFIG" ]] && rm -f "$BACKUP_CONFIG"
}

rollback() {
    print_message "WARNING" "Restoring previous firewall configuration..."

    # Restore previous configuration file
    if [[ "$CONFIG_EXISTED" == true ]]; then
        if ! cp -a "$BACKUP_CONFIG" "$CONFIG_FILE"; then
            print_message "ERROR" "Could not restore previous configuration file."
        fi
    else
        rm -f "$CONFIG_FILE"
    fi

    # Restore previous active ruleset
    if nft -f "$BACKUP_RULESET"; then
        print_message "SUCCESS" "Previous firewall ruleset restored."
    else
        print_message "ERROR" "Automatic ruleset restoration failed!"
        print_message "ERROR" "Manual recovery may be required."
    fi
}

trap cleanup EXIT

# ------------------------------------------
# Root and Dependency Checks
# ------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    error_exit "Please run this script as root."
fi

for command in nft getent systemctl awk sort date cp install mktemp; do
    command -v "$command" >/dev/null 2>&1 ||
        error_exit "Required command not found: $command"
done

print_message "INFO" "Starting Nftables configuration..."

# ------------------------------------------
# DNS Resolution
# ------------------------------------------

mapfile -t IPV4_ADDRESSES < <(
    getent ahostsv4 "$DOMAIN" 2>/dev/null |
        awk '{print $1}' |
        sort -u
)

mapfile -t IPV6_ADDRESSES < <(
    getent ahostsv6 "$DOMAIN" 2>/dev/null |
        awk '{print $1}' |
        sort -u
)

if [[ ${#IPV4_ADDRESSES[@]} -eq 0 &&
      ${#IPV6_ADDRESSES[@]} -eq 0 ]]; then
    error_exit "Could not resolve $DOMAIN."
fi

print_message "SUCCESS" "DNS resolution completed."

# ------------------------------------------
# Generate New Configuration
# ------------------------------------------

TEMP_CONFIG=$(mktemp)

cat > "$TEMP_CONFIG" <<EOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {

    chain input {
        type filter hook input priority 0;
        policy drop;

        # Allow loopback traffic
        iifname "lo" accept

        # Allow essential ICMPv6 traffic
        meta l4proto ipv6-icmp accept

        # Allow established and related connections
        ct state established,related accept

        # Allow SSH
        tcp dport $SSH_PORT accept
    }

    chain output {
        type filter hook output priority 0;
        policy accept;
EOF

for ip in "${IPV4_ADDRESSES[@]}"; do
    printf '        ip daddr %s counter comment "deb.debian.org IPv4"\n' \
        "$ip" >> "$TEMP_CONFIG"
done

for ip in "${IPV6_ADDRESSES[@]}"; do
    printf '        ip6 daddr %s counter comment "deb.debian.org IPv6"\n' \
        "$ip" >> "$TEMP_CONFIG"
done

cat >> "$TEMP_CONFIG" <<'EOF'
    }
}
EOF

chmod 644 "$TEMP_CONFIG"

print_message "SUCCESS" "New configuration generated."

# ------------------------------------------
# Validate Configuration
# ------------------------------------------

if ! nft -c -f "$TEMP_CONFIG"; then
    error_exit "Configuration validation failed."
fi

print_message "SUCCESS" "Configuration validation passed."

# ------------------------------------------
# Backup Existing Configuration and Rules
# ------------------------------------------

BACKUP_RULESET=$(mktemp)

{
    echo "flush ruleset"
    nft list ruleset
} > "$BACKUP_RULESET"

if [[ -f "$CONFIG_FILE" ]]; then
    CONFIG_EXISTED=true
    BACKUP_CONFIG="${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

    cp -a "$CONFIG_FILE" "$BACKUP_CONFIG"

    print_message "INFO" "Previous configuration backed up."
fi

BACKUP_CREATED=true

print_message "SUCCESS" "Current firewall state backed up."

# ------------------------------------------
# Install and Apply Configuration
# ------------------------------------------

install -m 644 "$TEMP_CONFIG" "$CONFIG_FILE"

if ! nft -f "$CONFIG_FILE"; then
    print_message "ERROR" "Failed to apply new firewall rules."

    rollback

    error_exit "Firewall configuration rolled back."
fi

print_message "SUCCESS" "Firewall rules applied successfully."

# ------------------------------------------
# Enable Nftables Service
# ------------------------------------------

if ! systemctl enable --now nftables; then
    print_message "ERROR" "Failed to enable Nftables service."
    rollback
    error_exit "Firewall configuration rolled back."
fi

if ! systemctl is-active --quiet nftables; then
    rollback
    error_exit "Nftables service is not active."
fi

print_message "SUCCESS" "Nftables service is enabled and active."

# ------------------------------------------
# Final Verification
# ------------------------------------------

if ! nft list ruleset >/dev/null 2>&1; then
    rollback
    error_exit "Final ruleset verification failed."
fi

echo
print_message "SUCCESS" "Nftables setup completed successfully."

echo "Resolved IPv4 addresses: ${#IPV4_ADDRESSES[@]}"
echo "Resolved IPv6 addresses: ${#IPV6_ADDRESSES[@]}"
echo "SSH port: $SSH_PORT"

echo
echo "Active ruleset:"
nft list ruleset

