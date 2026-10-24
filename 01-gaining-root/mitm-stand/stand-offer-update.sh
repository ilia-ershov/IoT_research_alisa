#!/usr/bin/env bash
# ============================================================================
# Включить ОДНО обновление: /check_updates начинает отдавать offer на
# yandexmicro 0.369.1.46 (13.10.2026) — это версия, которая ещё принимает
# eMudhra-цепочку. Заводская 0.1.1.6 (2021) без этого апдейта не умеет
# активироваться (не вызывает /get_sync_info).
# ЗАПУСКАТЬ ОТ ROOT:   sudo bash stand-offer-update.sh
# ============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Запусти от root:  sudo bash $0" >&2
  exit 1
fi

NGX_BIN="$(command -v nginx || true)"
[ -n "$NGX_BIN" ] || { echo "nginx не найден"; exit 1; }
NGX_PREFIX="$(cd "$(dirname "$NGX_BIN")/.." && pwd)"
CONF="$NGX_PREFIX/etc/nginx/servers/quasar"
[ -f "$CONF" ] || { echo "конфиг $CONF не найден"; exit 1; }
cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"

cat > "$CONF" <<'NGINX'
server {
    listen 80;
    server_name quasar.yandex.net quasar.yandex.ru scbh.yandex.net;
    location = /generate_204 { return 204; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    server_name quasar.yandex.net quasar.yandex.ru scbh.yandex.net;
    ssl_certificate     /opt/fakequasar/certs/fullchain.pem;
    ssl_certificate_key /opt/fakequasar/certs/quasar-all.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    http2 off;
    access_log /opt/fakequasar/logs/quasar.access.log;
    error_log  /opt/fakequasar/logs/quasar.error.log;

    location = /generate_204 { return 204; }

    location = /get_sync_info {
        default_type application/json;
        return 200 '{"status":"ok","config":{"account_config":{"spotter":"alisa"},"device_config":{"name":"quasar"},"adbd":{"remoteActivation":true,"network":true,"fullDurationMs":31536000000},"system_config":{"adbd":{"remoteActivation":true,"network":true,"fullDurationMs":31536000000}}},"subscription":{"mode":"transaction"}}';
    }

    location = /check_updates {
        default_type application/json;
        return 200 '{"hasUpdate":true,"version":"0.369.1.46.4778262442.20261013.297","downloadUrl":"https://cdnriqbxswemmatxzibl.svc.cdn.yandex.net/yandexmicro/ota/user/770338e8-a517-4642-a442-d26be2632873/0.369.1.46.4778262442.20261013.297.zip","crc32":371630625,"critical":true,"fallbackUrl":"https://quasar.s3.yandex.net/yandexmicro/ota/user/770338e8-a517-4642-a442-d26be2632873/0.369.1.46.4778262442.20261013.297.zip","fallbackIp":"93.158.134.158","updateId":"150484"}';
    }

    location / {
        resolver 8.8.8.8 1.1.1.1 valid=60s ipv6=off;
        proxy_pass https://$host$request_uri;
        proxy_http_version 1.1;
        proxy_ssl_server_name on;
        proxy_ssl_name $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
NGINX

echo "[*] nginx -t:"
nginx -t
nginx -s stop 2>/dev/null || true
nginx
sleep 1
echo "--- /check_updates теперь отдаёт ---"
curl -sk --resolve quasar.yandex.net:443:127.0.0.1 https://quasar.yandex.net/check_updates; echo
echo
echo "[OK] Оффер .46 включён. Колонка заберёт его на ближайшем опросе (~90 сек) и начнёт качать обновление."
echo "Следи за логом:  tail -f /opt/fakequasar/logs/quasar.access.log"
