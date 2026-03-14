# VPN-работа: документация

## Доступ к роутеру
```
ssh root@192.168.2.1
```

## Архитектура

Роутер на OpenWrt. Для избирательной маршрутизации через VPN используется демон **`dnsr`**.

- **VPN-интерфейс:** `awg1` (AmneziaWG), IP: `10.8.1.2/32`
- **Скрипт запуска:** `/etc/init.d/dnsr` (START=99, procd)

### Как работает dnsr

1. Собирает все `*.lst` из `/etc/whitelists/` → `/tmp/dnsr-combined.lst` (домены)
2. Собирает все `*.txt` из `/etc/whitelists/` → `/tmp/dnsr-combined-ips.txt` (IP-подсети)
3. Запускает: `dnsr --interface awg1 --proxy-list /tmp/dnsr-combined.lst --preset-ips /tmp/dnsr-combined-ips.txt`

Домены резолвятся, их IP маршрутизируются через `awg1` (VPN).

### Управление сервисом
```sh
/etc/init.d/dnsr start
/etc/init.d/dnsr stop
/etc/init.d/dnsr restart
```

---

## Белые списки

### Расположение
| | Путь |
|---|---|
| Локальная рабочая копия | `C:\Users\dkorotkov\Desktop\vpn-work\whitelists\` |
| На роутере | `/etc/whitelists/` |

### Формат файлов
- `*.lst` — домены, по одному на строку: `example.com`
- `*.txt` — IP-подсети CIDR: `149.154.160.0/20`
- Пустые строки и `#`-комментарии игнорируются

### Текущие списки
| Файл | Строк | Содержимое |
|---|---|---|
| youtube-google.lst | 21 | YouTube, Google |
| instagram-meta.lst | 37 | Instagram, Meta CDN |
| misc-blocked.lst | 44 | Notion, Signal, BBC, Meduza и др. |
| telegram.lst | 17 | Telegram домены |
| telegram-ips.txt | 8 | Telegram IP-подсети |
| twitter-x.lst | 8 | Twitter/X |
| discord.lst | 10 | Discord |
| whatsapp.lst | 3 | WhatsApp |
| spotify.lst | 5 | Spotify |
| steam.lst | 4 | Steam |
| reddit.lst | 4 | Reddit |
| tiktok.lst | 4 | TikTok |
| twitch.lst | 3 | Twitch |
| openai-chatgpt.lst | 4 | OpenAI/ChatGPT |
| claude-anthropic.lst | 6 | Claude/Anthropic |
| grok-xai.lst | 4 | Grok/xAI |
| linkedin.lst | 2 | LinkedIn |
| cdn-cloud.lst | 6 | CDN/облачные |

---

## Типичные задачи

### Добавить домен в существующий список
```sh
echo "newdomain.com" >> whitelists/youtube-google.lst
scp whitelists/youtube-google.lst root@192.168.2.1:/etc/whitelists/
ssh root@192.168.2.1 "/etc/init.d/dnsr restart"
```

### Создать новый список
```sh
# Создать файл локально
echo "example.com" > whitelists/newservice.lst
# Скопировать на роутер
scp whitelists/newservice.lst root@192.168.2.1:/etc/whitelists/
ssh root@192.168.2.1 "/etc/init.d/dnsr restart"
```

### Синхронизировать все списки на роутер
```sh
scp whitelists/*.lst root@192.168.2.1:/etc/whitelists/
scp whitelists/*.txt root@192.168.2.1:/etc/whitelists/
ssh root@192.168.2.1 "/etc/init.d/dnsr restart"
```

### Проверить статус на роутере
```sh
ssh root@192.168.2.1 "wc -l /tmp/dnsr-combined.lst /tmp/dnsr-combined-ips.txt"
ssh root@192.168.2.1 "ps | grep dnsr"
```
