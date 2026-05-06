#!/bin/sh
# Toggle full LAN -> VPN routing.
# Deployed to /usr/bin/vpn-all on router.
#
# Usage:
#   vpn-all on [seconds]   route all forwarded LAN traffic via awg1;
#                          if seconds given, schedule auto-off in background.
#                          Повторный вызов `on N` сбрасывает таймер на новый.
#   vpn-all off            revert to selective routing (default)
#   vpn-all status         print human-readable status
#
# Implementation: adds an ip rule that matches LAN-forwarded traffic only
# (iif br-lan), so the router's own outbound traffic (incl. your SSH session)
# is NOT diverted. This avoids the OUTPUT-path MTU/MSS pitfall and keeps
# admin access alive. Selective routing via fwmark 0x1 (priority 100) stays
# untouched and continues to work in parallel.

set -eu

PRIO=200
LAN_IF=br-lan
TABLE=vpn
DEADLINE_FILE=/tmp/vpn-all.deadline

is_on() {
    # `ip rule show` печатает строки вида: "200:\tfrom all iif br-lan lookup vpn"
    # — приоритет в начале строки, НЕ как "priority N" в конце.
    ip rule show | grep -qE "^${PRIO}:.*lookup ${TABLE}([[:space:]]|\$)"
}

fmt_left() {
    # $1 = seconds left, prints "MM:SS" or "HH:MM:SS"
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%d:%02d:%02d' $((s/3600)) $(((s%3600)/60)) $((s%60))
    else
        printf '%d:%02d' $((s/60)) $((s%60))
    fi
}

print_status() {
    if is_on; then
        echo "Режим: FULL VPN (весь LAN через awg1)"
        if [ -f "$DEADLINE_FILE" ]; then
            local d now left
            d="$(cat "$DEADLINE_FILE" 2>/dev/null || echo 0)"
            now="$(date +%s)"
            left=$(( d - now ))
            if [ "$left" -gt 0 ]; then
                echo "Авто-офф через: $(fmt_left "$left")"
            fi
        else
            echo "Авто-офф: нет (включено бессрочно)"
        fi
    else
        echo "Режим: SELECTIVE (через VPN — только whitelist)"
    fi
}

validate_seconds() {
    case "$1" in
        ''|*[!0-9]*) echo "seconds must be a positive integer" >&2; exit 2 ;;
    esac
    [ "$1" -gt 0 ] || { echo "seconds must be > 0" >&2; exit 2; }
}

schedule_auto_off() {
    # $1 = seconds; writes deadline file and forks a guarded sleep
    local secs="$1"
    local deadline
    deadline=$(( $(date +%s) + secs ))
    echo "$deadline" > "$DEADLINE_FILE"
    (
        sleep "$secs"
        # only act if our deadline is still the current one
        cur="$(cat "$DEADLINE_FILE" 2>/dev/null || echo)"
        [ "$cur" = "$deadline" ] || exit 0
        ip rule del iif "$LAN_IF" lookup "$TABLE" priority "$PRIO" 2>/dev/null || true
        rm -f "$DEADLINE_FILE"
        logger -t vpn-all "auto-off after ${secs}s"
    ) >/dev/null 2>&1 &
}

case "${1:-}" in
    on)
        if [ -n "${2:-}" ]; then
            validate_seconds "$2"
        fi
        if ! is_on; then
            ip rule add iif "$LAN_IF" lookup "$TABLE" priority "$PRIO"
            logger -t vpn-all "ENABLED full LAN -> VPN"
        fi
        # invalidate any pending bg sleep from a previous schedule
        rm -f "$DEADLINE_FILE"
        if [ -n "${2:-}" ]; then
            schedule_auto_off "$2"
        fi
        print_status
        ;;
    off)
        # Идемпотентно: удаляем все вхождения правила с этим приоритетом
        # (на случай дубликатов от прошлых багов) и не падаем если их нет.
        deleted=0
        while ip rule del iif "$LAN_IF" lookup "$TABLE" priority "$PRIO" 2>/dev/null; do
            deleted=$((deleted + 1))
        done
        rm -f "$DEADLINE_FILE"
        if [ "$deleted" -gt 0 ]; then
            logger -t vpn-all "DISABLED ($deleted rule(s) removed)"
        fi
        print_status
        ;;
    status)
        print_status
        ;;
    *)
        echo "Usage: $0 on [seconds] | off | status" >&2
        exit 1
        ;;
esac
