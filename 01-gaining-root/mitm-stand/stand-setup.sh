#!/usr/bin/env bash
# ============================================================================
# Стенд eQuasar (nginx) для Яндекс Станции Лайт (platform yandexmicro)
# ЗАПУСКАТЬ ОТ ROOT:   sudo bash stand-setup.sh
# Предусловие: nginx уже установлен обычным пользователем:  brew install nginx
# ============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Запусти от root:  sudo bash $0" >&2
  exit 1
fi

NGX_BIN="$(command -v nginx || true)"
if [ -z "$NGX_BIN" ]; then
  echo "nginx не установлен." >&2
  echo "Сначала обычным пользователем (НЕ root) выполни:" >&2
  echo "    brew install nginx" >&2
  echo "и затем снова запусти этот скрипт от root." >&2
  exit 1
fi
NGX_PREFIX="$(cd "$(dirname "$NGX_BIN")/.." && pwd)"
SERVERS_DIR="$NGX_PREFIX/etc/nginx/servers"
echo "[*] nginx: $NGX_BIN (prefix $NGX_PREFIX)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CERTS="$SCRIPT_DIR/copymetoroot/opt/fakequasar/certs"

# --- 1. Сертификаты --------------------------------------------------------
mkdir -p /opt/fakequasar/certs /opt/fakequasar/logs
cp "$SRC_CERTS/fullchain.pem" /opt/fakequasar/certs/fullchain.pem
cp "$SRC_CERTS/quasar-all.key" /opt/fakequasar/certs/quasar-all.key
chmod 600 /opt/fakequasar/certs/quasar-all.key
chmod 644 /opt/fakequasar/certs/fullchain.pem
chmod 755 /opt/fakequasar/logs
echo "[*] сертификаты -> /opt/fakequasar/certs/"

# --- 2. Конфиг виртуалхоста (финальная версия из гайда) --------------------
mkdir -p "$SERVERS_DIR"
if [ -f "$SERVERS_DIR/quasar" ]; then
  cp "$SERVERS_DIR/quasar" "$SERVERS_DIR/quasar.bak.$(date +%Y%m%d%H%M%S)"
  echo "[*] старый конфиг сохранён как $SERVERS_DIR/quasar.bak.*"
fi
cat > "$SERVERS_DIR/quasar" <<'NGINX'
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
        return 200 '{"hasUpdate":false}';
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
echo "[*] конфиг -> $SERVERS_DIR/quasar"

# --- 3. Проверка конфига, перезапуск, старт --------------------------------
echo "[*] nginx -t:"
nginx -t
nginx -s stop 2>/dev/null || true
nginx
sleep 1

# --- 4. Самопроверка стенда -------------------------------------------------
echo "[*] самопроверка:"
echo "--- /get_sync_info ---"
curl -sk --resolve quasar.yandex.net:443:127.0.0.1 https://quasar.yandex.net/get_sync_info; echo
echo "--- /check_updates ---"
curl -sk --resolve quasar.yandex.net:443:127.0.0.1 https://quasar.yandex.net/check_updates; echo
echo "--- сертификат ---"
echo | openssl s_client -connect 127.0.0.1:443 -servername quasar.yandex.net 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null

echo
echo "=============================================================="
echo "[OK] Стенд запущен."
echo "Логи (следить в реальном времени):"
echo "  tail -f /opt/fakequasar/logs/quasar.access.log /opt/fakequasar/logs/quasar.error.log"
echo "Перезапуск стенда:"
echo "  sudo nginx -s stop && sudo nginx"
echo "Проверка TLS глазами:"
echo "  curl -vk --resolve quasar.yandex.net:443:127.0.0.1 https://quasar.yandex.net/"
echo "=============================================================="
