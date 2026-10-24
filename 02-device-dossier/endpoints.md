# Эндпоинты Яндекс Станции Лайт (`yandexmicro`)

> Снято с прошивки `0.369.1.50.4794655315.20261021.297` (root ADB, read-only).
> «Слушает» — реально открытый сокет на момент снятия (`netstat`), «конфиг» — порт из `quasar.cfg`.

## 1. Наружу (доступно из LAN) — главное

| Порт | Протокол | Сервис | Что это |
|---|---|---|---|
| **5555** | TCP | `adbd` | **root-ADB без пароля** |
| **1961** | TCP (IPv6 `::`) | `glagold.externalPort` | glagol WebSocket (`WebSocket++/0.8.2`, TLS; на GET — `426 Upgrade Required`) — локальное управление колонкой |
| **7447** | TCP+UDP | Zenoh | IoT pub/sub (`devices.lmdb`) |
| **5081** | TCP | `pjsip` | SIP для звонков (`alice-ats`) |
| **5353** | UDP | mDNS/Avahi | анонс `_yandexio._tcp` → `YandexIOReceiver-<device_id>` |
| 11125 | UDP | `net_clock` | сетевые часы |

Итого «в мир»: **ADB, Glagol, Zenoh, SIP, mDNS**.

## 2. Внутренние TCP‑порты (только `127.0.0.1`) — реально слушают

| Порт | Сервис | Роль |
|---|---|---|
| 9875 | `aliced` | голосовой ассистент |
| 9877 | `wifid` | Wi‑Fi |
| 9878 | `authd` | OAuth/паспорт, токены |
| 9882 | `config_capability` | конфиг |
| 9884 | `firstrund` | первичная настройка |
| 9887 | `metricad` | метрики |
| 9895 | `monitord` | мониторинг/пингер |
| 9898 | `brickd` | режим подписки |
| 9899 | `glagold` (internal) | glagol внутри |
| 9903 | `iohub_services` | IoT‑шина |
| 9906 | `audioclient` | аудио‑клиент |
| 9908 | `update_health_check` | health OTA |
| 9910 | `iohub_clients` | IoT‑шина |
| 9911 | `ntpd` | время |
| 9912 | `setupd` | setup/секретные команды |
| 9913 | `ble_initd` | BLE‑настройка |
| 9917 | `networkd` | сеть |
| 9921 | `stereo_pair` | стереопара |
| 9924 | `backend` | backend‑прокси |
| 9926 | `network_stats` | статистика сети |
| 9850 | `yio_audio` | аудио |
| 11124 | `multiroomd` | мультирум |
| 53 | `unbound` | **свой DNS‑резолвер** (forwarders `77.88.8.x`) |
| 5037 | `adbd` | adb‑server |

## 3. Сконфигурированы, но не слушают (сейчас)

| Порт | Сервис | Почему |
|---|---|---|
| 9889 | `updatesd` | **вырезан из `launch.json`** (наш OTA‑блок) |
| 9891 | `external_commandsd` | не запущен |
| 9900 | `mediad` | сервис работает, но порт не забинден |
| 9904 | `metrica2d` | не запущен |
| 9907 | `notificationd` | не запущен |
| 9909 | `do_not_disturb` | не запущен |
| 9880 | `external` | не запущен |
| 9883 | `audioinit` | не слушает |
| 9922 | `volume_manager` | не слушает |
| 8080 | `firstrund.httpPort` | AP‑режим только при настройке |

## 4. Внешние эндпоинты (устройство → облако)

| URL | Назначение |
|---|---|
| `https://quasar.yandex.net` | основной backend (register, get_sync_info, glagol…), `backendUrl` |
| `wss://uniproxy.alice.yandex.net/uni.ws` | голосовой WebSocket Алисы |
| `wss://ws.api.music.yandex.net/quasar/websocket` | музыка/плеер |
| `https://rpc.alice.yandex.net` | RPC (`arpc_client`) |
| `https://oauth.yandex.ru` | токены |
| `https://login.yandex.ru` | логин |
| `https://mobileproxy.passport.yandex.net` | паспорт/код |
| `http://scbh.yandex.net/generate_204` | проверка интернета (captive) |
| `https://clck.yandex.net/quasar_metrics/write/batch` | метрики |
| `https://startup.mobile.yandex.net`, `https://startup.appmetrica.yango.com` | аналитика (AppMetrica) |
| `https://*.svc.cdn.yandex.net`, `https://quasar.s3.yandex.net` | CDN (spotter‑модели, звуки, OTA‑zip) |
| `*.yango.com` (yasmina) | региональный бренд |

## 5. Локальные UNIX‑сокеты / устройства

- `/dev/keymaster_svc`, `/dev/tee0`, `/dev/teepriv0` — TEE/keymaster.
- `/run/dbus/system_bus_socket` — D-Bus (bluez и др.).
- `/dev/wpa_supplicant` — wpa_supplicant control.
- `/tmp/...` — внутренние IPC‑сокеты Quasar.

## 6. Замечания

- Практически все внутренние сервисы слушают только `127.0.0.1` — снаружи они недоступны, их API «звенит» через `backend`/`iohub`.
- `1961` и `7447` — самые интересные для исследования: glagol‑WebSocket и Zenoh.
- `5353`/mDNS анонсирует `_yandexio._tcp`, но по нему видно только идентификатор устройства.
- `5555` — единственный «прямой» вход в root; рекомендуется держать только в доверенной сети.
