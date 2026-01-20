#!/usr/bin/env bash
# Comprehensive CJDNS peer discovery from multiple sources
# Checks: hyperboria/peers, yangm97/peers, cwinfo/hyperboria-peers, cjdns.ca

set -e

TEMP_BASE="/tmp/cjdns_peer_discovery_$$"
mkdir -p "$TEMP_BASE"
cd "$TEMP_BASE"

OUTPUT_IPV4="$TEMP_BASE/all_ipv4_peers.json"
OUTPUT_IPV6="$TEMP_BASE/all_ipv6_peers.json"

echo "{}" > "$OUTPUT_IPV4"
echo "{}" > "$OUTPUT_IPV6"

echo "======================================="
echo "CJDNS Comprehensive Peer Discovery"
echo "======================================="
echo
echo "Checking multiple peer repositories..."
echo

# List of repositories to check
REPOS=(
    "https://github.com/hyperboria/peers.git|hyperboria-peers"
    "https://github.com/yangm97/peers.git|yangm97-peers"
    "https://github.com/cwinfo/hyperboria-peers.git|cwinfo-peers"
)

TOTAL_IPV4=0
TOTAL_IPV6=0

# Function to extract peers from a repository
extract_peers_from_repo() {
    local repo_dir="$1"
    local repo_name="$2"

    echo "Processing $repo_name..."

    cd "$repo_dir"

    # Find all .k files
    local k_files=$(find . -name "*.k" -type f 2>/dev/null || echo "")

    if [ -z "$k_files" ]; then
        echo "  No .k files found"
        return
    fi

    local count=$(echo "$k_files" | wc -l)
    echo "  Found $count peer files"

    local current=0
    local ipv4_found=0
    local ipv6_found=0

    while IFS= read -r peer_file; do
        current=$((current + 1))

        # Read and validate JSON
        if ! peer_json=$(cat "$peer_file" 2>/dev/null); then
            continue
        fi

        if ! echo "$peer_json" | jq empty 2>/dev/null; then
            continue
        fi

        # Extract IPv4 addresses (no brackets)
        ipv4_addrs=$(echo "$peer_json" | jq -r 'keys[] | select(startswith("[") | not)' 2>/dev/null || echo "")

        if [ -n "$ipv4_addrs" ]; then
            while IFS= read -r address; do
                [ -z "$address" ] && continue

                peer_data=$(echo "$peer_json" | jq --arg addr "$address" '{($addr): .[$addr]}' 2>/dev/null)

                if [ -n "$peer_data" ]; then
                    echo "$peer_data" | jq -s --slurpfile existing "$OUTPUT_IPV4" '.[0] * $existing[0]' > "$TEMP_BASE/merged.json"
                    mv "$TEMP_BASE/merged.json" "$OUTPUT_IPV4"
                    ipv4_found=$((ipv4_found + 1))
                fi
            done <<< "$ipv4_addrs"
        fi

        # Extract IPv6 addresses (with brackets)
        ipv6_addrs=$(echo "$peer_json" | jq -r 'keys[] | select(startswith("["))' 2>/dev/null || echo "")

        if [ -n "$ipv6_addrs" ]; then
            while IFS= read -r address; do
                [ -z "$address" ] && continue

                peer_data=$(echo "$peer_json" | jq --arg addr "$address" '{($addr): .[$addr]}' 2>/dev/null)

                if [ -n "$peer_data" ]; then
                    echo "$peer_data" | jq -s --slurpfile existing "$OUTPUT_IPV6" '.[0] * $existing[0]' > "$TEMP_BASE/merged.json"
                    mv "$TEMP_BASE/merged.json" "$OUTPUT_IPV6"
                    ipv6_found=$((ipv6_found + 1))
                fi
            done <<< "$ipv6_addrs"
        fi

    done <<< "$k_files"

    echo "  IPv4: $ipv4_found peers"
    echo "  IPv6: $ipv6_found peers"
    echo

    TOTAL_IPV4=$((TOTAL_IPV4 + ipv4_found))
    TOTAL_IPV6=$((TOTAL_IPV6 + ipv6_found))
}

# Clone and process each repository
for repo_info in "${REPOS[@]}"; do
    IFS='|' read -r repo_url repo_name <<< "$repo_info"

    echo "Cloning $repo_name..."
    if git clone --depth 1 "$repo_url" "$TEMP_BASE/$repo_name" 2>/dev/null; then
        echo "✓ Cloned"
        extract_peers_from_repo "$TEMP_BASE/$repo_name" "$repo_name"
    else
        echo "✗ Failed to clone"
        echo
    fi
done

# Try to fetch cjdns.ca/peers.txt
echo "Checking cjdns.ca/peers.txt..."
if wget -q -O "$TEMP_BASE/peers.txt" http://cjdns.ca/peers.txt 2>/dev/null; then
    echo "✓ Downloaded peers.txt"

    # Parse peers.txt format (if it exists and has content)
    if [ -s "$TEMP_BASE/peers.txt" ]; then
        # This file may have a custom format - let's check it
        head -20 "$TEMP_BASE/peers.txt"
        echo "(showing first 20 lines - file will need custom parsing)"
    fi
else
    echo "✗ Could not fetch peers.txt"
fi
echo

echo "======================================="
echo "Extraction Complete"
echo "======================================="

# Count unique peers
UNIQUE_IPV4=$(jq 'keys | length' "$OUTPUT_IPV4")
UNIQUE_IPV6=$(jq 'keys | length' "$OUTPUT_IPV6")

echo "Total unique IPv4 peers: $UNIQUE_IPV4"
echo "Total unique IPv6 peers: $UNIQUE_IPV6"
echo
echo "IPv4 peers saved to: $OUTPUT_IPV4"
echo "IPv6 peers saved to: $OUTPUT_IPV6"
echo

# Show sample of peers
echo "======================================="
echo "Sample IPv4 Peers (first 5)"
echo "======================================="
jq -r 'to_entries[:5][] | "Address:    \(.key)\nPassword:   \(.value.password)\nPublicKey:  \(.value.publicKey)\nPeerName:   \(.value.peerName // "N/A")\n"' "$OUTPUT_IPV4"

echo "======================================="
echo "Sample IPv6 Peers (first 5)"
echo "======================================="
jq -r 'to_entries[:5][] | "Address:    \(.key)\nPassword:   \(.value.password)\nPublicKey:  \(.value.publicKey)\nPeerName:   \(.value.peerName // "N/A")\n"' "$OUTPUT_IPV6"

echo
echo "Working directory: $TEMP_BASE"
echo
echo "Next steps:"
echo "  1. Review the peer lists above"
echo "  2. Look for the 'alfa-charlie-alfa-bravo' (acab) password"
echo "  3. Compare these against your /etc/cjdroute_51888.conf"
echo "  4. Use add_peer_safe.sh to add new peers (on your host system)"
echo
