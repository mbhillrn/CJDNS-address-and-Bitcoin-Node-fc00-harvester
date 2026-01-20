#!/usr/bin/env bash
# Test IPv6 connectivity and configuration

echo "========================================"
echo "IPv6 Connectivity Test"
echo "========================================"
echo

# Check if IPv6 is enabled
echo "[1] Checking if IPv6 is enabled..."
if [ -f /proc/net/if_inet6 ]; then
    echo "✓ IPv6 is enabled in kernel"
    echo
    echo "IPv6 interfaces:"
    cat /proc/net/if_inet6 | awk '{print "  " $6}' | sort -u
else
    echo "✗ IPv6 is NOT enabled"
    echo "  Enable with: sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0"
    exit 1
fi

echo

# Test IPv6 DNS resolution
echo "[2] Testing IPv6 DNS resolution..."
if host -t AAAA google.com >/dev/null 2>&1; then
    echo "✓ IPv6 DNS resolution works"
    host -t AAAA google.com | head -2
else
    echo "✗ IPv6 DNS resolution failed"
fi

echo

# Test IPv6 internet connectivity
echo "[3] Testing IPv6 internet connectivity..."
if ping6 -c 2 2001:4860:4860::8888 >/dev/null 2>&1; then
    echo "✓ IPv6 internet connectivity works"
    ping6 -c 2 2001:4860:4860::8888 | tail -2
elif ping -6 -c 2 2001:4860:4860::8888 >/dev/null 2>&1; then
    echo "✓ IPv6 internet connectivity works"
    ping -6 -c 2 2001:4860:4860::8888 | tail -2
else
    echo "✗ IPv6 internet connectivity NOT working"
    echo "  This might be normal if your ISP doesn't provide native IPv6"
    echo "  CJDNS IPv6 peers might still work!"
fi

echo

# Check CJDNS IPv6 interface
echo "[4] Checking CJDNS IPv6 configuration..."
if [ -f /etc/cjdroute_51888.conf ]; then
    IPV6_BIND=$(jq -r '.interfaces.UDPInterface[1].bind // "NOT CONFIGURED"' /etc/cjdroute_51888.conf 2>/dev/null)
    echo "CJDNS IPv6 bind address: $IPV6_BIND"

    if [ "$IPV6_BIND" != "NOT CONFIGURED" ] && [ "$IPV6_BIND" != "null" ]; then
        echo "✓ CJDNS has IPv6 interface configured"

        IPV6_PEER_COUNT=$(jq '.interfaces.UDPInterface[1].connectTo // {} | length' /etc/cjdroute_51888.conf 2>/dev/null)
        echo "  Current IPv6 peers: $IPV6_PEER_COUNT"
    else
        echo "✗ CJDNS IPv6 interface NOT configured"
    fi
else
    echo "✗ Config file not found: /etc/cjdroute_51888.conf"
fi

echo

# Test if we can bind to IPv6
echo "[5] Testing if we can bind to IPv6 ports..."
if nc -6 -l -p 12345 </dev/null >/dev/null 2>&1 & then
    NC_PID=$!
    sleep 1
    kill $NC_PID 2>/dev/null
    echo "✓ Can bind to IPv6 ports"
else
    echo "✗ Cannot bind to IPv6 ports"
fi

echo
echo "========================================"
echo "Test Complete"
echo "========================================"
echo
echo "If IPv6 internet doesn't work but kernel IPv6 is enabled,"
echo "CJDNS IPv6 peers should still work for mesh networking!"
echo
