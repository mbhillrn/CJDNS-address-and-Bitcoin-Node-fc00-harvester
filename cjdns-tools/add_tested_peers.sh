#!/bin/bash

# Add tested active peers to cjdns config
# Copies ALL fields from source JSON without modification
# Usage: ./add_tested_peers.sh <active_ipv4.json> <active_ipv6.json> <config_file>

set -euo pipefail

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <active_ipv4.json> <active_ipv6.json> <config_file>"
    echo "Example: sudo $0 /tmp/cjdns_tested_peers_*/active_ipv4.json /tmp/cjdns_tested_peers_*/active_ipv6.json /etc/cjdroute_51888.conf"
    exit 1
fi

IPV4_PEERS="$1"
IPV6_PEERS="$2"
CONFIG="$3"

if [ ! -f "$IPV4_PEERS" ]; then
    echo "Error: IPv4 peers file not found: $IPV4_PEERS"
    exit 1
fi

if [ ! -f "$IPV6_PEERS" ]; then
    echo "Error: IPv6 peers file not found: $IPV6_PEERS"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "Error: Config file not found: $CONFIG"
    exit 1
fi

echo "========================================"
echo "Adding Tested Peers to CJDNS Config"
echo "========================================"
echo

# Create backup
BACKUP="${CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
echo "[1] Creating backup..."
cp "$CONFIG" "$BACKUP"
echo "  Backup saved to: $BACKUP"
echo

# Count peers to add
IPV4_COUNT=$(jq 'length' "$IPV4_PEERS")
IPV6_COUNT=$(jq 'length' "$IPV6_PEERS")

echo "[2] Peers to add:"
echo "  IPv4: $IPV4_COUNT"
echo "  IPv6: $IPV6_COUNT"
echo

if [ "$IPV4_COUNT" -eq 0 ] && [ "$IPV6_COUNT" -eq 0 ]; then
    echo "No peers to add. Exiting."
    exit 0
fi

# Show what will be added
if [ "$IPV4_COUNT" -gt 0 ]; then
    echo "IPv4 peers to add:"
    jq -r 'to_entries[] | "  \(.key) - \(.value.peerName // "unknown")"' "$IPV4_PEERS"
    echo
fi

if [ "$IPV6_COUNT" -gt 0 ]; then
    echo "IPv6 peers to add:"
    jq -r 'to_entries[] | "  \(.key) - \(.value.peerName // "unknown")"' "$IPV6_PEERS"
    echo
fi

read -p "Continue adding these peers? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo
echo "[3] Adding peers to config..."

# Start with current config
TEMP_CONFIG=$(mktemp)
cp "$CONFIG" "$TEMP_CONFIG"

# Add IPv4 peers
if [ "$IPV4_COUNT" -gt 0 ]; then
    echo "  Adding IPv4 peers..."

    # Merge IPv4 peers into interface 0
    jq --slurpfile new_peers "$IPV4_PEERS" '
        .interfaces.UDPInterface[0].connectTo += $new_peers[0]
    ' "$TEMP_CONFIG" > "${TEMP_CONFIG}.new"

    mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
    echo "  ✓ Added $IPV4_COUNT IPv4 peers"
fi

# Add IPv6 peers
if [ "$IPV6_COUNT" -gt 0 ]; then
    echo "  Adding IPv6 peers..."

    # Merge IPv6 peers into interface 1
    jq --slurpfile new_peers "$IPV6_PEERS" '
        .interfaces.UDPInterface[1].connectTo += $new_peers[0]
    ' "$TEMP_CONFIG" > "${TEMP_CONFIG}.new"

    mv "${TEMP_CONFIG}.new" "$TEMP_CONFIG"
    echo "  ✓ Added $IPV6_COUNT IPv6 peers"
fi

echo

# Validate JSON
echo "[4] Validating JSON..."
if jq empty "$TEMP_CONFIG" 2>/dev/null; then
    echo "  ✓ JSON is valid"
else
    echo "  ✗ JSON validation failed!"
    echo "  Config NOT updated. Backup preserved at: $BACKUP"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

# Write new config
cp "$TEMP_CONFIG" "$CONFIG"
rm -f "$TEMP_CONFIG"

echo
echo "[5] Counting final peers..."
FINAL_IPV4=$(jq '.interfaces.UDPInterface[0].connectTo | length' "$CONFIG")
FINAL_IPV6=$(jq '.interfaces.UDPInterface[1].connectTo | length' "$CONFIG")

echo "  Final IPv4 peers: $FINAL_IPV4"
echo "  Final IPv6 peers: $FINAL_IPV6"

echo
echo "========================================"
echo "Peers Added Successfully!"
echo "========================================"
echo
echo "Next steps:"
echo "  1. Restart cjdns: sudo systemctl restart cjdns"
echo "  2. Check peer status: sudo cjdnstool call ReachabilityCollector_getPeerInfo"
echo "  3. Monitor connections for a few minutes"
echo
echo "Backup preserved at: $BACKUP"
