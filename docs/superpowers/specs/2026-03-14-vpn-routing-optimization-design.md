# VPN Routing Optimization

## Summary

Optimize the dnsmasq nftset + fwmark routing setup on OpenWrt router after migration from dnsr. Goals: reduce resource usage, improve reliability, improve coverage.

## Current State

- Router: OpenWrt 24.10.5, 119 MB RAM, ~42 MB free
- VPN: awg1 (AmneziaWG), endpoint `92.51.45.254`, fwmark 0x1 → vpn table (id 99) → default dev awg1
- DNS: dnsmasq (`noresolv=1`, `server=1.1.1.1`, `server=1.0.0.1`) — changed from stubby during migration, confirmed live on router via `uci show dhcp`
- Whitelists: ~232 domains in *.lst, ~25 CIDRs in *.txt
- Init script: vpn-static-routes (START=98) adds default route, DNS static routes (1.1.1.1, 1.0.0.1 in main table), CIDRs to nft set
- Firewall: mark_domains rule with src=lan only; duplicate awg1-lan forwarding; flow_offloading + flow_offloading_hw enabled
- nft set vpn_domains: ~300 lines of elements, grows with every DNS resolve
- Unused: singbox zone (tun0) — remnant of previous setup, out of scope for this spec

## Problems

1. **Bloated whitelists** — redundant subdomains (dnsmasq matches subdomains automatically), overly broad CDN/Google domains sending unrelated traffic through VPN
2. **No recovery on awg1 restart** — init script runs once at boot; if awg1 drops and reconnects, vpn table and nft set are not refreshed
3. **Router's own traffic not marked** — mark_domains has src=lan, so router traffic (DNS to 1.1.1.1) bypasses fwmark; requires static routes in main table as workaround
4. **Duplicate firewall forwarding** — two identical awg1-lan rules

## Design

### 1. Whitelist Cleanup

Reduce ~232 domains to ~95 by removing redundant subdomains and overly broad domains.

**Key changes:**

| File | Before | After | Notes |
|---|---|---|---|
| youtube-google.lst | 21 | 6 | Remove google.com, googleapis.com, gstatic.com, googleusercontent.com, ad/analytics domains. YouTube may have degraded thumbnails/UI — if so, add back ggpht.com or gstatic.com |
| cdn-cloud.lst | 6 | 1 | Keep only cloudflare-dns.com; remove amazonaws.com, cloudfront.net, akamaized.net, fastly.net, cloudflare.com. If a service (e.g. Spotify, Steam) degrades, check if it uses these CDNs and add the specific CDN hostname back |
| instagram-meta.lst | 37 | 11 | Remove all explicit subdomains of instagram.com, facebook.com, fbcdn.net; keep distinct second-level domains |
| telegram.lst | 55 | 8 | Remove ~25 regional TLDs, redundant subdomains; keep core domains |
| discord.lst | 10 | 6 | Remove explicit subdomains |
| twitter-x.lst | 8 | 4 | Remove explicit subdomains |
| claude-anthropic.lst | 6 | 2 | anthropic.com, claude.ai |
| grok-xai.lst | 6 | 2 | grok.com, x.ai |
| openai-chatgpt.lst | 4 | 2 | openai.com, chatgpt.com |
| whatsapp.lst | 3 | 2 | whatsapp.com, whatsapp.net |
| spotify.lst | 5 | 3 | spotify.com, scdn.co, spotifycdn.com |
| misc-blocked.lst | 47 | 44 | Remove 3 redundant subdomains: updates.signal.org (covered by signal.org), i.imgur.com (covered by imgur.com), api.githubcopilot.com (covered by githubcopilot.com) |

**Unchanged:** steam.lst, tiktok.lst, twitch.lst, linkedin.lst, reddit.lst

**Note on google.com removal:** This means Google Search, Gmail, Drive, Maps, Play Store, and Android services (e.g. connectivitycheck.gstatic.com) will route via WAN, not VPN. This is intentional — these services are not blocked in Russia.

**Rollback:** Removed domains documented in `docs/removed-domains.md`.

### 2. Hotplug Instead of Init Script

Replace `/etc/init.d/vpn-static-routes` with `/etc/hotplug.d/iface/99-vpn-routes`.

**On `ACTION=ifup INTERFACE=awg1`:**
- Wait for fw4 nft set to be ready (retry loop, max ~10s)
- `ip route replace default dev awg1 table vpn`
- Load all CIDRs from `/etc/whitelists/*.txt` into nft set vpn_domains
- Clean up dnsr nftables if present
- Log via `logger -t vpn-routes`

**On `ACTION=ifdown INTERFACE=awg1`:**
- `ip route flush table vpn` — prevents traffic black-holing into dead interface; packets fall through to main table (WAN) instead

Benefits:
- Automatically recovers when awg1 reconnects
- No dependency on init script ordering
- Runs at boot (awg1 ifup) AND on reconnect
- Graceful degradation on tunnel down (traffic goes via WAN, not black-holed)

### 3. Firewall Fix

**Safety: protect WireGuard endpoint from fwmark loop.**

Add ip rule to ensure the VPN endpoint is always routed via main table:
```
ip rule add to 92.51.45.254 lookup main priority 50
```
This prevents a routing loop if the endpoint IP ever ends up in vpn_domains. Added in hotplug script on ifup.

**Add rule `mark_domains_output`:**
- No src (matches router-originated traffic / OUTPUT chain)
- dest: *
- proto: all
- ipset: vpn_domains
- set_mark: 0x1
- target: MARK
- family: ipv4

This makes router's own traffic to VPN-destined IPs go through fwmark → vpn table → awg1. Eliminates the need for static routes for DNS (1.1.1.1, 1.0.0.1) in main table.

**Note on flow_offloading:** Hardware flow offloading is enabled. Established connections may bypass nftables rules, but this is fine — the initial packets establish the route via awg1, and subsequent offloaded packets follow the same path. Dynamic re-routing of existing connections is not supported, but is not needed.

**New file `whitelists/dns-upstream-ips.txt`:**
```
1.1.1.1/32
1.0.0.1/32
```
These are loaded into nft set by the hotplug script, ensuring DNS IPs are always marked for router-originated traffic.

**Remove duplicate forwarding:** Delete one of the two identical `awg1-lan` forwarding rules.

### 4. Updated deploy.sh

Deploys:
1. Generated `dnsmasq-vpn-nftset.conf` → `/etc/dnsmasq.d/`
2. `whitelists/*.txt` → `/etc/whitelists/`
3. Hotplug script → `/etc/hotplug.d/iface/99-vpn-routes`
4. Restarts dnsmasq
5. Triggers hotplug (re-reads CIDRs)
6. Smoke test: DNS resolution + nft set verification

Removes:
- vpn-static-routes restart (service deleted)
- CRLF conversion (handled by .gitattributes)

### 5. Files Changed

**New files:**
- `scripts/99-vpn-routes.sh` — hotplug script (source, deployed to router)
- `whitelists/dns-upstream-ips.txt` — upstream DNS IPs
- `docs/removed-domains.md` — rollback reference

**Modified files:**
- `whitelists/*.lst` — cleaned up (12 files)
- `scripts/deploy.sh` — updated for hotplug, added smoke test
- `scripts/gen-dnsmasq-nftset.sh` — no changes needed

**Removed from router:**
- `/etc/init.d/vpn-static-routes` — replaced by hotplug

**Router config changes (uci):**
- Add firewall rule `mark_domains_output`
- Delete duplicate forwarding `awg1-lan`

## Expected Results

| Metric | Before | After |
|---|---|---|
| Domains in whitelists | ~232 | ~95 |
| nftset rules in dnsmasq conf | 18 lines, very long | 18 lines, shorter |
| nft set growth rate | High (broad CDN domains) | Lower (targeted domains only) |
| awg1 restart recovery | Manual | Automatic (hotplug) |
| awg1 down behavior | Traffic black-holed | Traffic falls through to WAN |
| Router DNS routing | Static routes in main table | fwmark like everything else |
| Duplicate firewall rules | 1 | 0 |

## Rollback

If services break after whitelist cleanup:
1. Check `docs/removed-domains.md` for what was removed
2. Add back the specific domain that's needed
3. Run `./scripts/deploy.sh`

If routing breaks completely:
1. SSH to router
2. `ip route add default dev awg1 table vpn` (restore vpn table)
3. `ip route add 1.1.1.1 dev awg1 && ip route add 1.0.0.1 dev awg1` (restore DNS routes)
4. `/etc/init.d/dnsmasq restart`
