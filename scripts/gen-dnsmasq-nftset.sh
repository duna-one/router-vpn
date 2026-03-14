#!/bin/bash
# Генерирует dnsmasq nftset конфиг из whitelist *.lst файлов
# Результат: одна строка nftset на файл (все домены из файла в одном правиле)
# Формат: nftset=/<domain1>/<domain2>/.../<domainN>/4#inet#fw4#vpn_domains

WHITELISTS_DIR="${1:-whitelists}"
OUTPUT="${2:-dnsmasq-vpn-nftset.conf}"

> "$OUTPUT"

for lst in "$WHITELISTS_DIR"/*.lst; do
    [ -f "$lst" ] || continue
    # Собираем домены в одну nftset-строку
    domains=""
    while IFS= read -r domain; do
        # Пропускаем пустые строки и комментарии
        [ -z "$domain" ] && continue
        [[ "$domain" == \#* ]] && continue
        # Убираем пробелы
        domain=$(echo "$domain" | tr -d '[:space:]')
        [ -z "$domain" ] && continue
        domains="${domains}/${domain}"
    done < "$lst"

    if [ -n "$domains" ]; then
        echo "nftset=${domains}/4#inet#fw4#vpn_domains" >> "$OUTPUT"
    fi
done

echo "Generated $(wc -l < "$OUTPUT") nftset rules in $OUTPUT"
