#!/bin/bash
# Деплой whitelists на роутер
# Использование: ./scripts/deploy.sh
#
# Что делает:
# 1. Генерирует dnsmasq nftset конфиг из whitelists/*.lst
# 2. Деплоит его на роутер в /etc/dnsmasq.d/
# 3. Деплоит whitelists/*.txt (CIDR) в /etc/whitelists/
# 4. Перезапускает dnsmasq и vpn-static-routes

set -euo pipefail

ROUTER="root@192.168.2.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHITELISTS_DIR="$PROJECT_DIR/whitelists"
CONF="$PROJECT_DIR/dnsmasq-vpn-nftset.conf"

# 1. Генерация dnsmasq конфига
echo ">>> Generating dnsmasq nftset config..."
bash "$SCRIPT_DIR/gen-dnsmasq-nftset.sh" "$WHITELISTS_DIR" "$CONF"

# 2. Деплой dnsmasq конфига (с конвертацией CRLF -> LF)
echo ">>> Deploying dnsmasq config..."
ssh "$ROUTER" "cat > /etc/dnsmasq.d/vpn-nftset.conf && sed -i 's/\r//' /etc/dnsmasq.d/vpn-nftset.conf" < "$CONF"

# 3. Деплой CIDR файлов (с конвертацией CRLF -> LF)
for txt in "$WHITELISTS_DIR"/*.txt; do
    [ -f "$txt" ] || continue
    fname="$(basename "$txt")"
    echo ">>> Deploying $fname..."
    ssh "$ROUTER" "cat > /etc/whitelists/$fname && sed -i 's/\r//' /etc/whitelists/$fname" < "$txt"
done

# 4. Перезапуск сервисов
echo ">>> Restarting vpn-static-routes..."
ssh "$ROUTER" "/etc/init.d/vpn-static-routes restart"

echo ">>> Restarting dnsmasq..."
ssh "$ROUTER" "/etc/init.d/dnsmasq restart"

echo ">>> Done."
