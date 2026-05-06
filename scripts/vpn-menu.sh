#!/bin/bash
# Локальное интерактивное меню переключения режима маршрутизации.
# Запускается на компе, ходит SSH на роутер и зовёт /usr/bin/vpn-all.
#
# Usage:  ./scripts/vpn-menu.sh
#
# Намеренно без `set -e` — меню должно переживать сетевые/ssh-сбои и не
# выпадать в шелл из-за них. Ошибки показываем явно.

set -u

ROUTER="${ROUTER:-root@192.168.2.1}"
SSH_OPTS=( -o ConnectTimeout=5 -o BatchMode=yes )

router() { ssh "${SSH_OPTS[@]}" "$ROUTER" "$@"; }

print_header() {
    clear 2>/dev/null || printf '\n\n'
    echo "=============================================="
    echo "  Router VPN — переключение режима"
    echo "  $ROUTER"
    echo "=============================================="
    local out rc
    out="$(router vpn-all status 2>&1)"; rc=$?
    if [ $rc -ne 0 ]; then
        echo "  [!] не достучался до роутера (ssh rc=$rc):"
        printf '%s\n' "$out" | sed 's/^/      /'
    else
        printf '%s\n' "$out" | sed 's/^/  /'
    fi
    echo "=============================================="
}

# stderr-only сообщения, чтобы не попадали в "$(read_minutes)"
err() { printf '%s\n' "$*" >&2; }

read_minutes() {
    # Печатает в stdout: "" (бессрочно) или число секунд.
    # Возвращает 1 если пользователь отменил (q).
    local mins
    while :; do
        if ! read -r -p "На сколько минут? (Enter — бессрочно, q — отмена): " mins; then
            return 1   # EOF / Ctrl-D
        fi
        case "$mins" in
            q|Q)        return 1 ;;
            '')         echo ""; return 0 ;;
            0)          err "  ноль не годится" ;;
            *[!0-9]*)   err "  введи число, Enter (бессрочно) или q (отмена)" ;;
            *)          echo "$((mins * 60))"; return 0 ;;
        esac
    done
}

run_and_show() {
    # запустить vpn-all с аргументами, показать вывод и подождать Enter
    echo
    local out rc
    out="$(router "$@" 2>&1)"; rc=$?
    if [ $rc -eq 0 ]; then
        echo "  ✓ выполнено:"
    else
        echo "  ✗ ошибка (ssh rc=$rc):"
    fi
    printf '%s\n' "$out" | sed 's/^/    /'
    echo
    read -r -p "Enter — назад в меню " _ || true
}

get_my_public_ip() {
    # с твоего компа. curl есть в Win10/11 из коробки.
    local ip
    for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ip="$(curl -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]')"
        if [ -n "$ip" ]; then echo "$ip"; return 0; fi
    done
    return 1
}

get_router_wan_ip() {
    # IP который видит мир, когда роутер ходит сам через WAN (без VPN).
    # OUTPUT-трафик роутера НЕ матчит iif br-lan, поэтому идёт через main.
    router "for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
        ip=\"\$(curl -fsS --max-time 4 \"\$u\" 2>/dev/null | tr -d '[:space:]')\"
        [ -n \"\$ip\" ] && { echo \"\$ip\"; exit 0; }
    done; exit 1" 2>/dev/null
}

get_router_vpn_ip() {
    # IP при выходе через awg1 — реальный VPN exit.
    router "for u in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
        ip=\"\$(curl -fsS --max-time 4 --interface awg1 \"\$u\" 2>/dev/null | tr -d '[:space:]')\"
        [ -n \"\$ip\" ] && { echo \"\$ip\"; exit 0; }
    done; exit 1" 2>/dev/null
}

verify_traffic() {
    echo
    echo "Проверяю откуда мир видит трафик..."
    echo "(несколько секунд)"
    echo

    # 1. Реальный режим
    local mode_raw mode_full=""
    mode_raw="$(router vpn-all status 2>/dev/null | head -1)"
    case "$mode_raw" in
        *FULL*)      mode_full=yes ;;
        *SELECTIVE*) mode_full=no ;;
        *)           mode_full="" ;;
    esac

    # 2. IP-адреса
    local me wan vpn
    me="$(get_my_public_ip || true)"
    wan="$(get_router_wan_ip || true)"
    vpn="$(get_router_vpn_ip || true)"

    # 3. Является ли test endpoint whitelist'нутым (попадает ли его IP в vpn_domains)
    local test_host="api.ipify.org"
    local test_ip whitelisted=""
    test_ip="$(router "nslookup $test_host 127.0.0.1 2>/dev/null | awk '/^Address [0-9]/ {print \$3; exit} /^Address: [0-9]/ {print \$2; exit}' | head -1")"
    test_ip="${test_ip%$'\r'}"
    if [ -n "$test_ip" ]; then
        if router "nft get element inet fw4 vpn_domains { $test_ip }" >/dev/null 2>&1; then
            whitelisted=yes
        else
            whitelisted=no
        fi
    fi

    # 4. Печать
    echo "  Режим (по vpn-all):      ${mode_raw:-?}"
    echo "  Твой IP (с компа):       ${me:-???}"
    echo "  IP роутера через WAN:    ${wan:-???}"
    echo "  IP роутера через VPN:    ${vpn:-???}"
    echo "  Test endpoint:           $test_host -> ${test_ip:-???} | в whitelist: ${whitelisted:-?}"
    echo

    # 5. Verdict
    if [ -z "$me" ]; then
        echo "  [?] не получилось узнать твой публичный IP — проверь интернет на компе"
    elif [ -z "$vpn" ]; then
        echo "  [✗] VPN-туннель НЕ работает — curl через awg1 не вышел в сеть"
    elif [ "$mode_full" = "yes" ]; then
        if [ "$me" = "$vpn" ]; then
            echo "  [✓] FULL VPN работает — весь твой трафик идёт через VPN ($vpn)"
        elif [ "$me" = "$wan" ]; then
            echo "  [✗] FULL VPN включён по статусу, но твой трафик идёт ЧЕРЕЗ WAN ($wan)."
            echo "      Что-то не так — глянь пункт 4 (Подробный статус)."
        else
            echo "  [?] FULL VPN включён, но твой IP ($me) не совпадает ни с WAN ни с VPN."
        fi
    elif [ "$mode_full" = "no" ]; then
        if [ "$whitelisted" = "yes" ] && [ "$me" = "$vpn" ]; then
            echo "  [i] Режим SELECTIVE. Этот endpoint ($test_host) попал в whitelist —"
            echo "      твой трафик к нему идёт через VPN ВСЕГДА, независимо от FULL."
            echo "      Этот тест НЕ годится для проверки FULL VPN."
            echo
            echo "      Чтобы реально проверить FULL — открой в браузере сайт, которого"
            echo "      нет в whitelist (yandex.ru, vk.com, mail.ru, любой не-VPN сайт),"
            echo "      и зайди на 2ip.ru. С FULL=on ты увидишь $vpn,"
            echo "      без него — $wan."
        elif [ "$me" = "$wan" ]; then
            echo "  [·] Режим SELECTIVE. Не-whitelist трафик идёт через WAN ($wan). Норма."
        elif [ "$me" = "$vpn" ]; then
            echo "  [i] Режим SELECTIVE, но трафик через VPN — endpoint скорее всего"
            echo "      whitelist'нут (resolved IP не нашли в vpn_domains, но домен может"
            echo "      резолвиться в другой IP при curl). Проверь не-whitelist сайтом."
        else
            echo "  [?] SELECTIVE, IP $me не совпадает ни с WAN ни с VPN — странно."
        fi
    else
        echo "  [?] не смог разобрать режим из 'vpn-all status': $mode_raw"
    fi
    echo
    read -r -p "Enter — назад в меню " _ || true
}

show_details() {
    echo
    echo "--- ip rule ---"
    router ip rule show || true
    echo
    echo "--- table vpn ---"
    router ip route show table vpn || true
    echo
    echo "--- awg1 ---"
    router "ip addr show awg1 2>/dev/null | head -3; echo; ifstatus awg1 2>/dev/null | grep -E '\"up\"|\"uptime\"' || true" || true
    echo
    read -r -p "Enter — назад в меню " _ || true
}

main_loop() {
    while :; do
        print_header
        echo "  1) Включить FULL VPN  (весь LAN через awg1)"
        echo "  2) Выключить FULL VPN (вернуться в SELECTIVE)"
        echo "  3) Проверить — реально ли трафик идёт через VPN"
        echo "  4) Подробный статус (ip rule / route / awg1)"
        echo "  0) Выход"
        echo
        local choice
        if ! read -r -p "> " choice; then
            echo "пока"; exit 0
        fi
        case "$choice" in
            1)
                local secs
                if secs="$(read_minutes)"; then
                    if [ -z "$secs" ]; then
                        run_and_show vpn-all on
                    else
                        run_and_show vpn-all on "$secs"
                    fi
                fi
                ;;
            2)
                run_and_show vpn-all off
                ;;
            3)
                verify_traffic
                ;;
            4)
                show_details
                ;;
            0|q|Q|'')
                echo "пока"
                exit 0
                ;;
            *)
                err "  ?"
                sleep 1
                ;;
        esac
    done
}

main_loop
