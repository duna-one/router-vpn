#!/bin/sh /etc/rc.common

START=98
STOP=10

start_service() {
    # Добавить default route в таблицу vpn
    ip route replace default dev awg1 table vpn 2>/dev/null

    # Маршруты для upstream DNS через VPN (dnsmasq -> 1.1.1.1)
    ip route replace 1.1.1.1 dev awg1 2>/dev/null
    ip route replace 1.0.0.1 dev awg1 2>/dev/null

    # Удалить dnsr nftables если остались
    nft delete table ip dnsr-nf 2>/dev/null
    nft delete table ip dnsr-nat 2>/dev/null

    # Добавить CIDR из *.txt в nft set vpn_domains
    for f in /etc/whitelists/*.txt; do
        [ -f "$f" ] || continue
        while IFS= read -r cidr; do
            [ -z "$cidr" ] && continue
            case "$cidr" in \#*) continue ;; esac
            nft add element inet fw4 vpn_domains "{ $cidr }" 2>/dev/null
        done < "$f"
    done
}

stop_service() {
    # Очистить таблицу vpn
    ip route flush table vpn 2>/dev/null
    # Не трогаем nft set — fw4 управляет им
}
