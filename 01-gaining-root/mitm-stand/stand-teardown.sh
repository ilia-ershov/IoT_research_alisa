#!/usr/bin/env bash
# ============================================================================
# Откат стенда: остановить nginx и (опционально) восстановить старый конфиг.
# ЗАПУСКАТЬ ОТ ROOT:   sudo bash stand-teardown.sh
# ============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Запусти от root:  sudo bash $0" >&2
  exit 1
fi

if command -v nginx >/dev/null 2>&1; then
  nginx -s stop 2>/dev/null && echo "[OK] nginx остановлен" || echo "[*] nginx не был запущен"
  NGX_PREFIX="$(cd "$(dirname "$(command -v nginx)")/.." && pwd)"
  SERVERS_DIR="$NGX_PREFIX/etc/nginx/servers"
  latest="$(ls -1t "$SERVERS_DIR"/quasar.bak.* 2>/dev/null | head -1 || true)"
  if [ -n "$latest" ]; then
    cp "$latest" "$SERVERS_DIR/quasar"
    echo "[*] конфиг восстановлен из $latest"
  fi
fi

echo "[*] сертификаты остались в /opt/fakequasar/ (можно удалить: sudo rm -rf /opt/fakequasar)"
echo "[*] DNS на роутере откатывается отдельно (скрипт router-dns-rollback.sh)"
