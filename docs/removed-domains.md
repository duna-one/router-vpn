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
