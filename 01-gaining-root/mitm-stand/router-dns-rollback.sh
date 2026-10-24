#!/bin/sh
# ============================================================================
# Откат DNS на роутере: восстановить бэкап /etc/dnsmasq.conf.
# ============================================================================
set -e
BACKUP=/etc/dnsmasq.conf.bak-before-equasar
if [ -f "$BACKUP" ]; then
  cp "$BACKUP" /etc/dnsmasq.conf
  /etc/init.d/dnsmasq restart
  echo "[*] dnsmasq.conf восстановлен из $BACKUP и dnsmasq перезапущен"
else
  echo "[!] бэкап $BACKUP не найден"
  exit 1
fi
