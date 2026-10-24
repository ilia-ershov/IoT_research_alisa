#!/bin/sh
# fastfetch-style system info for Yandex Station Lite (yandexmicro)
# Works on busybox/ash. No external deps.
c() { printf '\033[%sm' "$1"; }
R='\033[0m'
G='\033[1;32m'; C='\033[1;36m'; Y='\033[1;33m'; M='\033[1;35m'; B='\033[1;34m'; W='\033[1;37m'

HOST=$(hostname 2>/dev/null)
KERN=$(uname -r)
ARCH=$(uname -m)
OS=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')
[ -z "$OS" ] && OS=$(grep -E '^DISTRIB_DESCRIPTION=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')
UP=$(awk '{printf "%d:%02d", $1/3600, ($1%3600)/60}' /proc/uptime 2>/dev/null)
MEMT=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MEMF=$(awk '/MemFree/{print $2}' /proc/meminfo)
MEMU=$(( (MEMT - MEMF) / 1024 ))
MEMT_M=$(( MEMT / 1024 ))
CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
CPU=$(awk -F: '/model name|Processor|Hardware/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//')
[ -z "$CPU" ] && CPU="ARM Cortex-A53"
IP=$(ip addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
SSID=$(wpa_cli -i wlan0 status 2>/dev/null | awk -F= '/^ssid=/{print $2}')
DEV=$(cat /system/vendor/quasar/version_full 2>/dev/null)
DEVICE="Yandex Station Micro (Станция Лайт)"
# disk
DISK=$(df -h / 2>/dev/null | awk 'NR==2{print $2" ("$5" занято)"}')
# firmware date
FWD=$(echo "$DEV" | cut -d. -f6-7)

p() { printf "  %b%-12s%b %s\n" "$G" "$1" "$R" "$2"; }

echo
printf "%b" "$C"
cat <<'LOGO'
        .-"""-.
      .'  .-.  '.
     /   (   )   \
    |  .-'`-'-.  |
    | (  ALICE  ) |
     \  '-.-'  /
      '.  '-'  .'
        '-...-'
LOGO
printf "%b" "$W"
printf "  %s@%s\n" "$HOST" "$HOST"
printf "%b" "$R"
printf "  %b-------------------%b\n" "$G" "$R"
p "OS"       "$OS"
p "Kernel"   "$KERN ($ARCH)"
p "Device"   "$DEVICE"
p "Firmware" "$DEV"
p "Uptime"   "$UP"
p "Shell"    "busybox ash"
p "CPU"      "$CORES x $CPU"
p "Memory"   "${MEMU}MiB / ${MEMT_M}MiB"
p "Disk /"   "$DISK"
[ -n "$IP" ]     && p "IP"     "wlan0: $IP"
[ -n "$SSID" ]   && p "Wi-Fi"  "$SSID"
p "MAC"      "$(cat /sys/class/net/wlan0/address 2>/dev/null)"
p "Bluetooth" "$(hciconfig hci0 2>/dev/null | awk '/BD Address/{print $3}' | head -1)"
p "ADB"      "$(udp=0; cat /proc/net/tcp 2>/dev/null | grep -q ':15B3' && echo 'root :5555' || echo 'off')"
echo
