#!/bin/sh

if ! lsmod | grep nf_tables >/dev/null 2>&1; then
  if ! apk info -e iptables iptables-legacy >/dev/null 2>&1; then
    echo "Install iptables"
    apk add iptables iptables-legacy >/dev/null 2>&1
    rm -f /usr/sbin/iptables /usr/sbin/iptables-save /usr/sbin/iptables-restore
    ln -s /usr/sbin/iptables-legacy /usr/sbin/iptables
    ln -s /usr/sbin/iptables-legacy-save /usr/sbin/iptables-save
    ln -s /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore
  fi
else
  if ! apk info -e nftables >/dev/null 2>&1; then
    echo "Install nftables"
    apk add nftables >/dev/null 2>&1
  fi
  if apk info -e iptables iptables-legacy >/dev/null 2>&1; then
    echo "Delete iptables"
    apk del iptables iptables-legacy >/dev/null 2>&1
  fi
fi

FAKE_IP_RANGE="${FAKE_IP_RANGE:-198.18.0.0/15}"
FAKE_IP_FILTER="${FAKE_IP_FILTER:-}"
FAKE_IP_TTL="${FAKE_IP_TTL:-1}"
#   NAMESERVER_POLICY="domain1#dns1,domain2#dns2"
generate_nameserver_policy() {
  [ -z "${NAMESERVER_POLICY:-}" ] && return
  echo "  nameserver-policy:"
  OLDIFS=$IFS
  IFS=','
  for raw in $NAMESERVER_POLICY; do
    item=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$item" ] && continue
    domain=${item%%#*}
    dns=${item#*#}
    printf "    '%s': '%s'\n" "$domain" "$dns"
  done
  IFS=$OLDIFS
}

first_iface() {
  ip -o link show | awk -F': ' '/link\/ether/ {print $2}' | cut -d'@' -f1 | head -n1
}

config_file_mihomo_tproxy() {
cat > /root/.config/mihomo/config.yaml << EOF
log-level: ${LOGLEVEL:-error}
ipv6: false
dns:
  enable: true
  cache-algorithm: arc
  prefer-h3: false
  use-system-hosts: false
  respect-rules: false
  listen: 0.0.0.0:53
  ipv6: false
  default-nameserver:
    - 8.8.8.8
    - 9.9.9.9
    - 1.1.1.1
  enhanced-mode: fake-ip
  fake-ip-range: ${FAKE_IP_RANGE}
  fake-ip-ttl: ${FAKE_IP_TTL}${FAKE_IP_FILTER:+
  fake-ip-filter:}${FAKE_IP_FILTER:+$(printf '\n    - %s' $(echo "$FAKE_IP_FILTER" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'))}
EOF
generate_nameserver_policy >>  /root/.config/mihomo/config.yaml
cat >> /root/.config/mihomo/config.yaml <<EOF
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
    - https://dns.quad9.net/dns-query
hosts:
  dns.google: [8.8.8.8, 8.8.4.4]
  dns.quad9.net: [9.9.9.9, 149.112.112.112]
  cloudflare-dns.com: [104.16.248.249, 104.16.249.249]

listeners:
  - name: tproxy-in
    type: tproxy
    port: 12345
    listen: 0.0.0.0
    udp: true

rules:
  - MATCH,DIRECT

EOF
}
config_file_mihomo_tun() {
cat > /root/.config/mihomo/config.yaml << EOF
log-level: ${LOGLEVEL:-error}
ipv6: false
dns:
  enable: true
  cache-algorithm: arc
  prefer-h3: false
  use-system-hosts: false
  respect-rules: false
  listen: 0.0.0.0:53
  ipv6: false
  default-nameserver:
    - 8.8.8.8
    - 9.9.9.9
    - 1.1.1.1
  enhanced-mode: fake-ip
  fake-ip-range: ${FAKE_IP_RANGE}
  fake-ip-ttl: ${FAKE_IP_TTL}${FAKE_IP_FILTER:+
  fake-ip-filter:}${FAKE_IP_FILTER:+$(printf '\n    - %s' $(echo "$FAKE_IP_FILTER" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'))}
EOF
generate_nameserver_policy >>  /root/.config/mihomo/config.yaml
cat >> /root/.config/mihomo/config.yaml <<EOF
  nameserver:
    - https://dns.google/dns-query
    - https://cloudflare-dns.com/dns-query
    - https://dns.quad9.net/dns-query
hosts:
  dns.google: [8.8.8.8, 8.8.4.4]
  dns.quad9.net: [9.9.9.9, 149.112.112.112]
  cloudflare-dns.com: [104.16.248.249, 104.16.249.249]

listeners:
  - name: tun-in
    type: tun
    stack: system
    dns-hijack:
    - 0.0.0.0:53
    auto-detect-interface: false
    include-interface:
      - $(first_iface)
    auto-route: true
    strict-route: true
    auto-redirect: true
    inet4-address:
    - 198.19.0.1/30
    udp-timeout: 30
    mtu: 1500

rules:
  - AND,((NETWORK,udp),(DST-PORT,443),(DOMAIN-SUFFIX,googlevideo.com)),REJECT
  - MATCH,DIRECT
EOF
}

nft_rules () {
nft flush ruleset
nft -f - <<EOF
table inet mihomo_tproxy {
    chain prerouting {
        type filter hook prerouting priority filter; policy accept;
        ip daddr ${FAKE_IP_RANGE} meta l4proto { tcp, udp } iifname "$(first_iface)" meta mark set 0x00000001 tproxy ip to 127.0.0.1:12345 accept
        ip daddr { $(ip -4 addr show $(ip -o link show | awk -F': ' '/link\/ether/ {print $2}' | cut -d'@' -f1 | head -n1) | grep inet | awk '{ print $2 }' | cut -d/ -f1), 0.0.0.0/8, 127.0.0.0/8, 224.0.0.0/4, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 169.254.0.0/16, 192.0.0.0/24, 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 192.88.99.0/24, 198.18.0.0/15, 224.0.0.0/3 } return
        meta l4proto { tcp, udp } iifname "$(first_iface)" meta mark set 0x00000001 tproxy ip to 127.0.0.1:12345 accept
    }

    chain divert {
        type filter hook prerouting priority mangle; policy accept;
        meta l4proto tcp socket transparent 1 meta mark set 0x00000001 accept
    }
}
EOF
ip rule show | grep -q 'fwmark 0x00000001 lookup 100' || ip rule add fwmark 1 table 100
ip route replace local 0.0.0.0/0 dev lo table 100 table 100
}

run() {
mkdir -p /root/.config/mihomo
if lsmod | grep -q '^nft_tproxy'; then
   echo "nft_tproxy module loaded, use inbound TPROXY"
   nft_rules
   config_file_mihomo_tproxy
else
   echo "nft_tproxy not loaded, use inbound TUN with TCP redirect"
   config_file_mihomo_tun
fi
exec ./mihomo
}

run || exit 1
