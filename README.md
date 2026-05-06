# VPN-работа: избирательная маршрутизация через VPN

## Доступ к роутеру
```
ssh root@192.168.2.1
```

## Архитектура

Роутер на OpenWrt 24.10.5. Избирательная маршрутизация через VPN реализована через **dnsmasq nftset** + **fwmark**.

- **VPN-интерфейс:** `awg1` (AmneziaWG), IP: `10.8.1.2/32`
- **DNS:** dnsmasq → 1.1.1.1 (Cloudflare, напрямую через VPN)
- **Firewall:** fw4 (nftables)

### Как работает маршрутизация

1. dnsmasq резолвит домены из whitelist-файлов и добавляет IP в nft set `vpn_domains` (директива `nftset`)
2. Статические IP-подсети из `*.txt` добавляются в тот же nft set через hotplug при поднятии awg1
3. Firewall правила `mark_domains` (LAN) и `mark_domains_output` (роутер): пакеты к IP из `vpn_domains` → fwmark `0x1`
4. ip rule: `fwmark 0x1 → lookup vpn` (приоритет 100)
5. Таблица `vpn` (id 99): один маршрут `default dev awg1`

```
DNS-запрос → dnsmasq (nftset) → IP в vpn_domains
Пакет к IP  → fw4 mark 0x1    → ip rule → vpn table → awg1 (VPN)
```

### Сервисы на роутере

| Сервис | Назначение |
|---|---|
| `dnsmasq` | DNS + DHCP, nftset-директивы из `/etc/dnsmasq.d/vpn-nftset.conf` |
| hotplug `99-vpn-routes` | Автоматическая настройка VPN-маршрутов при поднятии/падении awg1 |
| `/usr/bin/vpn-all` | Временно завернуть **весь** LAN-трафик в VPN (см. ниже) |

---

## Белые списки

### Расположение
| | Путь |
|---|---|
| Локальная рабочая копия | `whitelists/` |
| На роутере | `/etc/whitelists/` |
| dnsmasq nftset конфиг | `/etc/dnsmasq.d/vpn-nftset.conf` |

### Формат файлов
- `*.lst` — домены, по одному на строку: `example.com`
- `*.txt` — IP-подсети CIDR: `149.154.160.0/20`
- Пустые строки и `#`-комментарии игнорируются

### Текущие списки
| Файл | Содержимое |
|---|---|
| youtube-google.lst | YouTube |
| instagram-meta.lst | Instagram, Meta CDN |
| instagram-meta-ips.txt | Meta IP-подсети |
| misc-blocked.lst | Notion, Signal, BBC, Meduza и др. |
| telegram.lst | Telegram домены |
| telegram-ips.txt | Telegram IP-подсети |
| twitter-x.lst | Twitter/X |
| discord.lst | Discord |
| whatsapp.lst | WhatsApp |
| spotify.lst | Spotify |
| steam.lst | Steam |
| reddit.lst | Reddit |
| tiktok.lst | TikTok |
| twitch.lst | Twitch |
| openai-chatgpt.lst | OpenAI/ChatGPT |
| claude-anthropic.lst | Claude/Anthropic |
| grok-xai.lst | Grok/xAI |
| linkedin.lst | LinkedIn |
| cdn-cloud.lst | Cloudflare DNS |
| dns-upstream-ips.txt | IP upstream DNS-серверов |

---

## Типичные задачи

### Добавить домен в существующий список
```sh
echo "newdomain.com" >> whitelists/youtube-google.lst
./scripts/deploy.sh
```

### Создать новый список
```sh
echo "example.com" > whitelists/newservice.lst
./scripts/deploy.sh
```

### Деплой всех изменений на роутер
```sh
./scripts/deploy.sh
```

Скрипт автоматически:
1. Генерирует `dnsmasq-vpn-nftset.conf` из `whitelists/*.lst`
2. Деплоит его в `/etc/dnsmasq.d/` на роутере
3. Деплоит `*.txt` (CIDR) в `/etc/whitelists/`
4. Деплоит hotplug-скрипт
5. Перезапускает dnsmasq и перезагружает VPN-маршруты
6. Проверяет DNS и nft set (smoke test)

### Включить весь трафик через VPN на время

Самый удобный способ — интерактивное меню, запускается локально из репы:
```sh
bash ./scripts/vpn-menu.sh
```
Что умеет:
- Показывает текущий режим (`SELECTIVE` / `FULL VPN`) и сколько осталось до авто-офф
- Включить FULL VPN на N минут или бессрочно
- Выключить (вернуться в `SELECTIVE`)
- **Проверить «реально ли трафик идёт через VPN»** — снимает твой публичный IP, IP роутера через WAN и через VPN, с честным verdict (учитывает whitelist)
- Подробный статус: `ip rule`, `table vpn`, `awg1`

Прямые вызовы на роутере (то же самое под капотом):
```sh
ssh root@192.168.2.1 vpn-all on 1200   # 20 минут, потом сам выключится
ssh root@192.168.2.1 vpn-all on        # бессрочно
ssh root@192.168.2.1 vpn-all off       # выключить вручную
ssh root@192.168.2.1 vpn-all status    # человекочитаемый статус
```

Под капотом завёрнут **только forwarded LAN-трафик** (`iif br-lan → table vpn`,
priority 200). Собственный трафик роутера (включая твой SSH) идёт по main как
обычно — поэтому сессия не отваливается. MSS clamping (`mtu_fix=1` на zone
awg1) работает, потому что трафик forwarded. Селективный режим через
`fwmark 0x1` остаётся рядом и продолжает работать параллельно.

Авто-офф через `[seconds]` пишет дедлайн в `/tmp/vpn-all.deadline` и форкает
охранную `sleep`-задачу; повторный вызов `on N` корректно сбрасывает таймер на
новый. После перезагрузки роутера правило не восстанавливается — это by design.

### Проверить статус на роутере
```sh
# nft set (список IP для VPN)
ssh root@192.168.2.1 "nft list set inet fw4 vpn_domains | head -20"

# vpn routing table
ssh root@192.168.2.1 "ip route show table vpn"

# DNS тест
ssh root@192.168.2.1 "nslookup telegram.org 127.0.0.1"
```

---

## Структура проекта

```
whitelists/          — домены (*.lst) и IP-подсети (*.txt)
scripts/
  gen-dnsmasq-nftset.sh  — генератор dnsmasq nftset конфига
  99-vpn-routes.sh       — hotplug-скрипт для awg1 (деплоится на роутер)
  vpn-all.sh             — переключатель «всё через VPN» (деплоится в /usr/bin/vpn-all)
  vpn-menu.sh            — локальное интерактивное меню (НЕ деплоится, ходит SSH-ом)
  deploy.sh              — деплой на роутер
dnsmasq-vpn-nftset.conf  — сгенерированный dnsmasq конфиг
docs/                     — документация по миграции
config-snapshot/          — снапшоты конфигурации роутера (до миграции)
```
