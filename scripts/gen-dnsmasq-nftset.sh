#!/bin/bash
# Генерирует dnsmasq nftset конфиг из whitelist *.lst файлов
# Результат: две строки на файл:
#   server=/<domains>/1.1.1.1   — DNS-запросы для VPN-доменов через VPN upstream
#   nftset=/<domains>/4#inet#fw4#vpn_domains — резолв IP добавляется в nft set
#
# VPN upstream DNS (1.1.1.1) маршрутизируется через VPN (см. dns-upstream-ips.txt),
# поэтому DNS-запросы для VPN-доменов не утекают через WAN.

VPN_DNS="${VPN_DNS:-1.1.1.1}"
WHITELISTS_DIR="${1:-whitelists}"
OUTPUT="${2:-dnsmasq-vpn-nftset.conf}"

> "$OUTPUT"

for lst in "$WHITELISTS_DIR"/*.lst; do
    [ -f "$lst" ] || continue
    # Собираем домены в одну строку
    domains=""
    while IFS= read -r domain || [ -n "$domain" ]; do
        # Пропускаем пустые строки и комментарии
        [ -z "$domain" ] && continue
        [[ "$domain" == \#* ]] && continue
        # Убираем пробелы
        domain=$(echo "$domain" | tr -d '[:space:]')
        [ -z "$domain" ] && continue
        domains="${domains}/${domain}"
    done < "$lst"

    if [ -n "$domains" ]; then
        echo "server=${domains}/${VPN_DNS}" >> "$OUTPUT"
        echo "nftset=${domains}/4#inet#fw4#vpn_domains" >> "$OUTPUT"
    fi
done

echo "Generated $(( $(wc -l < "$OUTPUT") / 2 )) domain groups ($(wc -l < "$OUTPUT") lines) in $OUTPUT"
