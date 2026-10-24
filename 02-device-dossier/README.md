# Яндекс Станция Лайт (`yandexmicro`) — техническое досье

> Полное обследование устройства через root ADB. Всё — на своём устройстве и в своей сети.
> Прошивка на момент обследования: `0.369.1.50.4794655315.20261021.297` (Quasar `VERSION 3.21`,
> Software Revision `ce2b8fc257cdde42a035aeea04e75e9350b35781`).

---

## 1. Как устроено в двух словах

- **Железо:** SoC Amlogic AXG (A113X), 4×Cortex-A53, ~238 МБ RAM, NAND-флеш, Realtek RTL88x2CS (Wi‑Fi 11ac + BT), усилитель TAS5825M, ёмкостные сенсорные кнопки Cypress `cy8cmbr3`, OP‑TEE.
- **ОС:** Buildroot 2020.02.1, ядро 4.9.68, **32-битный userland на 64-битном ядре**, busybox 1.31.1, sysv‑init + `/etc/init.d/S*`.
- **Софт:** демон `maind` (21.8 МБ, мульти‑инструмент: 14 «tools» + 6 «daemons»), `quasar_launcher2`, десятки внутренних сервисов (≈30 портов на loopback), glagol‑WebSocket, Matter/Zenoh, SIP‑звонки, OTA.
- **Root:** сетевой `adbd` на `:5555` без пароля, поднят маркерами в `/data/quasar/` и обёрткой `activate_adb.sh`.

---

## 2. Как выгружать файлы с устройства

Так как у нас root‑ADB, основной способ — **`adb pull`** (работает на любой файл, читает от root).

```bash
# один файл
adb -s 192.168.1.80:5555 pull /system/vendor/quasar/onboot.sh ./onboot.sh

# каталог целиком
adb -s 192.168.1.80:5555 pull /system/vendor/quasar/ledpatterns ./ledpatterns

# конфиг и состояние
adb -s 192.168.1.80:5555 pull /data/quasar/data/user_config.dat ./user_config.dat
adb -s 192.168.1.80:5555 pull /data/quasar/daemons_logs/maind.log ./maind.log
```

Особенности:

- **Всё читается** — файлы `root`-овые, но `adbd` у нас от root, поэтому `pull` берёт любой путь (в т.ч. `/system` и `/data`).
- **Обратно — `adb push`** (нужен для записи; `/` сейчас `ro`, но UBIFS легко ремаунтится: `mount -o remount,rw /` — правда на UBIFS иногда `EBUSY`, тогда писать через staging + `mv`).
- **Альтернативы:** `dd`/`tar` + `adb pull` из `/tmp` (ram‑disk), `socat`/`nc` (есть `nc`/`telnet`/`wget`), но `adb pull` проще всего.
- **Что выгружено:** `~/алиса/dump/` — `quasar/` (скрипты/конфиги), `libs/` (ELF‑библиотеки), `logs/` (логи демонов), `state/` (persisted‑состояние), `media/` (LED/звуки).

---

## 3. Железо

| Компонент | Что найдено |
|---|---|
| SoC | Amlogic AXG (A113X), device‑tree `Yandex Station Micro`, `amlogic,axg` |
| CPU | 4×Cortex‑A53 (part `0xd03`), ядро aarch64, userland 32‑бит (`arm64-v8a,armeabi-v7a`) |
| RAM | `MemTotal: 243960 kB` (~238 MiB) |
| Flash | NAND, 128 КБ eraseblock, 7 MTD‑разделов + 2 UBI |
| Wi‑Fi | **Realtek RTL88x2CS** (`rtl88x2cs v5.14.0.2`, BT‑Coex `COEX20211210-2727`) |
| Bluetooth | Realtek, H5 over UART (`rtk_hciattach -s 115200 ttyS1 rtk_h5`), MAC `B8:87:6E:3F:99:3B` |
| Аудио‑кодек/усилитель | ALSA card `AMLAUGESOUND`, `TDM-B-tas5825m-amplifier` (TAS5825M) |
| Кнопки | Cypress `cy8cmbr3` (CapSense), `irq/33-cy8cmbr3` |
| TEE | OP‑TEE: `/dev/tee0`, `/dev/teepriv0`, `tee-supplicant`, `keymaster_svc` |
| Серийник | `[REDACTED-DEVICE-ID]` (он же device_id) |

Wi‑Fi/BT: MAC из efuse (`mac_bt` offset 6). Регион/локаль: `COUNTRY_RU`, `ru-RU`.

---

## 4. Flash, разделы и U‑Boot

**MTD:**

| mtd | имя | что это |
|---|---|---|
| 0 | bootloader | U‑Boot |
| 1 | tpl | TPL (SPL) |
| 2 | boot | ядро |
| 3 | system | rootfs → UBI `ubi0:rootfs` (UBIFS, 72.1 MiB, смонтирован `ro`) |
| 4 | nv | nvdata → `/tee` (vfat), хранилище TEE |
| 5 | bkupgrade | UBI `ubi1` (101.7 MiB) → `/data` (UBIFS, `rw`) |
| 6 | recovery | recovery |

**U‑Boot env (`fw_printenv`, читается/пишется из userspace):**
`Board_id=9`, `aml_dt=axg_micro_default`, `boot_to_recovery=0`, `rabbit_hole_debug=0`,
`bootcmd`/`preboot`/`storeboot`/`switch_bootmode`, `recovery_part=recovery`, `upgrade_step=2`.
`cmdline_keys` через `keyman` читает из защищённой памяти `deviceid`, `mac`, `localization`.

**«Rabbit hole»:** `/sbin/getty_rabbit_hole` запускает root‑getty на serial **только** если в cmdline есть `androidboot.rh_unlock=1` (U‑Boot выставляет его из `rabbit_hole_debug=1`). Иначе `exec sleep infinity`. Это заводской сервисный доступ по UART.

---

## 5. ОС и автозагрузка

- `init` (busybox) → `/etc/inittab` → `/etc/init.d/rcS` → `S*`‑скрипты.
- Ключевые init‑скрипты: `S30dbus`, `S40wifi` (`wpa_supplicant`), `S41dhcpcd`, `S45tas58xx` (инициализация усилителя), `S49chrony`, `S49teeinit`, `S50hci0` (BT), `S51bluetoothd`, `S52bluealsa`, `S53bluealsa-aplay`, `S70unbound`, `S99quasar`.
- `S99quasar` → `run.sh` → `quasar_launcher2 launch.json` (список задач) → `maind`‑демоны.
- `onboot.sh` (вызывается quasаром) кладёт `overcommit_memory=1`, чистит OTA‑артефакты, ставит `LD_LIBRARY_PATH`/`GST_PLUGIN_PATH`, вызывает `activate_adb.sh check`, `set_monotonic_time.sh`, `yio_iptables_init.sh`, `run.sh`.

---

## 6. Инвентарь бинарников (самое интересное)

**`/system/vendor/quasar/`:**
`maind` (21.8 МБ; симлинки `led_util`, `metric_collector`, `keymaster_proxy_app`, `quasar_client`, `tcp_alsa_writer` — это один и тот же бинарь с разными argv[0]), `quasar_launcher2`, `q` (CLI‑обёртка), `run.sh`, `onboot.sh`, `activate_adb.sh` + `adb_options.inc`, `device_ota_update.sh`, `ota_script.pub`, `quasar.cfg` (63 КБ, 79 секций), `ca-certificates.crt` (trust store), `vqe_models`, `bio_lingware`, `matter/paa` (сертификаты), `spotter_models`, `ledpatterns`, `ledconfigs`, `sounds`, `unbound`, `libs`.

**`/usr/bin` (ключевое):**
- Аудио: `aplay`, `arecord`, `amixer`, `alsamixer`, `aserver`, `bluealsa`, `bluealsa-aplay`, `sndfile-resample`.
- BT: `bluetoothctl`, `bluemoon`, `bt-*`, `hciattach`, `rtk_hciattach`, `gatttool`, `btmon`, `sdptool`, `l2ping`, `rfcomm`, `a2dpconf`, `mpris-proxy`.
- ADB: `adbd`, `adb.sh`, `adb-keepalive.sh`.
- OTA/флеш: `apply_packed_ota`, `ubi*`, `ubiformat`, `ubiupdatevol`, `flash_erase`, `flashcp`, `nanddump`, `nandwrite`, `mtd_debug`.
- Yandex: `yandex-apply-dtb-overlay`, `yandex-badblocks`, `yandex-btfwversion`, `yandex-chrony`, `yandex-get-localization`, `yandex-waitfile`, `yandex-wifichipmodel`, `yandex-wifireset`, `wifi_power`.
- Прочее: `keymaster_svc`, `dbus-*`, `chronyc`, `htop`, `lsof`, `strings`, `xxd`, `wget`, `telnet`, `tftp`.

**`/sbin`:** `init`, `start-stop-daemon`, `udhcpc`, `dhcpcd`, `syslogd`, `klogd`, `watchdog`, `getty_rabbit_hole`, `fw_printenv`/`fw_setenv`.
**`/usr/sbin`:** `unbound`, `wpa_supplicant`/`wpa_cli`, `dnsd`, `crond`, `i2c*`, `ubi*`.

---

## 7. Архитектура Quasar

`maind` — единый бинарь с двумя режимами:

**Tools (интроспекция/утилиты):**
`--version`, `--build-timestamp`, `--device-id`, `--device-localization`, `--getprop`, `--full-info`,
`--glagol-connections`, `--wifi-info`, `--nettest URL RATE`, `--gst-launch <pipeline>`,
`--set-dev-backend-flag` / `--remove-dev-backend-flag`, `--save-last-monotonic-time`, `--cli`.

**Daemons (постоянно работающие):**
`--platformd`, `--mediad`, `--telemetry`, `--fluent-bitd` (в нашем случае `--updatesd` **вырезан** из `launch.json`).

**`q` — обёртка** (`q start|stop|restart|version|device-id|wifi-info|glagol-connections|full-info|backend-dev|backend-prod|cli|getprop`).

**`quasar.cfg` — 79 секций**, в т.ч.: `adbd`, `backend`, `authd`, `glagold`, `mediad`, `updatesd`,
`aliced`, `audiosender`, `audiod`, `audioinit`, `smart_volume`, `equalizer_controller`, `leds`,
`led_capability`, `bluetooth`, `ble_initd`, `wifid`, `networkd`, `setupd`, `firstrund`,
`matter`, `iot`, `iot_scenarios`, `zenoh`, `phone_calls`, `multiroomd`, `stereo_pair`,
`monitord`, `telemetry`, `metricad`, `updatesd`, `update_health_check`, `chrony`, `ntpd`,
`unbound`‑настройки и др.

---

## 8. Функционал по подсистемам

### 8.1. Голос / Алиса

- **Wake‑word (spotter):** модели `activation/alisa` (слово «алиса»), `activation/yandex` («яндекс»),
  плюс `activation/yasmina` (ar‑SA, из профиля), `command` (команды), `counteractivation` (анти‑ложные
  срабатывания), `vad` (детектор речи), `spotterRecognizer` (tflite).
- **`aliced`:** apiKey `51ae06cc-...`, app_id `aliced`; каналы аудио `raw_mic_0..3`, `raw_spk_0..1`,
  `vqe_0`, `vqe_bnr`; история 10 с.
- **VQE (`libyandex_evil.so`):** лучеформирование, AEC, шумодав, `SmartEqualizer`, `RoomCorrection`,
  **ультразвуковой детектор/сонар** (`UltrasoundDetector`, `UltrasoundSonar`) — для presence‑детекции.
- **Биометрия (`bio_lingware`):** классификаторы пол/возраст, ECAPA‑TDNN (speaker embedding) —
  «голосовой профиль».
- **Транспорт:** `glagold` — WebSocket‑клиент к uniproxy (`wss://…alice.yandex.net`), сервер на `1961`.
- **Локальный текстовый ввод:** `maind --cli` → `q <текст>` отправляет text‑query в Алису.

### 8.2. Аудио и музыка

- ALSA: card `AMLAUGESOUND`, усилитель `TAS5825M` (controls `TAS5805M *`, `Master`, `PDM`).
- Воспроизведение через **GStreamer**: `souphttpsrc → decodebin → 48000/2/S16LE → volume → equalizer → alsasink`
  (`mediad.playbackParams.gstPipeline`), с `opt_aes_decoding` (шифрованный поток).
- Музыка: `mediad.apiUrl = wss://ws.api.music.yandex.net/quasar/websocket`, `ResolverCache` для `storage.mds.yandex.net`.
- `smart_volume` (адаптивная громкость), `equalizer_controller`, `volume_manager`.
- Системные звуки — `.opus` в `sounds/common` (16) и `sounds/ru-RU` (20): `configure_success`, `no_internet`, `brick`, `wrong_sound`, и т.п.

### 8.3. LED

- `ledpatterns/*.led` — текстовые анимации: `loop`/`gammacorrection`, затем кадры
  `RRGGBB RRGGBB RRGGBB <длительность_ms>` (3 зоны кольца).
- `ledconfigs/*.json` — цветокорректирующая матрица 3×3 (компенсация цвета RGB‑светодиода).
- Управление — через `device_state_handler` (симлинк `led_util → maind`), паттерны: `alice_listening/speaking/thinking`, `call_*`, `bluetooth_*`, `player_*`, `update_applying`, `volume`, `error`, `timer`.

### 8.4. Bluetooth

- Стек: `rtk_hciattach` (H5, ttyS1) → `bluetoothd` → `bluealsa` (`a2dp-sink`, `a2dp-source`, `hfp-ag`) + `bluealsa-aplay` + `just-works-bluez-agent`.
- Имя: `Яндекс Лайт`; prefix `Yandex Station Lite `.
- Сценарии: A2DP‑плеер (колонка как BT‑колонка), HFP (handsfree), pairing‑агент.
- Известные устройства: `/data/quasar/data/bt_known_devices.dat`.

### 8.5. Сеть и DNS

- `wpa_supplicant` + `dhcpcd` на `wlan0`; хранится **1** Wi‑Fi‑сеть (`maxStoredWifiNetworks: 1`).
- **Собственный DNS‑резолвер `unbound`** на `127.0.0.1:53`, forwarders: `77.88.8.1/8/88/2` (Yandex DNS) + `192.168.1.254` + `fe80::1%wlan0`.
  Именно поэтому устройство не всегда слушается DHCP‑DNS — и гайду нужен был DNAT.
- Проверка интернета: `generate_204` на `scbh.yandex.net` (и Google в конфиге).
- `DnsFallbackMap`: `quasar.yandex.net → 213.180.193.230` — жёсткий fallback.

### 8.6. Matter / IoT / Zenoh

- **Matter:** `matter/paa/` — PAA‑сертификаты (Google, Tuya, TP‑Link, и др.), `chip.lmdb`, `devices.lmdb`,
  `ota.lmdb`; commissioning через BT; `enableSystemDiscovery`.
- **Zenoh:** `zenoh` (pub/sub IoT), слушает `0.0.0.0:7447`, `devices.lmdb`.
- `iot.providers`: `Matter: true`, `WiFi: true` (в конфиге профиля — `Zenoh: true`).
- `iot_scenarios.lmdb`, `syncEndpoints`.

### 8.7. Звонки

- `phone_calls` на **pjsip**: SIP `5081`, `sip_use_tcp/tls`, opus/48000, SRTP, `ats_manager` = Alice Telephony Service (`alice-ats.yandex.net`).
- `stored_phone_calls_accounts` (45 КБ) в `/data/quasar/data`.
- Директива `calls_*` в `sounds` и `call_*` LED‑паттерны.

### 8.8. OTA / обновления

- `updatesd`: порт `9889`, `applyUpdateScript = device_ota_update.sh`, `otaScriptPublicKey = ota_script.pub`,
  `updatesDir = /bkupgrade`, `updatesExt = .img`, `update-info.json`.
- Поток: `get_sync_info` → `hasCriticalUpdate` → `check_updates` → скачать `.img` → `device_ota_update.sh` → `apply_packed_ota` → reboot.
- **Мы это нейтрализовали:** `updatesd` вырезан из `launch.json`, `device_ota_update.sh` → `exit 0`, `ota_script.pub` подменён.

### 8.9. Первичная настройка (setup)

- `setupd` (порт `9912`) + `firstrund` + `ble_initd` (BLE GATT: сервис конфигурации с
  characteristics `deviceId`, `wifiList`, `token`, `connect`, `status`).
- **`secretMsgList`** — «секретные» команды: среди них
  **`activate_adb.sh --sound activate`** (активация ADB по звуку!), `fw_setenv factory_mode 0/1/2`,
  `qc_leds_test`, `qc_buttons_test`, `qc_sweep_tone`, `qc_bt_discoverable_on`, `qc_send_version_to_backend`.
- Индикатор процесса — BLE‑notify `status` (коды 102/103/105/107/109).

### 8.10. ADB

- `activate_adb.sh` + `adb_options.inc`: маркеры `/data/quasar/activate_adb_{sound,quasmodrom,glagol}` и
  `/data/quasar/activate_network_adb`.
- Наш конфиг‑триггер: `quasmodromNetworkActivateCmd = activate_adb.sh --quasmodrom activate --network`.
- `onboot.sh` на старте: `activate_adb.sh check` → если есть маркеры → `start-stop-daemon -S -b -x adbd`.
- `adbd` на `0.0.0.0:5555`, **без пароля**.

### 8.11. TEE / keymaster

- OP‑TEE: `tee-supplicant` + `/dev/tee0`, `keymaster_svc`, `/dev/keymaster_svc` (unix socket).
- `/tee` (mtd4, vfat) — TEE‑хранилище (каталог‑хэш `1C1EFB8EE5372643A5D68C33726C7D57`).
- Через keymaster читаются `deviceid`, `mac`, `localization` (видно в U‑Boot `cmdline_keys`).

---

## 9. Локальные интерфейсы

**Наружу (0.0.0.0/::), т.е. доступно из LAN:**

| Порт | Что |
|---|---|
| `5555` | `adbd` (root, без аутентификации) |
| `1961` | glagol WebSocket (`WebSocket++/0.8.2`, TLS, ответ на GET — `426 Upgrade Required`) |
| `7447` | Zenoh (IoT pub/sub) |
| `5081` | SIP (pjsip) |

**Только loopback (127.0.0.1):** ~30 портов сервисов Quasar (`9875`…`9926`, `9895` monitord, `9877` wifid,
`9878` authd, `9899` glagold, `9900` mediad, `9899`, `9912` setupd, `9913` ble_initd, `9908` update_health_check, `53` unbound и др.).

**mDNS:** `_yandexio._tcp` → `YandexIOReceiver-<device_id>`; также `_http._tcp` не найден.
**glagol:** TLS с самоподписанным сертификатом `CN=localhost, O=Yandex`; сертификат и приватный ключ
лежат в `/data/quasar/devices.json` (значит, локальный API технически «прозрачен» для того, у кого есть этот файл).

---

## 10. Что лежит в состоянии (и что там чувствительного)

`/data/quasar/data/`:
- `user_config.dat` — **полный конфиг** от бэкенда: `account_config`, `device_config` (имя «Яндекс Лайт»,
  `locale ru-RU`, `standby 240 мин`), `system_config` (эксперименты, `testids`, `quasmodrom_group=production`),
  `passport_uid: [REDACTED-UID]`.
- `account_storage.dat` — токены `xtoken`/`authToken` (вида `y0_[REDACTED]`).
- `wifi.dat` — **Wi‑Fi SSID и пароль в открытом виде**.
- `devices.json` — glagol‑сертификат + приватный ключ, `tokensStorage`.
- `subscription_mode.dat` (`{"mode":"transaction"}`), `last_vendor_volume`, `is_speaker_muted`,
  `spotter.json`, `spotter_model/`, `bt_known_devices.dat`, `stored_phone_calls_accounts`,
  `matter/`, `zenoh/`, `iot_scenarios.lmdb`, `capability_states.lmdb`, `metrica/`, `adhans/`.

`/system/vendor/quasar/`:
- `certs/ca-certificates.crt` — trust store (240 КБ) с eMudhra/emSign — на нём и держится вся техника.
- `ota_script.pub`, `platformKey.h.sha256`.
- `config`: `authd` хранит **OAuth client id/secret** (`authTokenClientId/Secret`, `xTokenClientId/Secret`),
  URL `oauth.yandex.ru`, `login.yandex.ru`, `mobileproxy.passport.yandex.net`; `deviceName: «Яндекс.Станция Лайт»`.

**Логи:** `/data/quasar/daemons_logs/{maind,mediad,updatesd,wifid,yiod,telemetry,fluent-bitd,chip}.log`.
В `yiod.log` виден весь первичный setup, включая ответ бэкенда `{"hasCriticalUpdate":true,"status":"ok"}`
и `get_sync_info` → `429 limited` (бэкенд сам режет частоту).

---

## 11. Наблюдения по безопасности

- **ADB `5555` без аутентификации** — любой в LAN получает root. Держать только в доверенной сети.
- **glagol `1961`** — LAN‑API управления колонкой по TLS; сертификат/ключ сервера лежат на диске
  (`devices.json`), т.е. это не секрет. Фактически это ещё один локальный канал управления.
- **Zenoh `7447`** — открытый IoT‑протокол без видимой изоляции.
- **«Активация ADB по звуку»** в `setupd.secretMsgList` — заводской механизм (включить ADB спец‑звуком),
  защищён hash'ем команды. Плюс `fw_setenv factory_mode` — переключение заводских режимов.
- **Rabbit hole** — root‑getty на serial включается флагом U‑Boot (нужен физический доступ/UART).
- Wi‑Fi‑пароль и OAuth‑секреты хранятся в открытом виде на устройстве.
- Имя модели: в DT — `Yandex Station Micro`, но в `authd.deviceName` и BT — **«Яндекс Станция Лайт»**.

---

## 12. Быстрые команды для повторного обследования

```bash
# подключиться
adb connect <IP>:5555 && adb shell id

# интроспекция
/system/vendor/quasar/q full-info
/system/vendor/quasar/q getprop
/system/vendor/quasar/q wifi-info
/system/vendor/quasar/q glagol-connections
/system/vendor/quasar/q cli          # REPL: s-старт диалога, q-текстовый запрос, p-пауза…

# выгрузить всё важное
adb pull /system/vendor/quasar/quasar.cfg ./quasar.cfg
adb pull /data/quasar/data ./data
adb pull /data/quasar/daemons_logs ./logs

# порты / сеть
netstat -ltn
cat /etc/resolv.conf; cat /etc/unbound/*.conf
```
