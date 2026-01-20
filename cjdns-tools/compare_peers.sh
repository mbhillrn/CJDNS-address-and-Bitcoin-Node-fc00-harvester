#!/usr/bin/env bash
# Compare discovered peers against your current cjdns config
# Shows which peers are NEW and can be added

set -e

CONFIG="/etc/cjdroute_51888.conf"
DISCOVERED_IPV4="$1"
DISCOVERED_IPV6="$2"

if [ -z "$DISCOVERED_IPV4" ] || [ -z "$DISCOVERED_IPV6" ]; then
    echo "Usage: sudo $0 <ipv4_peers.json> <ipv6_peers.json>"
    echo
    echo "Example:"
    echo "  sudo $0 /tmp/cjdns_peer_discovery_*/all_ipv4_peers.json \\"
    echo "          /tmp/cjdns_peer_discovery_*/all_ipv6_peers.json"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "Error: Config file not found: $CONFIG"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)"
    exit 1
fi

echo "========================================"
echo "CJDNS Peer Comparison Tool"
echo "========================================"
echo

# Extract current peers from config
echo "Extracting current peers from config..."
CURRENT_IPV4=$(mktemp)
CURRENT_IPV6=$(mktemp)

jq -r '.interfaces.UDPInterface[0].connectTo // {} | keys[]' "$CONFIG" > "$CURRENT_IPV4" 2>/dev/null || : > "$CURRENT_IPV4"
jq -r '.interfaces.UDPInterface[1].connectTo // {} | keys[]' "$CONFIG" > "$CURRENT_IPV6" 2>/dev/null || : > "$CURRENT_IPV6"

CURRENT_IPV4_COUNT=$(wc -l < "$CURRENT_IPV4")
CURRENT_IPV6_COUNT=$(wc -l < "$CURRENT_IPV6")

echo "Current config has:"
echo "  IPv4 peers: $CURRENT_IPV4_COUNT"
echo "  IPv6 peers: $CURRENT_IPV6_COUNT"
echo

# Find NEW peers (not in current config)
echo "========================================"
echo "NEW IPv4 Peers (not in your config)"
echo "========================================"

NEW_IPV4=$(mktemp)
jq -r 'keys[]' "$DISCOVERED_IPV4" | while read -r addr; do
    if ! grep -Fxq "$addr" "$CURRENT_IPV4"; then
        echo "$addr"
    fi
done > "$NEW_IPV4"

NEW_IPV4_COUNT=$(wc -l < "$NEW_IPV4")

if [ "$NEW_IPV4_COUNT" -eq 0 ]; then
    echo "No new IPv4 peers found"
else
    echo "Found $NEW_IPV4_COUNT new IPv4 peers:"
    echo

    cat "$NEW_IPV4" | while read -r addr; do
        jq -r --arg addr "$addr" 'to_entries[] | select(.key == $addr) |
            "Address:    \(.key)\n" +
            "Password:   \(.value.password)\n" +
            "PublicKey:  \(.value.publicKey)\n" +
            "PeerName:   \(.value.peerName // "N/A")\n" +
            "Contact:    \(.value.contact // "N/A")\n"' "$DISCOVERED_IPV4"
    done
fi

echo
echo "========================================"
echo "NEW IPv6 Peers (not in your config)"
echo "========================================"

NEW_IPV6=$(mktemp)
jq -r 'keys[]' "$DISCOVERED_IPV6" | while read -r addr; do
    if ! grep -Fxq "$addr" "$CURRENT_IPV6"; then
        echo "$addr"
    fi
done > "$NEW_IPV6"

NEW_IPV6_COUNT=$(wc -l < "$NEW_IPV6")

if [ "$NEW_IPV6_COUNT" -eq 0 ]; then
    echo "No new IPv6 peers found"
else
    echo "Found $NEW_IPV6_COUNT new IPv6 peers:"
    echo

    cat "$NEW_IPV6" | while read -r addr; do
        jq -r --arg addr "$addr" 'to_entries[] | select(.key == $addr) |
            "Address:    \(.key)\n" +
            "Password:   \(.value.password)\n" +
            "PublicKey:  \(.value.publicKey)\n" +
            "PeerName:   \(.value.peerName // "N/A")\n" +
            "Contact:    \(.value.contact // "N/A")\n"' "$DISCOVERED_IPV6"
    done
fi

echo
echo "========================================"
echo "Summary"
echo "========================================"
echo "Current IPv4 peers: $CURRENT_IPV4_COUNT"
echo "Current IPv6 peers: $CURRENT_IPV6_COUNT"
echo
echo "Available new IPv4 peers: $NEW_IPV4_COUNT"
echo "Available new IPv6 peers: $NEW_IPV6_COUNT"
echo
echo "Potential total after adding all:"
echo "  IPv4: $((CURRENT_IPV4_COUNT + NEW_IPV4_COUNT))"
echo "  IPv6: $((CURRENT_IPV6_COUNT + NEW_IPV6_COUNT))"
echo

# Cleanup
rm -f "$CURRENT_IPV4" "$CURRENT_IPV6" "$NEW_IPV4" "$NEW_IPV6"
