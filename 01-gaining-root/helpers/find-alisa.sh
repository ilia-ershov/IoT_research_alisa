#!/usr/bin/env bash
# ============================================================================
# Найти Яндекс Станцию (yandex-micro) в текущей сети и подключиться по adb.
# Ищет по MAC [REDACTED-MAC] (ARP), fallback — по открытому порту 5555 (adbd).
# Работает на macOS. Подсеть определяется автоматически (предполагается /24).
# ============================================================================
set -uo pipefail

STATION_MAC="[REDACTED-MAC]"
PORT=5555

# --- 1. Определить активный интерфейс и мой IP ---
IFACE=""; MY_IP=""
for i in en0 en1 en2 en3; do
  ip=$(ipconfig getifaddr "$i" 2>/dev/null)
  if [ -n "$ip" ]; then IFACE="$i"; MY_IP="$ip"; break; fi
done
if [ -z "$MY_IP" ]; then
  echo "[!] Не нашёл IP на en0-en3 (нет Wi-Fi/сети?)" >&2
  exit 1
fi
SUBNET="${MY_IP%.*}"
echo "[*] Интерфейс $IFACE, мой IP $MY_IP, сканирую $SUBNET.0/24 ..."

# --- 2. Ping-sweep, чтобы заполнить ARP-таблицу ---
seq 1 254 | xargs -P 64 -I{} sh -c "ping -c1 -t1 $SUBNET.{} >/dev/null 2>&1"

# --- 3. Ищем по MAC в ARP ---
IP=$(arp -a 2>/dev/null | grep -i "$STATION_MAC" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

# --- 4. Fallback: ищем по порту adb (5555) ---
if [ -z "$IP" ]; then
  echo "[*] По MAC не нашёл, ищу по порту $PORT ..."
  IP=$(seq 1 254 | xargs -P 64 -I{} sh -c "nc -z -G1 $SUBNET.{} $PORT 2>/dev/null && echo $SUBNET.{}" | head -1)
fi

if [ -z "$IP" ]; then
  echo "[!] Колонка не найдена в $SUBNET.0/24. Убедись, что Mac и колонка в одной сети." >&2
  exit 1
fi
echo "[*] Колонка найдена: $IP"

# --- 5. Подключение и проверка root ---
adb connect "$IP:$PORT"
sleep 1
ID=$(adb -s "$IP:$PORT" shell id 2>/dev/null | tr -d '\r')
echo "[*] id: $ID"
if echo "$ID" | grep -q "uid=0(root)"; then
  echo "[OK] ROOT есть."
else
  echo "[!] root не подтверждён (но adb ответил)."
fi

echo "Подключение вручную:  adb connect $IP:$PORT"
