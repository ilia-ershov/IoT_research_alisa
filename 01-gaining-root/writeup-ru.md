# Root на Яндекс Станции Лайт (`yandexmicro`) — полный writeup

> **Итог:** `adb shell id` → `uid=0(root) gid=0(root)` на прошивке
> `0.369.1.50.4794655315.20261021.297`. Root закреплён (fortress + OTA-off) и
> переживает перезагрузку без стенда, без подмены DNS и после смены Wi-Fi-сети.
>
> **Метод:** eQuasar — подмена бэкенда Quasar на своём сервере с сертификатом,
> выпущенным на утёкшем наборе eMudhra/emSign. В ответе конфига колонке говорится
> «включи ADB», колонка сама поднимает сетевой `adbd` от root.

---

## 1. TL;DR

1. Подняли локальный nginx-стенд, который по DNS забирает на себя `quasar.yandex.net`/`.ru`, `scbh.yandex.net`.
2. В `/get_sync_info` стенд отдаёт конфиг с `adbd.remoteActivation=true` + `fullDurationMs`, в `/check_updates` — контроль обновлений.
3. Колонка (Станция Лайт) прошла регистрацию через стенд, приняла eMudhra-сертификат, получила конфиг и записала маркеры ADB в `/data/quasar/`.
4. Получили `adb` root, затем закрепили доступ (fortress + отключение OTA в три слоя).
5. Проверили, что root живёт автономно (без стенда и DNS-подмены) и после смены сети.

Ключевой неочевидный момент: **заводская прошивка Лайт (`0.1.1.6`, июль 2021) слишком старая и не умеет активироваться** — пришлось сначала дать ей одно OTA-обновление до `.46`, и только потом активация дошла до `/get_sync_info`.

---

## 2. Что было целью

Получить root ADB на **Яндекс Станции Лайт** (платформа `yandexmicro`) в своей сети, закрепить его и убедиться, что он не отвалится:

- при перезагрузке колонки,
- после того, как стенд и подмена DNS будут убраны,
- после переезда колонки в другую Wi-Fi-сеть.

Всё — только на собственном устройстве и в собственной сети, без прошивки чужих boot.img.

---

## 3. Исходная картина (разведка)

| Объект | Адрес/значение |
|---|---|
| MacBook | macOS 15.8.1, сначала `192.168.50.218` (en0), позже `192.168.1.79` |
| Роутер | OpenWrt `25.12.6` (mediatek/filogic), LAN `192.168.50.1`, WAN `192.168.1.101`, upstream `192.168.1.254` |
| Колонка | hostname `yandex-micro`, MAC `[REDACTED-MAC]`, сначала `192.168.50.163`, позже `192.168.1.80` |
| Сертификат стенда | `CN=quasar.yandex.net`, issuer `EM OV TLS CA - G3C` (eMudhra), до `22.01.2029` |

Важные находки на старте:

- Устройство — **`yandexmicro` (Станция Лайт)**, а не `yandexmini_2` (Мини 2), под который написан классический гайд и на котором «официально» проверен eQuasar. Это был главный риск всей операции.
- Роутер был **уже частично настроен** предыдущей попыткой:
  - DNAT-правило `force-station-dns` (перекидывало DNS колонки на роутер),
  - `local=/quasar.yandex.../` в `/etc/dnsmasq.conf` (гасили Quasar в NXDOMAIN — это **не** то, что нужно),
  - мусорные DHCP-резервации `yandexmini2`/`infosec` с IP из чужой подсети `192.168.1.x`,
  - неактивный static-route `0.0.0.0/0 via 192.168.50.223`.
- В песочнице, где работает агент, **заблокирован `sudo`**, нет docker и nginx, а `brew` не может писать в `/opt/homebrew`.

---

## 4. Инструменты и артефакты

- **eQuasar** (`git.gay/iwakura/eQuasar`) — из него взяты сертификаты и опорный nginx-конфиг.
  - `copymetoroot/opt/fakequasar/certs/fullchain.pem` — цепочка: leaf `quasar.yandex.net` + `EM OV TLS CA - G3C`.
  - `copymetoroot/opt/fakequasar/certs/quasar-all.key` — RSA-ключ (2048).
- **Форк `hu553in/yandex-station-root`** — `persistence.py`: безопасное закрепление root по ADB (fortress + отключение OTA в launch.json).
- На Mac: `adb`, `curl`, `dig`, `openssl`, `nginx` (brew), Python 3.12 + `paramiko` (для SSH к роутеру без pty).

---

## 5. Полная хронология (с провалами и тем, как их чинили)

### 5.1. Разведка и доступ к роутеру

- **Провал №1 — `expect` не смог выделить pty.** Первая попытка ходить на роутер через `expect` (парольный SSH) упала с `The system has no more ptys`.
  - **Решение:** перешли на Python `paramiko` (SSH-канал напрямую, без pty). Написали хелперы `rssh.py` (команда одной строкой) и `rrun.py` (загрузка скрипта по SFTP и запуск).

- Увидели, что роутер — это OpenWrt, а не «чужой» ASUS (адрес `192.168.50.1` нестандартный для OpenWrt, но это он и есть).

### 5.2. Стенд nginx на Mac

- **Провал №2 — в песочнице нельзя `sudo`, нет docker, `brew install nginx` не пишет в `/opt/homebrew`** (`Operation not permitted`).
  - **Решение:** готовый root-скрипт `stand-setup.sh`, который запускает уже **пользователь** на Mac от root (`sudo bash stand-setup.sh`). Агент подготовил всё: сертификаты, конфиг, самопроверку.

- Скачали сертификаты eQuasar напрямую через Gitea API (полный `git clone` с git.gay вис и был убит как ненужный).

- Сертификат проверен:
  ```
  subject=CN=quasar.yandex.net
  issuer=EM OV TLS CA - G3C (eMudhra)
  notAfter=Jan 22 2029
  SAN: quasar.yandex.net, *.quasar.yandex.net, scbh.yandex.net,
       rpc.alice.yandex.net, uniproxy.alice.yandex.net, strm.yandex.ru, ...
  ```

- Взяли **финальную** версию конфига из гайда (в репозитории eQuasar конфиг «сырой»: без `fullDurationMs`, без второго пути `adbd`, без `resolver`). Итоговый `/get_sync_info` отдаёт `adbd` в **двух** местах (`config.adbd` и `config.system_config.adbd`) с `fullDurationMs=31536000000`, а в проксирующем `location /` стоит `resolver 8.8.8.8 1.1.1.1` (иначе все проксируемые запросы → 502).

- **Провал №3 — первая самопроверка дала «Empty reply from server».** Испугались, что стенд сломан.
  - **Диагноз:** nginx в этот момент ещё перезапускался (скрипт делает `nginx -s stop; nginx`), плюс один «пустой» запрос от `nc`-пробы залогировался как `400`.
  - **Решение:** просто подождали и перепроверили — всё заработало (`/get_sync_info` → 200/307 байт, `/check_updates` → `{"hasUpdate":false}`, `/generate_204` → 204, `/` → 404 от настоящего Quasar через прокси).

### 5.3. Роутер: DNS, DNAT, чистка мусора

- **Исправили** `local=` → `address=`:
  ```
  address=/quasar.yandex.net/192.168.50.218
  address=/quasar.yandex.ru/192.168.50.218
  address=/scbh.yandex.net/192.168.50.218
  address=/strm.yandex.ru/127.0.0.1
  address=/strm.yandex.net/127.0.0.1
  address=/rpc.alice.yandex.net/127.0.0.1
  address=/uniproxy.alice.yandex.net/127.0.0.1
  address=/alice.yandex.net/127.0.0.1
  address=/alice-ats.yandex.net/127.0.0.1
  address=/alice-ats-test.yandex.net/127.0.0.1
  ```
- По просьбе пользователя **выключили DNAT** `force-station-dns` (`enabled=0`), т.к. роутер подключили по WAN-кабелю.
- Удалили мусорные резервации `yandexmini2`/`infosec` (чужая подсеть).
- Проверили: `nslookup quasar.yandex.net` → `192.168.50.218`, `strm.yandex.net` → `127.0.0.1`.

### 5.4. Сброс и настройка колонки — первый «ступор»

Колонку сбросили и настроили через приложение «Дом с Алисой». В логе стенда появилось:

```
POST /register?...&platform=yandexmicro&firmware=0.1.1.6...factory  -> 200 (51 байт)
GET  /check_updates?...&platform=yandexmicro                        -> 200 (19 байт)
```

**Это был первый большой успех и одновременно провал:**

- ✅ Сертификат eMudhra **принят** (register прошёл по TLS → 200). Значит, способ работает и на `yandexmicro`.
- ❌ Но `GET /get_sync_info` **не приходил**. Колонка застряла: раз в ~90 секунд опрашивала `/check_updates` и ничего больше.

### 5.5. Диагностика «почему нет /get_sync_info»

Сначала пошли по ложному следу:

- В conntrack увидели у колонки прямое TLS-соединение с `87.250.251.227:443` и заподозрили «жёстко прописанный IP» для обхода DNS.
- **Разоблачение:** сервер на `87.250.251.227` отдаёт сертификат `*.oauth.yandex.ru` — это обычный Yandex OAuth (обмен токенов), а не канал конфига. Мы его и не должны перехватывать. Ложная тревога.

Настоящая причина: смотрим на версию в запросах — `0.1.1.6...factory` (июль **2021**). Заводская прошивка настолько старая, что **не умеет завершать активацию** (не вызывает `/get_sync_info`), а крутит `/check_updates`, ожидая обновление. Наш же щит (`hasUpdate:false`) сам держал её в этом цикле.

Вывод совпал с известным поведением из форка eQuasar: «заводской восстановлению нужно одно OTA-обновление до `.46` до завершения активации».

### 5.6. Решение: дать ОДНО обновление до `.46`

- Взяли метаданные версии `yandexmicro` `0.369.1.46.4778262442.20261013.297` (13.10.2026) — это последняя известная версия, которая ещё принимает eMudhra-цепочку (в свежих `.50`/`.372` её выпилили).
- Переключили `/check_updates` с `{"hasUpdate":false}` на полноценный offer:
  ```json
  {"hasUpdate":true,"version":"0.369.1.46.4778262442.20261013.297",
   "downloadUrl":"https://cdn...svc.cdn.yandex.net/yandexmicro/ota/user/.../0.369.1.46....zip",
   "crc32":371630625,"critical":true,
   "fallbackUrl":"https://quasar.s3.yandex.net/yandexmicro/ota/user/...",
   "fallbackIp":"93.158.134.158","updateId":"150484"}
  ```
- Колонка забрала offer (ответ 452 байта вместо 19), скачала `update.zip` с CDN Яндекса (в conntrack видно ~67 МБ и рост), установила и перезагрузилась.

### 5.7. Root получен

После обновления колонка прошла активацию на `.46`, и в логе наконец появилось главное:

```
GET /get_sync_info?device_id=...&platform=yandexmicro&version=0.369.1.46...  -> 200 (307 байт)
```

Затем:

```
adb connect 192.168.50.163:5555
adb shell id   -> uid=0(root) gid=0(root)
```

Маркеры в `/data/quasar/`: `activate_adb_quasmodrom`, `activate_network_adb`.

Нюанс: колонка **сама докатилась с `.46` до `.50`** (updatesd обходит DNS по прямым IP), но маркеры в `/data` пережили смену системного раздела — root сработал уже на `.50`. Это ровно тот сценарий, который описан в гайде.

### 5.8. Закрепление root — два новых провала

Закрепление делали скриптом `persistence.py` из форка hu553in (это и есть fortress + ota-off, безопасно, с проверкой форматов и бэкапами).

- **Провал №4 — `install-adb` упал на `mktemp`.** На `yandexmicro` нет пути `/data/local/tmp` (инструмент писался под mini_2, где он есть).
  - **Решение:** `adb shell mkdir -p /data/local/tmp`, повтор.

- **Провал №5 — `disable-updates` упал на remount:** `mount: mounting ubi0:rootfs on / failed: Device or resource busy`.
  - **Диагноз:** устройство на UBIFS, `/` уже смонтирован `rw`; remount для UBIFS даёт EBUSY. При этом сам файл `launch.json` **уже был изменён** (задача `updatesd` вырезана), а бэкап `launch.root_original.json` создан. То есть операция фактически применилась, упал лишь шаг cleanup-remount.
  - **Решение:** проверили фактическое состояние (обновление реально применилось), ничего чинить не пришлось.

Итог закрепления — **три слоя OTA-off** + fortress:

| Компонент | Что сделано | Бэкап оригинала |
|---|---|---|
| `activate_adb.sh` | обёртка: `deactivate` → no-op, `activate` → всегда `--network` | `activate_adb.root_original.sh` |
| `launch.json` | вырезана задача `updatesd` | `launch.root_original.json` |
| `device_ota_update.sh` | заменён на `#!/bin/sh` + `exit 0` | `device_ota_update.root_original.sh` |
| `ota_script.pub` | подменён на свежесгенерированный RSA-ключ | `ota_script.root_original.pub` |

Проверка: `ADB guard installed`, `OTA disabled in launcher configuration`, маркеры на месте, `updatesd` в процессах отсутствует.

### 5.9. Автономный тест

- Убрали DNS-подмену на роутере (0 `address=`-строк), `quasar.yandex.net` снова → `213.180.193.230`.
- Перезагрузили колонку **без стенда и без DNS-подмены** → `uid=0(root)` на месте.

### 5.10. Смена Wi-Fi-сети

- Mac переехал в сеть `192.168.1.0/24` (`192.168.1.79`), OpenWrt-роутер (`192.168.50.1`) стал недоступен.
- Колонку нашли в новой сети по MAC + порту 5555: **`192.168.1.80`**. Root пережил смену сети.

---

## 6. Таблица провалов → решений

| # | Провал | Диагноз | Решение |
|---|---|---|---|
| 1 | `expect` не выделяет pty | в песочнице нет pty | Python `paramiko` |
| 2 | `sudo`/`brew`/docker/nginx недоступны в песочнице | песочница пишет только в workspace | root-скрипт, который запускает пользователь |
| 3 | «Empty reply from server» при проверке стенда | nginx ещё перезапускался | подождать, перепроверить |
| 4 | колонка не шлёт `/get_sync_info` | заводская `0.1.1.6` (2021) слишком старая | offer одного OTA до `.46` |
| 5 | подозрение на жёсткий IP `87.250.251.227` | это OAuth (`*.oauth.yandex.ru`), норма | игнорировать |
| 6 | `install-adb` упал на `mktemp` | нет `/data/local/tmp` | `mkdir -p /data/local/tmp` |
| 7 | `disable-updates` упал на remount | UBIFS `/` уже rw, remount даёт EBUSY | проверить фактический результат (применилось) |
| 8 | неверный IP + неверный `adb shell <ip>` у пользователя | опечатка `192.168.80.1` + порядок adb | `adb connect` сначала, потом `adb shell` |

---

## 7. Как это работает (почему root выживает)

- **Маркеры** `/data/quasar/activate_adb_quasmodrom` и `/data/quasar/activate_network_adb` — `onboot.sh` при каждой загрузке видит их и поднимает сетевой `adbd` на `:5555` от root. Они лежат в `/data` (userdata), поэтому переживают и питание, и OTA (системный раздел меняется, а `/data` — нет).
- **Fortress** (`activate_adb.sh`-обёртка) превращает команду `deactivate` в no-op — Яндекс присылает конфиг без `remoteActivation`, но выключить ADB уже не может.
- **OTA-off** — три независимых слоя: `updatesd` не стартует (вырезан из `launch.json`), скрипт применения OTA — no-op, ключ проверки подписи OTA подменён.

---

## 8. Файлы проекта (в `~/алиса/`)

| Файл | Назначение |
|---|---|
| `stand/stand-setup.sh` | развернуть nginx-стенд (root) |
| `stand/stand-offer-update.sh` | включить offer обновления `.46` (root) |
| `stand/stand-teardown.sh` | остановить стенд (root) |
| `stand/router-dns.sh` | включить DNS-подмену (на роутере) |
| `stand/router-dns-rollback.sh` | откат DNS из бэкапа |
| `stand/router-dns-clean.sh` | снять DNS-подмену |
| `rssh.py` / `rrun.py` | SSH к роутеру (paramiko) |
| `find-alisa.sh` | найти колонку в текущей сети + adb connect |
| `yandex-station-root/` | форк hu553in (`persistence.py` для fortress/ota-off) |

---

## 9. Шпаргалка команд

```bash
# найти колонку и подключиться (автоматически, в любой сети)
cd ~/алиса && ./find-alisa.sh

# вручную
adb connect 192.168.1.80:5555
adb shell id                    # uid=0(root) gid=0(root)
adb shell cat /system/vendor/quasar/version_full

# статус закрепления
./.venv/bin/python yandex-station-root/persistence.py --adb adb --serial 192.168.1.80:5555 status
```

---

## 10. Откат

```bash
# вернуть ADB-скрипт и OTA-лаунчер (бэкапы на самой колонке)
./.venv/bin/python yandex-station-root/persistence.py --adb adb --serial <IP>:5555 restore-adb
./.venv/bin/python yandex-station-root/persistence.py --adb adb --serial <IP>:5555 restore-updates

# device_ota_update.sh и ota_script.pub — восстановить из *.root_original.* по adb:
adb shell 'cd /system/vendor/quasar && cp device_ota_update.root_original.sh device_ota_update.sh && cp ota_script.root_original.pub ota_script.pub'
```

---

## 11. Важные предупреждения

- **Колонка на `.50` — эта прошивка уже НЕ принимает eMudhra-цепочку.** Не делай **сброс до заводских**: он сотрёт `/data/quasar/` (маркеры), и повторно активировать ADB этим способом на `.50` не выйдет — придётся откатывать прошивку на `.46`.
- **Порт `5555` без пароля.** Держи колонку только в доверенной сети.
- Бэкапы оригиналов лежат на колонке в `/system/vendor/quasar/` (`*.root_original.*`) — не удаляй их, если хочешь иметь возможность отката.
