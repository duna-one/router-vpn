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
2. Статические IP-подсети из `*.txt` добавляются в тот же nft set при старте (`vpn-static-routes`)
3. Firewall правило `mark_domains`: пакеты к IP из `vpn_domains` → fwmark `0x1`
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
| `vpn-static-routes` | Добавляет default route в vpn table, CIDR из `*.txt` в nft set, маршруты для DNS |

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
| youtube-google.lst | YouTube, Google |
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
| cdn-cloud.lst | CDN/облачные |

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
4. Перезапускает `vpn-static-routes` и `dnsmasq`

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
  vpn-static-routes.sh   — init-скрипт для роутера
  deploy.sh              — деплой на роутер
dnsmasq-vpn-nftset.conf  — сгенерированный dnsmasq конфиг
docs/                     — документация по миграции
config-snapshot/          — снапшоты конфигурации роутера (до миграции)
```
