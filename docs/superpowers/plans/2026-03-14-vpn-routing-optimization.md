# VPN Routing Optimization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize VPN selective routing — reduce whitelist bloat, add awg1 hotplug recovery, fix firewall for router-originated traffic.

**Architecture:** Replace init script with hotplug on awg1 ifup/ifdown. Add firewall OUTPUT mark rule so router DNS goes through fwmark like LAN traffic. Clean whitelists to ~95 domains.

**Tech Stack:** OpenWrt 24.10.5, dnsmasq-full (nftset), nftables (fw4), busybox ash, AmneziaWG

**Spec:** `docs/superpowers/specs/2026-03-14-vpn-routing-optimization-design.md`

**Router:** `ssh root@192.168.2.1`

**CRITICAL:** Router provides internet. Do NOT restart network service. Do NOT reboot without verifying DNS works. Always test before removing old config.

---

## Chunk 1: Whitelist Cleanup & Rollback Doc

### Task 1: Create removed-domains rollback document

**Files:**
- Create: `docs/removed-domains.md`

- [ ] **Step 1: Create rollback doc with all domains being removed**

```markdown
# Removed Domains (2026-03-14 optimization)

Domains removed from whitelists during optimization. dnsmasq nftset matches
subdomains automatically, so explicit subdomains of a parent already in the
list are redundant. Broad CDN/Google domains were removed to reduce unnecessary
VPN traffic.

If a service breaks, find the relevant section below and add the domain back
to the corresponding .lst file, then run `./scripts/deploy.sh`.

## youtube-google.lst

Removed (broad Google — not blocked in Russia):
- google.com
- googleapis.com
- gstatic.com
- googleusercontent.com
- ggpht.com
- googlesyndication.com
- googleadservices.com
- googletagmanager.com
- google-analytics.com
- googletagservices.com

Removed (redundant subdomains):
- yt3.ggpht.com (covered by ggpht.com, itself removed)
- yt3.googleusercontent.com (covered by googleusercontent.com, itself removed)
- youtubei.googleapis.com (covered by googleapis.com, itself removed)
- youtube.googleapis.com (covered by googleapis.com, itself removed)
- wide-youtube.l.google.com (covered by google.com, itself removed)

## cdn-cloud.lst

Removed (overly broad CDN providers):
- amazonaws.com
- cloudfront.net
- akamaized.net
- fastly.net
- cloudflare.com

## instagram-meta.lst

Removed (redundant subdomains of instagram.com):
- i.instagram.com
- api.instagram.com
- graph.instagram.com
- about.instagram.com
- help.instagram.com
- upload.instagram.com
- edge-chat.instagram.com
- l.instagram.com
- maps.instagram.com
- business.instagram.com
- developers.instagram.com

Removed (redundant subdomains of cdninstagram.com):
- static.cdninstagram.com
- scontent.cdninstagram.com
- video.cdninstagram.com

Removed (redundant subdomains of facebook.com):
- web.facebook.com
- staticxx.facebook.com
- lookaside.facebook.com
- edge-mqtt.facebook.com
- streaming-graph.facebook.com
- graph.facebook.com
- rupload.facebook.com

Removed (redundant subdomains of facebook.net):
- connect.facebook.net

Removed (redundant subdomains of fbcdn.net):
- fna.fbcdn.net
- external.xx.fbcdn.net
- scontent.xx.fbcdn.net
- static.xx.fbcdn.net
- video.xx.fbcdn.net

Removed (minor Meta properties):
- fbpigeon.com
- internalfb.com

## telegram.lst

Removed (redundant subdomains of telegram.org):
- core.telegram.org
- desktop.telegram.org
- web.telegram.org
- updates.telegram.org
- api.telegram.org
- cdn-telegram.org
- telegram-cdn.org

Removed (regional TLDs / redirects):
- telegram.app
- telegram.dev
- telegram.dog
- telegram.space
- tg.dev
- tg.org
- tx.me
- teleg.xyz
- telegram.ai
- telegram.asia
- telegram.biz
- telegram.cloud
- telegram.cn
- telegram.co
- telegram.de
- telegram.eu
- telegram.fr
- telegram.host
- telegram.in
- telegram.info
- telegram.io
- telegram.jp
- telegram.net
- telegram.qa
- telegram.ru
- telegram.services
- telegram.solutions
- telegram.team
- telegram.tech
- telegram.uk
- telegram.us
- telegram.website
- telegram.xyz
- telegramapp.org
- telegramdownload.com
- quiz.directory
- telega.one
- tgram.org
- torg.org

Removed (third-party / minor):
- nicegram.app
- comments.app
- usercontent.dev
- tdesktop.com
- telesco.pe

## discord.lst

Removed (redundant subdomains):
- cdn.discordapp.com (covered by discordapp.com)
- media.discordapp.net (covered by discordapp.net)
- images-ext-1.discordapp.net (covered by discordapp.net)
- gateway.discord.gg (covered by discord.gg)

## twitter-x.lst

Removed (redundant subdomains):
- abs.twimg.com (covered by twimg.com)
- pbs.twimg.com (covered by twimg.com)
- api.twitter.com (covered by twitter.com)
- api.x.com (covered by x.com)

## claude-anthropic.lst

Removed (redundant subdomains of anthropic.com):
- api.anthropic.com
- console.anthropic.com
- cdn.anthropic.com
- statsigapi.anthropic.com

## grok-xai.lst

Removed (redundant subdomains of x.ai):
- api.x.ai
- console.x.ai
- accounts.x.ai
- auth.x.ai

## openai-chatgpt.lst

Removed (redundant subdomains of openai.com):
- chat.openai.com
- api.openai.com

## whatsapp.lst

Removed (redundant subdomains of whatsapp.com):
- web.whatsapp.com

## spotify.lst

Removed (redundant subdomains):
- audio-sp-tyo.spotifycdn.com (covered by spotifycdn.com)
- ap-gew4.spotify.com (covered by spotify.com)

## misc-blocked.lst

Removed (redundant subdomains):
- updates.signal.org (covered by signal.org)
- i.imgur.com (covered by imgur.com)
- api.githubcopilot.com (covered by githubcopilot.com)
```

- [ ] **Step 2: Commit**

```bash
git add docs/removed-domains.md
git commit -m "Add removed-domains rollback reference for whitelist cleanup"
```

### Task 2: Clean whitelist files

**Files:**
- Modify: `whitelists/youtube-google.lst`
- Modify: `whitelists/cdn-cloud.lst`
- Modify: `whitelists/instagram-meta.lst`
- Modify: `whitelists/telegram.lst`
- Modify: `whitelists/discord.lst`
- Modify: `whitelists/twitter-x.lst`
- Modify: `whitelists/claude-anthropic.lst`
- Modify: `whitelists/grok-xai.lst`
- Modify: `whitelists/openai-chatgpt.lst`
- Modify: `whitelists/whatsapp.lst`
- Modify: `whitelists/spotify.lst`
- Modify: `whitelists/misc-blocked.lst`

- [ ] **Step 1: Rewrite youtube-google.lst**

New content (6 domains):
```
youtube.com
youtu.be
googlevideo.com
ytimg.com
yt.be
youtube-nocookie.com
```

- [ ] **Step 2: Rewrite cdn-cloud.lst**

New content (1 domain):
```
cloudflare-dns.com
```

- [ ] **Step 3: Rewrite instagram-meta.lst**

New content (11 domains):
```
instagram.com
cdninstagram.com
ig.me
igsonar.com
facebook.com
facebook.net
fbcdn.net
fb.com
fb.me
fbsbx.com
meta.com
```

- [ ] **Step 4: Rewrite telegram.lst**

New content (8 domains):
```
telegram.org
telegram.me
telegram.com
t.me
telegra.ph
graph.org
fragment.com
contest.com
```

- [ ] **Step 5: Rewrite discord.lst**

New content (6 domains):
```
discord.com
discord.gg
discordapp.com
discord.media
discordapp.net
discord.dev
```

- [ ] **Step 6: Rewrite twitter-x.lst**

New content (4 domains):
```
twitter.com
x.com
t.co
twimg.com
```

- [ ] **Step 7: Rewrite claude-anthropic.lst**

New content (2 domains):
```
anthropic.com
claude.ai
```

- [ ] **Step 8: Rewrite grok-xai.lst**

New content (2 domains):
```
grok.com
x.ai
```

- [ ] **Step 9: Rewrite openai-chatgpt.lst**

New content (2 domains):
```
openai.com
chatgpt.com
```

- [ ] **Step 10: Rewrite whatsapp.lst**

New content (2 domains):
```
whatsapp.com
whatsapp.net
```

- [ ] **Step 11: Rewrite spotify.lst**

New content (3 domains):
```
spotify.com
scdn.co
spotifycdn.com
```

- [ ] **Step 12: Edit misc-blocked.lst — remove 3 redundant lines**

Remove these lines:
- `updates.signal.org` (line 14)
- `i.imgur.com` (line 41)
- `api.githubcopilot.com` (line 46)

- [ ] **Step 13: Regenerate dnsmasq config**

```bash
bash scripts/gen-dnsmasq-nftset.sh whitelists dnsmasq-vpn-nftset.conf
```

Expected: `Generated 18 nftset rules in dnsmasq-vpn-nftset.conf` (same count, shorter lines)

- [ ] **Step 14: Commit**

```bash
git add whitelists/ dnsmasq-vpn-nftset.conf
git commit -m "Clean whitelists: remove redundant subdomains and broad CDN/Google domains

~232 domains reduced to ~95. See docs/removed-domains.md for rollback."
```

## Chunk 2: Hotplug Script & DNS IPs

### Task 3: Create dns-upstream-ips.txt

**Files:**
- Create: `whitelists/dns-upstream-ips.txt`

- [ ] **Step 1: Create the file**

```
# Upstream DNS servers — routed through VPN via nft set
1.1.1.1/32
1.0.0.1/32
```

- [ ] **Step 2: Commit**

```bash
git add whitelists/dns-upstream-ips.txt
git commit -m "Add upstream DNS IPs to whitelist for fwmark routing"
```

### Task 4: Create hotplug script

**Files:**
- Create: `scripts/99-vpn-routes.sh`

- [ ] **Step 1: Write the hotplug script**

```sh
#!/bin/sh
# Hotplug script for awg1 VPN interface
# Deployed to /etc/hotplug.d/iface/99-vpn-routes on router
#
# ifup:   configures vpn routing table, loads CIDRs into nft set
# ifdown: flushes vpn table so traffic falls through to WAN

[ "$INTERFACE" = "awg1" ] || exit 0

case "$ACTION" in
    ifup)
        logger -t vpn-routes "awg1 ifup: configuring VPN routes"

        # Protect WireGuard endpoint from fwmark routing loop
        ip rule del to 92.51.45.254 lookup main priority 50 2>/dev/null
        ip rule add to 92.51.45.254 lookup main priority 50

        # Default route in vpn table
        ip route replace default dev awg1 table vpn

        # Wait for fw4 to create the nft set (may not be ready at early boot)
        for i in 1 2 3 4 5; do
            nft list set inet fw4 vpn_domains >/dev/null 2>&1 && break
            logger -t vpn-routes "waiting for fw4 vpn_domains set ($i/5)"
            sleep 2
        done

        # Load static CIDRs into nft set
        for f in /etc/whitelists/*.txt; do
            [ -f "$f" ] || continue
            while IFS= read -r cidr; do
                [ -z "$cidr" ] && continue
                case "$cidr" in \#*) continue ;; esac
                nft add element inet fw4 vpn_domains "{ $cidr }" 2>/dev/null
            done < "$f"
        done

        # Clean up dnsr nftables if still present
        nft delete table ip dnsr-nf 2>/dev/null
        nft delete table ip dnsr-nat 2>/dev/null

        logger -t vpn-routes "awg1 ifup: VPN routes configured"
        ;;
    ifdown)
        logger -t vpn-routes "awg1 ifdown: flushing vpn table"
        ip route flush table vpn 2>/dev/null
        ;;
esac
```

- [ ] **Step 2: Commit**

```bash
git add scripts/99-vpn-routes.sh
git commit -m "Add hotplug script for awg1 ifup/ifdown VPN route management"
```

### Task 5: Update deploy.sh

**Files:**
- Modify: `scripts/deploy.sh`

- [ ] **Step 1: Rewrite deploy.sh**

New content:
```bash
#!/bin/bash
# Deploy whitelists and VPN routing config to router
# Usage: ./scripts/deploy.sh

set -euo pipefail

ROUTER="root@192.168.2.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHITELISTS_DIR="$PROJECT_DIR/whitelists"
CONF="$PROJECT_DIR/dnsmasq-vpn-nftset.conf"

# 1. Generate dnsmasq nftset config
echo ">>> Generating dnsmasq nftset config..."
bash "$SCRIPT_DIR/gen-dnsmasq-nftset.sh" "$WHITELISTS_DIR" "$CONF"

# 2. Deploy dnsmasq config
echo ">>> Deploying dnsmasq config..."
ssh "$ROUTER" "cat > /etc/dnsmasq.d/vpn-nftset.conf" < "$CONF"

# 3. Deploy CIDR files
for txt in "$WHITELISTS_DIR"/*.txt; do
    [ -f "$txt" ] || continue
    fname="$(basename "$txt")"
    echo ">>> Deploying $fname..."
    ssh "$ROUTER" "cat > /etc/whitelists/$fname" < "$txt"
done

# 4. Deploy hotplug script
echo ">>> Deploying hotplug script..."
ssh "$ROUTER" "cat > /etc/hotplug.d/iface/99-vpn-routes && chmod +x /etc/hotplug.d/iface/99-vpn-routes" < "$SCRIPT_DIR/99-vpn-routes.sh"

# 5. Restart dnsmasq
echo ">>> Restarting dnsmasq..."
ssh "$ROUTER" "/etc/init.d/dnsmasq restart"

# 6. Trigger hotplug (reload CIDRs into nft set)
echo ">>> Triggering VPN route reload..."
ssh "$ROUTER" "ACTION=ifup INTERFACE=awg1 /bin/sh /etc/hotplug.d/iface/99-vpn-routes"

# 7. Smoke test
echo ">>> Running smoke test..."
if ssh "$ROUTER" "nslookup telegram.org 127.0.0.1 >/dev/null 2>&1"; then
    echo ">>> DNS: OK"
else
    echo ">>> WARNING: DNS check failed!"
fi

if ssh "$ROUTER" "nft list set inet fw4 vpn_domains 2>/dev/null | grep -q '149.154'"; then
    echo ">>> nft set (Telegram CIDR): OK"
else
    echo ">>> WARNING: Telegram CIDR not found in nft set!"
fi

echo ">>> Done."
```

- [ ] **Step 2: Commit**

```bash
git add scripts/deploy.sh
git commit -m "Update deploy.sh: hotplug deploy, remove CRLF workaround, add smoke test"
```

## Chunk 3: Router Config Changes & Deploy

### Task 6: Apply firewall changes on router

This task runs commands on the live router via SSH. Do NOT restart network.

- [ ] **Step 1: Add mark_domains_output firewall rule**

```bash
ssh root@192.168.2.1 '
uci add firewall rule
uci set firewall.@rule[-1].name="mark_domains_output"
uci set firewall.@rule[-1].dest="*"
uci set firewall.@rule[-1].proto="all"
uci set firewall.@rule[-1].ipset="vpn_domains"
uci set firewall.@rule[-1].set_mark="0x1"
uci set firewall.@rule[-1].target="MARK"
uci set firewall.@rule[-1].family="ipv4"
uci commit firewall
echo "mark_domains_output rule added"
'
```

- [ ] **Step 2: Verify the new rule exists**

```bash
ssh root@192.168.2.1 'uci show firewall | grep mark_domains_output'
```

Expected: shows the new rule with all fields.

- [ ] **Step 3: Delete duplicate awg1-lan forwarding**

First identify which one is the duplicate:
```bash
ssh root@192.168.2.1 'uci show firewall | grep "awg1-lan"'
```

Then delete the last duplicate (index @forwarding[3] based on config-snapshot):
```bash
ssh root@192.168.2.1 'uci delete firewall.@forwarding[3]; uci commit firewall; echo "duplicate deleted"'
```

Verify only one remains:
```bash
ssh root@192.168.2.1 'uci show firewall | grep "awg1-lan"'
```

- [ ] **Step 4: Reload firewall**

```bash
ssh root@192.168.2.1 '/etc/init.d/firewall reload && echo "firewall reloaded"'
```

- [ ] **Step 5: Verify fwmark works for OUTPUT**

```bash
ssh root@192.168.2.1 'nslookup telegram.org 127.0.0.1 >/dev/null 2>&1 && echo "DNS OK" || echo "DNS FAIL"'
```

### Task 7: Deploy new config to router

- [ ] **Step 1: Run deploy.sh**

```bash
./scripts/deploy.sh
```

Expected output: all steps OK, smoke test passes.

- [ ] **Step 2: Remove static DNS routes from main table**

These are no longer needed (fwmark OUTPUT handles it):
```bash
ssh root@192.168.2.1 'ip route del 1.1.1.1 dev awg1 2>/dev/null; ip route del 1.0.0.1 dev awg1 2>/dev/null; echo "static DNS routes removed"'
```

- [ ] **Step 3: Verify DNS still works without static routes**

```bash
ssh root@192.168.2.1 'nslookup claude.ai 127.0.0.1 && echo "DNS OK"'
```

If DNS fails: the OUTPUT fwmark rule isn't working. Restore static routes immediately:
```bash
ssh root@192.168.2.1 'ip route add 1.1.1.1 dev awg1; ip route add 1.0.0.1 dev awg1'
```

- [ ] **Step 4: Disable and remove old init script**

Only after verifying everything works:
```bash
ssh root@192.168.2.1 '/etc/init.d/vpn-static-routes disable 2>/dev/null; rm -f /etc/init.d/vpn-static-routes; echo "old init script removed"'
```

- [ ] **Step 5: Full verification**

```bash
ssh root@192.168.2.1 '
echo "=== vpn table ==="
ip route show table vpn
echo "=== main awg1 routes ==="
ip route show | grep awg1 || echo "none (expected)"
echo "=== ip rules ==="
ip rule show | grep -E "fwmark|92.51"
echo "=== firewall marks ==="
uci show firewall | grep mark_domains
echo "=== memory ==="
free
echo "=== DNS test ==="
nslookup telegram.org 127.0.0.1 | head -4
echo "=== nft set sample ==="
nft list set inet fw4 vpn_domains 2>/dev/null | head -10
'
```

Expected:
- vpn table: `default dev awg1 scope link`
- main awg1 routes: `none (expected)`
- ip rules: fwmark 0x1 → vpn, 92.51.45.254 → main
- Two mark_domains rules (lan + output)
- DNS resolves
- nft set has elements

- [ ] **Step 6: Commit deploy script removal of vpn-static-routes.sh**

```bash
git rm scripts/vpn-static-routes.sh
git commit -m "Remove vpn-static-routes init script, replaced by hotplug"
```

### Task 8: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update architecture section in README**

Update the "Сервисы на роутере" table — replace `vpn-static-routes` with hotplug description. Add note about `mark_domains_output`. Remove mention of static DNS routes.

Changes to make:
- In the services table, replace `vpn-static-routes` row with:
  `| hotplug 99-vpn-routes | Автоматическая настройка VPN-маршрутов при поднятии/падении awg1 |`
- Update the deploy section to note that deploy.sh now includes smoke test

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Update README for hotplug and firewall OUTPUT rule"
```

### Task 9: Final smoke test from LAN device

- [ ] **Step 1: Test services from a device on the LAN**

From a phone or PC behind the router, verify these work:
- Telegram (send a message)
- YouTube (play a video)
- Instagram (open feed)
- Claude/ChatGPT (if accessible)
- A non-VPN site (e.g. google.com should load fast, not through VPN)

If any service fails: check `docs/removed-domains.md`, add back the needed domain, re-run `./scripts/deploy.sh`.
