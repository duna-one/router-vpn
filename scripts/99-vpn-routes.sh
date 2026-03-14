#!/bin/sh
# Hotplug script for awg1 VPN interface
# Deployed to /etc/hotplug.d/iface/99-vpn-routes on router
#
# ifup:   configures vpn routing table, loads CIDRs into nft set
# ifdown: flushes vpn table so traffic falls through to WAN

[ "$INTERFACE" = "awg1" ] || exit 0

case "$ACTION" in
    ifup)
        logger -t vpn-routes "awg1 ifup: configuring VPN routes"

        # Protect WireGuard endpoint from fwmark routing loop
        ip rule del to 92.51.45.254 lookup main priority 50 2>/dev/null
        ip rule add to 92.51.45.254 lookup main priority 50

        # Default route in vpn table
        ip route replace default dev awg1 table vpn

        # Wait for fw4 to create the nft set (may not be ready at early boot)
        for i in 1 2 3 4 5; do
            nft list set inet fw4 vpn_domains >/dev/null 2>&1 && break
            logger -t vpn-routes "waiting for fw4 vpn_domains set ($i/5)"
            sleep 2
        done

        # Load static CIDRs into nft set
        for f in /etc/whitelists/*.txt; do
            [ -f "$f" ] || continue
            while IFS= read -r cidr; do
                [ -z "$cidr" ] && continue
                case "$cidr" in \#*) continue ;; esac
                nft add element inet fw4 vpn_domains "{ $cidr }" 2>/dev/null
            done < "$f"
        done

        # Clean up dnsr nftables if still present
        nft delete table ip dnsr-nf 2>/dev/null
        nft delete table ip dnsr-nat 2>/dev/null

        logger -t vpn-routes "awg1 ifup: VPN routes configured"
        ;;
    ifdown)
        logger -t vpn-routes "awg1 ifdown: flushing vpn table"
        ip route flush table vpn 2>/dev/null
        ;;
esac
