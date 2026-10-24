# Файловая система Яндекс Станции Лайт (`yandexmicro`)

> Снято через root‑ADB на `0.369.1.50.4794655315.20261021.297`. Только чтение.
> Платформа: Amlogic AXG (A113X), 32‑битный userland (armhf), glibc **2.30**, busybox 1.31.1, Buildroot 2020.02.1.

---

## 1. Файловые системы и разделы

| Точка | Устройство | Тип | Режим | Размер/занято | Что это |
|---|---|---|---|---|---|
| `/` | `ubi0:rootfs` | **UBIFS** | **ro** | 64.8M / 52.6M (81%) | системный rootfs (read‑only) |
| `/bkupgrade` | `/dev/ubi1_0` | **UBIFS** | **rw** | 87.2M / 4.1M (5%) | «data» (userdata) + OTA‑хранилище |
| `/data` | → `/bkupgrade/data` | симлинк | rw | — | пользовательские данные |
| `/dev` | devtmpfs | devtmpfs | rw | 106M | узлы устройств |
| `/dev/pts` | devpts | devpts | rw | — | псевдотерминалы |
| `/dev/shm` | tmpfs | tmpfs | rw | 119M | shared memory |
| `/tmp` | tmpfs | tmpfs | rw | 119M (14.7M) | временное |
| `/run` | tmpfs | tmpfs | rw | 119M | run‑state (pid, сокеты) |
| `/sys` | sysfs | sysfs | rw | — | ядро/устройства |
| `/sys/kernel/debug` | none | debugfs | rw | — | отладка |
| `/sys/fs/pstore` | pstore | pstore | rw | — | crash‑логи (ramoops) |
| `/tee` | `/dev/mtdblock4` | **vfat** (в fstab: auto/jffs2) | **ro** | 1006K | TEE‑хранилище (OP‑TEE) |
| `/etc/unbound` | tmpfs | tmpfs | rw | 119M | конфиг/состояние unbound |
| `/etc/wifi/w1` | tmpfs | tmpfs | rw | 119M | Wi‑Fi‑калибровка w1 |

**Виртуальные (не на диске):** `/proc` (proc), `/sys` (sysfs), `/dev` (devtmpfs), `/tmp`, `/run` (tmpfs), `/var/log|lock|cache|spool|tmp → /tmp`, `/var/run → /run`, `/var/www` (www-data, пуст).

**NAND‑разделы (MTD):** `0 bootloader`, `1 tpl`, `2 boot`, `3 system` (→ ubi0), `4 nv` (→ /tee), `5 bkupgrade` (→ ubi1), `6 recovery`.
**UBI:** `ubi0` (rootfs) и `ubi1` (data, 101.7 MiB, в т.ч. том `data`).

---

## 2. Корень `/` — карта

| Путь | Что это |
|---|---|
| `bin/` | busybox‑апплеты + `busybox` |
| `sbin/` | системные утилиты (init, mount, ip, modprobe…) |
| `lib/` | glibc 2.30, libstdc++, `libteec`, модули ядра, firmware |
| `lib32 → lib` | алиас 32‑битной библиотеки |
| `usr/` | bin/sbin/lib/share (пакеты) |
| `etc/` | вся конфигурация |
| `system/` | `vendor/quasar` — сам Quasar |
| `data → bkupgrade/data` | userdata |
| `bkupgrade/` | rw‑раздел (/data, dhcpcd, wifi, OTA) |
| `dev/`, `proc/`, `sys/` | виртуальные ФС |
| `tmp/`, `run/` | tmpfs |
| `var/` | log/cache и т.п. (симлинки на /tmp) |
| `tee/` | TEE‑хранилище |
| `opt/`, `root/`, `media/`, `mnt/` | пусты |
| `linuxrc → bin/busybox` | initramfs‑загрузчик |

---

## 3. `/bin` — базовые утилиты (busybox)

Почти всё — симлинки/апплеты `busybox`: `sh`, `ash`, `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `mknod`, `mktemp`, `date`, `dd`, `df`, `echo`, `grep`, `egrep`, `fgrep`, `sed`, `awk`, `tar`, `gzip/gunzip/zcat`, `hostname`, `kill`, `ln`, `login`, `mount`, `umount`, `mountpoint`, `netstat`, `ping`, `ps`, `pwd`, `run-parts`, `sleep`, `stty`, `su`, `sync`, `touch`, `true`, `uname`, `usleep`, `vi`, `watch`, `base64`, `cpio`, `dd`, `dmesg`, `nice`, `pidof`, `printenv`, `resume`, `setarch`, `setpriv`, `setserial`, `hwclock`(sbin)`.

Отдельно: `busybox` (мульти‑бинарь), `tee-supplicant` (OP‑TEE), `nuke`, `pipe_progress`, `linux32/64`, `fdflush`, `dumpkmap`.

---

## 4. `/sbin` — системные

- Загрузка/init: `init`, `switch_root`, `run-init`, `pivot_root`, `reboot`, `poweroff`, `halt`, `runlevel`.
- Устройства/ФС: `mdev`, `makedevs`, `mke2fs`, `mkdosfs`, `mkswap`, `mkswap`, `fdisk`, `fsck`, `blkid`, `losetup`, `fstrim`, `freeramdisk`, `hwclock`.
- Сеть: `ifconfig`, `ifup`, `ifdown`, `ip` (+ `ipaddr/iplink/iproute/iprule/ipneigh`), `route`, `arp`, `dhcpcd`, `udhcpc`, `iptunnel`, `tc`, `vconfig`, `ifconfig`.
- Модули/ядро: `modprobe`, `insmod`, `rmmod`, `lsmod`, `sysctl`, `devmem`.
- Сервисы: `start-stop-daemon`, `syslogd`, `klogd`, **`getty`**, **`getty_rabbit_hole`** (root‑getty только при `rh_unlock=1`), `watchdog`, `sulogin`, `nameif`.

---

## 5. `/lib` — библиотеки, модули, прошивки

- **glibc 2.30**: `ld-2.30.so` (+ `ld-linux-armhf.so.3`), `libc`, `libm`, `libpthread`, `libdl`, `librt`, `libutil`, `libresolv`, `libnss_*`, `libanl`, `libcrypt`.
- `libstdc++.so.6.0.28`, `libgcc_s`, `libatomic`, `libgomp`, `libgfortran`.
- **`libteec.so*`** — OP‑TEE client library.
- `firmware/`: `tas5805m.bin` (усилитель), `rtlbt/` (Realtek BT), `wcnmodem.bin`, `aw9610x_0.bin` (тач/GPIO), `NTP8910_Settings.c`.
- `modules/4.9.68/`: `extra/` (`aml_sdio.ko`, `sdio_bt.ko`, `vlsicomm.ko`, `optee.ko`+`optee/optee_armtz.ko`), `kernel/` (bluetooth, net, fs, sound, tee, **uwe5621**), `modules.*` (зависимости).
- `teetz/`, `dhcpcd/`.

> В прошивке есть драйверы и «Unisoc UWE5621», и «Realtek RTL8822CS»; фактически загружен **Realtek** (Wi‑Fi `rtl88x2cs` + BT `rtk_hciattach`).

---

## 6. `/usr` — пакеты

| Подпапка | Что |
|---|---|
| `bin/` | прикладные утилиты (см. ниже) |
| `sbin/` | `wpa_supplicant`, `unbound`, `i2c*`, `ubi*`, `flash_*`, `iptables`, `nand*`, `mtd_debug`, `rdate`, `crond`, `dnsd` |
| `lib/` | libasound, libbluetooth, libdbus, libgio/glib/gobject, libcrypto/libssl, libnl, libpcre, libprotobuf-nanopb, libsamplerate, libsbc, libsndfile, **libspandsp** (SIP), libtiff, libturbojpeg, libubootenv, libunbound, libxtables, libyaml, libz, `terminfo` |
| `share/` | `alsa`, `applications`, `dbus-1`, `dhcpcd`, `gettext`, `glib-2.0`, `locale`, `pixmaps`, `terminfo`, `udhcpc`, `unbound`, `xml` |
| `libexec/` | `bluetooth/bluetoothd` |

**`/usr/bin` (ключевое):**
- Аудио: `aplay`, `arecord`, `amixer`, `alsamixer`, `aserver`, `bluealsa`, `bluealsa-aplay`, `sndfile-resample`.
- BT: `bluetoothctl`, `bluemoon`, `bt-*`, `hciattach`, `rtk_hciattach`, `gatttool`, `btmon`, `sdptool`, `l2ping`, `rfcomm`, `a2dpconf`, `mpris-proxy`.
- ADB: `adbd`, `adb.sh`, `adb-keepalive.sh`.
- OTA/флеш: `apply_packed_ota` (`/usr/bin`), `ubi*`, `ubiformat`, `ubiupdatevol`, `flash_erase`, `flashcp`, `nanddump`, `nandwrite`, `mtd_debug`.
- Yandex: `yandex-apply-dtb-overlay`, `yandex-badblocks`, `yandex-btfwversion`, `yandex-chrony`, `yandex-get-localization`, `yandex-waitfile`, `yandex-wifichipmodel`, `yandex-wifireset`, `wifi_power`.
- Сервис: `keymaster_svc`, `chronyc`, `dbus-*`, `htop`, `lsof`, `strings`, `xxd`, `wget`, `telnet`, `tftp`, `hexdump`, `hexedit`, `od`, `xmlwf`, `pcre*`.

---

## 7. `/etc` — конфигурация (по файлам)

**Загрузка/система:**
- `inittab` — busybox init: `sysinit` mount'ы, `rcS`, serial‑getty через `getty_rabbit_hole`, `shutdown` → `rcK`.
- `init.d/` — `rcS`/`rcK` + скрипты `S00hostname` … `S99quasar` (25 шт., порядок ниже).
- `fstab` — таблица монтирования (см. §1).
- `mdev.conf` — правила `/dev` и `@modprobe $MODALIAS`.
- `modprobe.conf`, `fw_env.config` (U‑Boot env), `sysctl.conf` (через `S02sysctl`).
- `passwd`, `shadow`, `group`, `nsswitch.conf`, `hostname`, `hosts`, `issues`, `shells`, `profile`, `profile.d/`.
- `os-release` → `../usr/lib/os-release`, `mtab` → `/proc/self/mounts`.

**Сеть/DNS:**
- `dhcpcd.conf` — DHCP‑клиент; `wpa_supplicant.conf`, `wifi_ant_src.conf`.
- `resolv.conf` → `../tmp/resolv.conf` (dhcpcd пишет `nameserver 127.0.0.1` → unbound).
- `network/` — (пусто), `libnl/` — конфиг netlink.
- `unbound/` — конфиг DoT/DoH‑резолвера; `rw-dirs.d/unbound.conf` — tmpfs для `/etc/unbound`.

**Аудио/BT:**
- `asound.conf`, `alsa/conf.d/20-bluealsa.conf` (ALSA‑плагин bluealsa).
- `bluetooth/main.conf`, `bluetooth/w1/` (BT‑firmware `w1_bt_fw_uart.bin`, `aml_bt_rf.txt`, `a2dp_mode_cfg.txt`), `bluetooth/uwe5621/` (RF‑конфиги Marlin).
- `w1-settings-src/` — калибровка Wi‑Fi (aml RF).

**Прочее:**
- `chrony.conf` (NTP), `dbus-1/` (D‑Bus), `ssl/` (openssl.cnf, certs, private), `services`, `protocols`, `inputrc`.

**Порядок init (`S*`):**
`S00hostname → S01rw-dirs → S01syslogd → S01watchdog → S02klogd → S02sysctl → S10mdev → S20urandom → S30dbus → S39w1_wifi_ant_config → S40dhcpcd-db → S40net.lo → S40wifi → S41dhcpcd → S45tas58xx → S49chrony → S49teeinit → S50hci0 → S51bluetoothd → S52bluealsa → S53bluealsa-aplay → S54default-bluez-agent → S60touch_buttons_settings → S70unbound → S98pstore-clear → S99quasar`.

---

## 8. `/system` — Quasar (vendor)

`/system/vendor/quasar/` — весь голосовой/умный стек:
- **`maind`** (21.8 МБ) — «всё в одном»: tools (`--version`, `--full-info`, `--getprop`, `--wifi-info`, `--glagol-connections`, `--gst-launch`, `--nettest`, `--cli`) + daemons (`--platformd`, `--mediad`, `--telemetry`, `--fluent-bitd`, `--updatesd`).
- `quasar_launcher2` + `launch.json` — супервизор процессов.
- `q` — CLI‑обёртка; `run.sh`/`onboot.sh` — запуск и boot‑хук; `adb_options.inc`/`activate_adb.sh` — ADB; `device_ota_update.sh`/`ota_script.pub` — OTA.
- `quasar.cfg` (63 КБ) — 79 секций конфигурации; `VERSION`, `version_full`.
- `certs/ca-certificates.crt` — trust store (eMudhra внутри).
- `libs/` — `libyandex_evil` (VQE), `libquasar_gstreamer`, `libtflite`, `libglib`, `libavahi`.
- `spotter_models/`, `vqe_models/`, `bio_lingware/` — wake‑word, шумодав, биометрия.
- `ledpatterns/`, `ledconfigs/`, `sounds/` — LED и звуки.
- `matter/paa` — PAA‑сертификаты; `unbound/` — свой DNS.

---

## 9. `/data` (= `/bkupgrade`) — userdata (rw)

- `data/quasar/` — вся «правда»: `logs/`, `daemons_logs/`, `data/` (конфиг, токены, spotter‑модели, matter/zenoh lmdb, wifi.dat), `initialized`, маркеры `activate_adb_*`.
- `data/quasar/devices.json`, `account_storage.dat`, `user_config.dat`.
- `dhcpcd/`, `wifi/`, `ota/`, `uImage*` (OTA‑артефакты).
- `/bkupgrade` также хранит `update-info.json` и загрузки OTA.

---

## 10. `/var`

`cache → /tmp`, `lock → /tmp`, `log → /tmp`, `spool → /tmp`, `tmp → /tmp`, `run → /run`, `db/dhcpcd → /data/dhcpcd`, `lib/alsa`, `lib/chrony`, `lib/dbus → /tmp/dbus`, `lib/misc → /tmp`, `www` (www-data, пусто).

---

## 11. Остальное

- **`/dev`** — devtmpfs: `tty`, `ttyS0` (serial), `tee0/teepriv0`, `mtdblock*`, `ubi*`, `snd/*`, `input/*`.
- **`/proc`** — `cpuinfo`, `meminfo`, `cmdline`, `mounts`, `net/*` и т.д.
- **`/sys`** — `class/net/wlan0`, `class/leds`, `class/mtd`, `kernel/debug`, `fs/pstore`.
- **`/tmp`** — tmpfs, сюда пишут логи/сокеты; тут лежит `fastfetch`, `resolv.conf`, `dbus`.
- **`/run`** — `chrony/`, `dbus/`, `dhcpcd/`, `klogd.pid`, `mdev.pid`.
- **`/tee`** — TEE‑объекты (каталог‑хэш `1C1EFB8…`).
- **`/opt`, `/root`, `/media`, `/mnt`** — пусты.

---

## 12. Поток загрузки

```
U-Boot → kernel (mtd2/boot) → initramfs → switch_root(/dev/ubi0_0)
  → init (busybox) читает /etc/inittab
    → mount proc, mount -a (fstab), hostname
    → /etc/init.d/rcS
      → S00…S99 (syslogd, dbus, wifi, tas5825m, chrony, tee, hci0, bluetooth, unbound…)
      → S99quasar → run.sh → quasar_launcher2 launch.json
        → maind --platformd/--telemetry/--fluent-bitd/--mediad
        → onboot.sh: activate_adb.sh check → (маркеры) → adbd
```

---

## 13. fastfetch

- Пробовал официальные сборки **fastfetch 2.70** и **2.10.2** (armv7l): обе требуют **glibc ≥ 2.31/2.34**, а на устройстве **2.30** → `version 'GLIBC_2.34' not found`.
- Поэтому сделал **самодостаточный fastfetch‑скрипт** (`/data/local/tmp/fastfetch`, работает на busybox). Вывод:

```
  yandex-station-lite@yandex-station-lite
  OS          Buildroot 2020.02.1
  Kernel      4.9.68 (aarch64)
  Device      Yandex Station Micro (Станция Лайт)
  Firmware    0.369.1.50.4794655315.20261021.297
  Uptime      2:54
  Shell       busybox ash
  CPU         4 x Amlogic
  Memory      232MiB / 238MiB
  Disk /      64.8M (81% занято)
  IP          wlan0: 192.168.1.80
  Wi-Fi       [REDACTED-SSID]
  MAC         [REDACTED-MAC]
  Bluetooth   B8:87:6E:3F:99:3B
  ADB         root :5555
```

---

## 14. Шпаргалка

```bash
adb connect 192.168.1.80:5555
adb shell 'df -h; cat /proc/mounts'          # ФС
adb shell 'ls -la /bin /sbin /usr/bin'       # бинарники
adb shell 'cat /etc/inittab /etc/fstab'      # загрузка/монтирование
adb shell 'sh /data/local/tmp/fastfetch'     # fastfetch
adb pull /data/quasar/data ./data            # userdata
```
