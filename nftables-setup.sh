
#!/usr/bin/env bash

set -Eeuo pipefail

# ==========================================
# Emperor Penguin - Nftables Setup
# ==========================================

CONFIG_FILE="/etc/nftables.conf"
DOMAIN="deb.debian.org"
SSH_PORT="2222"

TEMP_CONFIG=""

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
}

trap cleanup EXIT

# ------------------------------------------
# Root and Dependency Checks
# ------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    error_exit "Please run this script as root."
fi

for command in nft getent systemctl awk sort; do
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
# Backup Existing Configuration
# ------------------------------------------

if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"

    cp -a "$CONFIG_FILE" "$BACKUP_FILE"

    print_message "INFO" "Previous configuration backed up to $BACKUP_FILE"
fi

# ------------------------------------------
# Generate Nftables Configuration
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

# Add IPv4 counters
for ip in "${IPV4_ADDRESSES[@]}"; do
    printf '        ip daddr %s counter comment "deb.debian.org IPv4"\n' \
        "$ip" >> "$TEMP_CONFIG"
done

# Add IPv6 counters
for ip in "${IPV6_ADDRESSES[@]}"; do
    printf '        ip6 daddr %s counter comment "deb.debian.org IPv6"\n' \
        "$ip" >> "$TEMP_CONFIG"
done

cat >> "$TEMP_CONFIG" <<'EOF'
    }
}
EOF

chmod 644 "$TEMP_CONFIG"

print_message "INFO" "Nftables configuration generated."

# ------------------------------------------
# Validate Configuration
# ------------------------------------------

if ! nft -c -f "$TEMP_CONFIG"; then
    error_exit "Nftables configuration validation failed."
fi

print_message "SUCCESS" "Configuration validation passed."

# ------------------------------------------
# Install Configuration
# ------------------------------------------

install -m 644 "$TEMP_CONFIG" "$CONFIG_FILE"

# ------------------------------------------
# Apply Firewall Rules
# ------------------------------------------

if ! nft -f "$CONFIG_FILE"; then
    error_exit "Failed to apply Nftables rules."
fi

print_message "SUCCESS" "Firewall rules applied successfully."

# ------------------------------------------
# Enable Nftables Service
# ------------------------------------------

systemctl enable --now nftables ||
    error_exit "Failed to enable Nftables service."

if ! systemctl is-active --quiet nftables; then
    error_exit "Nftables service is not active."
fi

print_message "SUCCESS" "Nftables service is enabled and active."

# ------------------------------------------
# Final Verification
# ------------------------------------------

if ! nft list ruleset >/dev/null 2>&1; then
    error_exit "Could not verify the active ruleset."
fi

echo
print_message "SUCCESS" "Nftables setup completed successfully."
echo
echo "Resolved IPv4 addresses: ${#IPV4_ADDRESSES[@]}"
echo "Resolved IPv6 addresses: ${#IPV6_ADDRESSES[@]}"
echo "SSH port: $SSH_PORT"
echo
echo "Active ruleset:"
nft list ruleset
