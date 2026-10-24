#!/bin/sh
# ============================================================================
# Роутер OpenWrt: DNS-подмена под стенд eQuasar.
#   quasar/scbh  -> 192.168.50.218 (стенд на Mac)
#   голос/стриминг -> 127.0.0.1 (заглушка)
# Плюс чистка мусорных DHCP-резерваций из гайда (чужая подсеть 192.168.1.x).
# ============================================================================
set -e

BACKUP=/etc/dnsmasq.conf.bak-before-equasar
if [ ! -f "$BACKUP" ]; then
  cp /etc/dnsmasq.conf "$BACKUP"
  echo "[*] бэкап /etc/dnsmasq.conf -> $BACKUP"
fi

# убрать старые local= записи (гасили quasar в NXDOMAIN)
sed -i '/^# lite-stand:/d; /^local=\/quasar\.yandex/d; /^local=\/scbh\.yandex/d' /etc/dnsmasq.conf

# добавить address= записи
cat >> /etc/dnsmasq.conf <<'EOF'
# equasar-stand: quasar -> стенд (Mac .218), голос/стриминг -> заглушка
address=/quasar.yandex.net/192.168.50.218
address=/quasar.yandex.ru/192.168.50.218
address=/scbh.yandex.net/192.168.50.218
address=/strm.yandex.ru/127.0.0.1
address=/strm.yandex.net/127.0.0.1
address=/rpc.alice.yandex.net/127.0.0.1
address=/uniproxy.alice.yandex.net/127.0.0.1
address=/alice.yandex.net/127.0.0.1
address=/alice-ats.yandex.net/127.0.0.1
address=/alice-ats-test.yandex.net/127.0.0.1
EOF

# чистка мусорных резерваций (гайд-значения на чужой подсети)
if [ "$(uci get dhcp.@host[2].name 2>/dev/null)" = "infosec" ]; then
  uci delete dhcp.@host[2]
  echo "[*] удалена резервация infosec (192.168.1.138)"
fi
if [ "$(uci get dhcp.@host[1].name 2>/dev/null)" = "yandexmini2" ]; then
  uci delete dhcp.@host[1]
  echo "[*] удалена резервация yandexmini2 (192.168.1.141)"
fi
uci commit dhcp

/etc/init.d/dnsmasq restart
echo "[*] dnsmasq перезапущен"

# контроль
echo "--- quasar.yandex.net ---"; nslookup quasar.yandex.net 127.0.0.1 2>/dev/null | tail -2
echo "--- strm.yandex.net ---";  nslookup strm.yandex.net 127.0.0.1 2>/dev/null | tail -2
echo "--- alice.yandex.net ---"; nslookup alice.yandex.net 127.0.0.1 2>/dev/null | tail -2
