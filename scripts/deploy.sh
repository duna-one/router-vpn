#!/bin/bash
# Deploy whitelists and VPN routing config to router
# Usage: ./scripts/deploy.sh

set -euo pipefail

ROUTER="root@192.168.2.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHITELISTS_DIR="$PROJECT_DIR/whitelists"
CONF="$PROJECT_DIR/dnsmasq-vpn-nftset.conf"

# 1. Generate dnsmasq nftset config
echo ">>> Generating dnsmasq nftset config..."
bash "$SCRIPT_DIR/gen-dnsmasq-nftset.sh" "$WHITELISTS_DIR" "$CONF"

# 2. Deploy dnsmasq config
echo ">>> Deploying dnsmasq config..."
ssh "$ROUTER" "cat > /etc/dnsmasq.d/vpn-nftset.conf" < "$CONF"

# 3. Deploy CIDR files
for txt in "$WHITELISTS_DIR"/*.txt; do
    [ -f "$txt" ] || continue
    fname="$(basename "$txt")"
    echo ">>> Deploying $fname..."
    ssh "$ROUTER" "cat > /etc/whitelists/$fname" < "$txt"
done

# 4. Deploy hotplug script
echo ">>> Deploying hotplug script..."
ssh "$ROUTER" "cat > /etc/hotplug.d/iface/99-vpn-routes && chmod +x /etc/hotplug.d/iface/99-vpn-routes" < "$SCRIPT_DIR/99-vpn-routes.sh"

# 5. Restart dnsmasq
echo ">>> Restarting dnsmasq..."
ssh "$ROUTER" "/etc/init.d/dnsmasq restart"

# 6. Trigger hotplug (reload CIDRs into nft set)
echo ">>> Triggering VPN route reload..."
ssh "$ROUTER" "ACTION=ifup INTERFACE=awg1 /bin/sh /etc/hotplug.d/iface/99-vpn-routes"

# 7. Smoke test
echo ">>> Running smoke test..."
if ssh "$ROUTER" "nslookup telegram.org 127.0.0.1 >/dev/null 2>&1"; then
    echo ">>> DNS: OK"
else
    echo ">>> WARNING: DNS check failed!"
fi

if ssh "$ROUTER" "nft list set inet fw4 vpn_domains 2>/dev/null | grep -q '149.154'"; then
    echo ">>> nft set (Telegram CIDR): OK"
else
    echo ">>> WARNING: Telegram CIDR not found in nft set!"
fi

echo ">>> Done."
