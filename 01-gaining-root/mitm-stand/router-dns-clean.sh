#!/bin/sh
# ============================================================================
# Полное снятие DNS-подмены стенда: убираем наш блок address= (quasar -> .218,
# голос -> 127.0.0.1). После этого quasar резолвится в настоящий IP Яндекса.
# ============================================================================
set -e
sed -i '/^# equasar-stand:/d; /^address=\/quasar\.yandex/d; /^address=\/scbh\.yandex/d; /^address=\/strm\.yandex/d; /^address=\/rpc\.alice/d; /^address=\/uniproxy\.alice/d; /^address=\/alice\.yandex/d; /^address=\/alice-ats/d' /etc/dnsmasq.conf
/etc/init.d/dnsmasq restart
echo "[*] DNS-подмена снята"
echo "--- quasar.yandex.net ---"; nslookup quasar.yandex.net 127.0.0.1 2>/dev/null | tail -2
echo "--- strm.yandex.net ---";  nslookup strm.yandex.net 127.0.0.1 2>/dev/null | tail -2
