# Миграция с dnsr на dnsmasq nftset

## Проблема

`dnsr` перехватывает DNS-ответы и создаёт индивидуальный маршрут (`ip route add <IP> dev awg1`) на каждый резолвнутый IP. Сейчас 3483 маршрута в main table. Это:
- Нагружает слабый роутер (119 MB RAM, 34 MB свободно)
- Не покрывает hardcoded IP (Telegram клиенты ходят на DC напрямую по IP, без DNS)
- Дублирует работу: dnsr параллельно заполняет nft set `vpn_domains`, но fwmark-схема не задействована (таблица `vpn` пуста)

## Решение

Заменить dnsr на **dnsmasq `nftset`** + **статические CIDR** в nft set. Использовать уже существующую инфраструктуру:
- nft set `vpn_domains` (inet fw4, type ipv4_addr, flags interval, auto-merge)
- Firewall rule `mark_domains`: пакеты к IP из `vpn_domains` → fwmark 0x1
- ip rule: `fwmark 0x1 → lookup vpn` (приоритет 100)
- Routing table `vpn` (id 99 в /etc/iproute2/rt_tables)

Нужно только:
1. Активировать таблицу vpn (один default route через awg1)
2. Перенести домены из *.lst в dnsmasq nftset конфиг
3. Добавить CIDR из *.txt напрямую в nft set
4. Остановить и отключить dnsr

## Текущее состояние роутера

```
OpenWrt 24.10.5
dnsmasq-full 2.90 (с поддержкой nftset)
VPN интерфейс: awg1 (AmneziaWG)
Firewall: fw4 (nftables)
Shell: busybox ash
DNS: dnsmasq → 127.0.0.1#5453 (noresolv), filter_aaaa=1
IPv6: ULA на br-lan, wan6 dhcpv6 (но без внешнего IPv6 — нет global route)
Routing table vpn = id 99, пустая
ip rule: fwmark 0x1 → lookup vpn (priority 100)
```

## Файлы whitelists (локально, деплоятся на роутер)

```
*.lst — домены (построчно)
*.txt — IP CIDR (построчно)
```

Список файлов:
- cdn-cloud.lst, claude-anthropic.lst, discord.lst, grok-xai.lst
- instagram-meta.lst, instagram-meta-ips.txt
- linkedin.lst, misc-blocked.lst, openai-chatgpt.lst, reddit.lst
- spotify.lst, steam.lst, telegram.lst, telegram-ips.txt
- tiktok.lst, twitch.lst, twitter-x.lst, whatsapp.lst, youtube-google.lst

## План выполнения

### ВАЖНО: Безопасность

Доступ к Claude (этому агенту) идёт через VPN. Если VPN-маршрутизация сломается — связь потеряется. Поэтому:
- Каждый шаг проверяется отдельно
- Перед отключением dnsr убедиться что dnsmasq nftset работает
- Держать SSH-сессию к роутеру открытой на случай отката

### Шаг 0: Бэкап

```sh
ssh root@192.168.2.1 'cp /etc/init.d/dnsr /etc/init.d/dnsr.bak'
ssh root@192.168.2.1 'uci export dhcp > /tmp/dhcp-backup.conf'
ssh root@192.168.2.1 'uci export firewall > /tmp/firewall-backup.conf'
ssh root@192.168.2.1 'uci export network > /tmp/network-backup.conf'
```

### Шаг 1: Добавить default route в таблицу vpn

Таблица vpn (id 99) существует, но пуста. Нужен один маршрут.

```sh
ssh root@192.168.2.1 'ip route add default dev awg1 table vpn'
```

Проверка:
```sh
ssh root@192.168.2.1 'ip route show table vpn'
# Ожидаем: default dev awg1
```

Чтобы маршрут сохранялся после перезагрузки — добавить в network config:
```sh
ssh root@192.168.2.1 'uci set network.vpn_route=route
uci set network.vpn_route.interface="awg1"
uci set network.vpn_route.target="0.0.0.0/0"
uci set network.vpn_route.table="vpn"
uci commit network'
```

НЕ перезапускать network сейчас — маршрут уже добавлен вручную.

### Шаг 2: Генерация dnsmasq nftset конфига

Скрипт на ЛОКАЛЬНОЙ машине генерирует конфиг из *.lst файлов.

Создать файл `scripts/gen-dnsmasq-nftset.sh`:

```sh
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
```

Запуск:
```sh
chmod +x scripts/gen-dnsmasq-nftset.sh
./scripts/gen-dnsmasq-nftset.sh whitelists dnsmasq-vpn-nftset.conf
```

### Шаг 3: Скрипт для статических CIDR

Создать файл `scripts/gen-static-cidrs.sh`:

```sh
#!/bin/bash
# Генерирует nft-команды для добавления CIDR из *.txt в vpn_domains set
# nft set vpn_domains уже interval + auto-merge, поддерживает CIDR нативно

WHITELISTS_DIR="${1:-whitelists}"
OUTPUT="${2:-static-cidrs.nft}"

> "$OUTPUT"

for txt in "$WHITELISTS_DIR"/*.txt; do
    [ -f "$txt" ] || continue
    while IFS= read -r cidr; do
        [ -z "$cidr" ] && continue
        [[ "$cidr" == \#* ]] && continue
        cidr=$(echo "$cidr" | tr -d '[:space:]')
        [ -z "$cidr" ] && continue
        echo "add element inet fw4 vpn_domains { $cidr }" >> "$OUTPUT"
    done < "$txt"
done

echo "Generated $(wc -l < "$OUTPUT") CIDR elements in $OUTPUT"
```

### Шаг 4: Создать init-скрипт для статических CIDR на роутере

Файл `/etc/init.d/vpn-static-routes` на роутере:

```sh
#!/bin/sh /etc/rc.common

START=98
STOP=10

start_service() {
    # Добавить default route в таблицу vpn
    ip route replace default dev awg1 table vpn 2>/dev/null

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
```

START=98 — до dnsr (START=99), чтобы маршрут vpn был готов.

### Шаг 5: Деплой dnsmasq nftset конфига

```sh
# Деплой dnsmasq конфига (confdir=/tmp/dnsmasq.d уже настроен)
ssh root@192.168.2.1 "cat > /tmp/dnsmasq.d/vpn-nftset.conf" < dnsmasq-vpn-nftset.conf

# Деплой init-скрипта
ssh root@192.168.2.1 "cat > /etc/init.d/vpn-static-routes" < scripts/vpn-static-routes.sh
ssh root@192.168.2.1 "chmod +x /etc/init.d/vpn-static-routes"
ssh root@192.168.2.1 "/etc/init.d/vpn-static-routes enable"
```

### Шаг 6: Тест — запустить dnsmasq nftset параллельно с dnsr

Не останавливаем dnsr. Просто перезапускаем dnsmasq и проверяем.

```sh
# Запустить static routes
ssh root@192.168.2.1 "/etc/init.d/vpn-static-routes start"

# Проверить что vpn table получила default route
ssh root@192.168.2.1 "ip route show table vpn"
# Ожидаем: default dev awg1

# Проверить что CIDR попали в nft set
ssh root@192.168.2.1 "nft list set inet fw4 vpn_domains | grep '149.154.160'"
# Ожидаем: 149.154.160.0/20

# Перезапустить dnsmasq чтобы подхватил nftset конфиг
ssh root@192.168.2.1 "/etc/init.d/dnsmasq restart"

# Проверить что dnsmasq стартовал без ошибок
ssh root@192.168.2.1 "logread | tail -20 | grep -i dnsmasq"
```

**Критическая проверка — доступность сервисов через VPN:**
```sh
# С устройства в LAN проверить что Telegram, Claude и т.д. работают
# Если что-то сломалось — dnsr ещё работает как fallback через main table
```

### Шаг 7: Отключить dnsr

Только после успешной проверки в Шаге 6!

```sh
ssh root@192.168.2.1 "/etc/init.d/dnsr stop"
ssh root@192.168.2.1 "/etc/init.d/dnsr disable"
```

Проверить:
```sh
# Маршруты из main table должны уйти (dnsr их добавлял)
ssh root@192.168.2.1 "ip route show | grep -c awg1"
# Ожидаем: 0 или близко к 0

# А трафик всё равно идёт через VPN (через fwmark → vpn table)
ssh root@192.168.2.1 "ip route show table vpn"
# default dev awg1

# nft set всё ещё содержит IP (от dnsmasq nftset)
ssh root@192.168.2.1 "nft list set inet fw4 vpn_domains | head -5"
```

**Тест связности — проверить что Telegram, Claude, YouTube и т.д. работают.**

### Шаг 8: Очистка

```sh
# Удалить старые маршруты dnsr из main table (если остались)
ssh root@192.168.2.1 "ip route show | grep 'dev awg1' | while read r; do ip route del \$r; done"

# Проверить финальное состояние
ssh root@192.168.2.1 "echo '=== routes ==='; ip route show | wc -l; echo '=== vpn table ==='; ip route show table vpn; echo '=== memory ==='; free; echo '=== nft set size ==='; nft list set inet fw4 vpn_domains | grep -c ','"
```

### Шаг 9: Сделать dnsmasq nftset конфиг постоянным

Файл в `/tmp/dnsmasq.d/` не переживёт перезагрузку. Варианты:
- Положить в `/etc/dnsmasq.d/` (если директория существует)
- Или добавить nftset-строки прямо в uci config dhcp

```sh
# Проверить есть ли /etc/dnsmasq.d
ssh root@192.168.2.1 "ls -la /etc/dnsmasq.d/ 2>/dev/null || echo 'no /etc/dnsmasq.d'"

# Если нет — создать и прописать в dnsmasq
ssh root@192.168.2.1 "mkdir -p /etc/dnsmasq.d"
ssh root@192.168.2.1 "uci set dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'"
ssh root@192.168.2.1 "uci commit dhcp"

# Скопировать конфиг
ssh root@192.168.2.1 "cat > /etc/dnsmasq.d/vpn-nftset.conf" < dnsmasq-vpn-nftset.conf
```

## Откат (если что-то пошло не так)

```sh
# 1. Вернуть dnsr
ssh root@192.168.2.1 "/etc/init.d/dnsr enable"
ssh root@192.168.2.1 "/etc/init.d/dnsr start"

# 2. Остановить static routes
ssh root@192.168.2.1 "/etc/init.d/vpn-static-routes stop"

# 3. Удалить dnsmasq nftset конфиг
ssh root@192.168.2.1 "rm -f /tmp/dnsmasq.d/vpn-nftset.conf /etc/dnsmasq.d/vpn-nftset.conf"
ssh root@192.168.2.1 "/etc/init.d/dnsmasq restart"

# 4. Вернуть confdir если менялся
ssh root@192.168.2.1 "uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'"
ssh root@192.168.2.1 "uci commit dhcp"
```

## Ожидаемый результат

| Метрика | До | После |
|---|---|---|
| Маршруты в main table | ~3483 | ~0 |
| Маршруты в vpn table | 0 | 1 (default) |
| nft set vpn_domains | ~345 элементов (от dnsr) | Растёт по мере DNS-резолва + CIDR |
| Процесс dnsr | 522 MB VIRT | Нет |
| Telegram hardcoded IPs | Не покрыты | Покрыты через CIDR в nft set |
| Механизм | DNS sniff → individual routes | dnsmasq nftset → fwmark → vpn table |

## Важные замечания

- `filter_aaaa=1` в dnsmasq — IPv6 AAAA записи фильтруются, IPv6 Telegram подсети не нужны
- `confdir=/tmp/dnsmasq.d` — текущий confdir, файлы в /tmp не переживают перезагрузку (Шаг 9 решает это)
- dnsr nft-таблицы (`dnsr-nat`, `dnsr-nf`) останутся после остановки dnsr — их можно удалить вручную: `nft delete table ip dnsr-nat; nft delete table ip dnsr-nf`
- Дублирующийся forwarding `awg1-lan` в firewall config — не критично, но можно почистить
