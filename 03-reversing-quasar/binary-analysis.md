# Первичный разбор `maind` (Яндекс Станция Лайт)

**Файл:** `/system/vendor/quasar/maind` → локально `artifacts/maind`
**Размер:** 21 819 816 байт
**SHA-256:** `459679b2d4d0cf46dc31f0270913d8b0a99cd2bbe6604745a68a25123847919a`
**Прошивка:** Quasar 3.21 (`0.369.1.50.4794655315.20261021.297`)

---

## 1. Что это за бинарник

```
ELF 32-bit LSB pie executable, ARM EABI5, dynamically linked,
interpreter /lib/ld-linux-armhf.so.3, BuildID[sha1]=ee2ed366…, stripped
```

- **32-битный ARM (armhf)** userland поверх **aarch64-ядра** (64-бит ядро, 32-бит ПО).
- **PIE**, **stripped** (символы вырезаны — отладочных имён функций нет).
- Собран из монорепозитория Яндекса **Arcadia** (`ya make`, `build_chain`), компилятор
  Clang, статический **libc++** (секция `__lcxx_override`).
- Это **монолит-мультитул**: один бинарь реализует все демоны. Режим выбирается аргументом:
  `--platformd`, `--mediad`, `--telemetry`, `--fluent-bitd`, `--updatesd`
  (+ симлинки `quasar_client`, `led_util`, `metrics_collector`, `keymaster_proxy_app`,
  `tcp_alsa_writer`, `metricad`, `glagold` — поведение зависит от `argv[0]`).

### Карта секций (ключевое)
| Секция | Размер | Смысл |
|---|---|---|
| `.text` | ~14 МБ | код (огромный — вся логика здесь) |
| `.rodata` | ~3.6 МБ | строки/константы/конфиг-дефолты |
| `.data.rel.ro` | ~770 КБ | таблицы указателей (vtables/релокации) |
| `SYSTEMD_BUS_ERROR_MAP` | — | использует **sd-bus** (systemd D-Bus) |
| `malloc_hook`, `.ARM.extab` | — | свой аллокатор-хук, C++ exceptions |

## 2. Зависимости (NEEDED), `RUNPATH=/system/vendor/quasar/libs`

| Библиотека | Роль |
|---|---|
| **`libtflite.so`** | TensorFlow Lite — on-device ML (wake-word, VAD), делегаты **XNNPack/NNAPI** |
| **`libyandex_evil.so`** | внутренняя glue-библиотека Яндекса |
| `libasound.so.2` | ALSA (захват/воспроизведение звука) |
| `libavahi-common/core` | mDNS/Zeroconf — обнаружение glagol (`_yandexio._tcp`) |
| `libglib`, `libiconv` | GLib, перекодировки |
| libc/pthread/rt/dl/m | стандарт |

Крипта вкомпилирована статически — **BoringSSL** (символ `BN_mod_inverse_no_branch`).

## 3. Голосовой front-end (микрофонный массив)

Импортируется C-API **`YandexVqeC_*`** (Voice Quality Enhancement):
- `YandexVqeC_Process`, `GetDoa` (**Direction of Arrival** — определение направления на
  говорящего), `GetCurrentActiveZone`, beamforming по зонам;
- `RoomCorrection_*` (калибровка под комнату), `EqualizerConfig_*`, `GetOutdoorsDetectorResult`
  (детектор «на улице»), `GetMicHealthConfidences` (диагностика микрофонов).
- Дальше — **TFLite** интерпретатор прогоняет споттер-модели из `spotter_models/`
  (`alisa`, `yandex`, `command`, `vad`, `counteractivation`).

Пайплайн: **микрофоны → VQE (beamforming/AEC) → TFLite spotter → UniProxy (облако)**.

## 4. Сетевой протокол и бэкенды

### Главный канал — UniProxy (голосовой ассистент)
- `wss://uniproxy.alice.yandex.net` — основной WebSocket
- `uniproxy-quic.alice.yandex.net` — вариант по QUIC
- `uniproxy-roz.alice.yandex.net`, `rpc.alice.yandex.net`, `voiceservices.yandex.net`
- `alice-ats.yandex.net` / `alice-ats-test.yandex.net` — ATS

### Протокол директив/событий Алисы
В `.rodata` — **полный словарь протокола**: сотни типов
`…DirectiveType` (команды из облака) и `…EventType` (события в облако). Домены:
- **Голос/медиа:** `AudioPlayer*`, `Vocalize`, `StartVoiceInput`, `CompleteTtsResponse`
- **Умный дом:** `Iot*` (Zigbee/Matter/**Tuya**/Thread), камеры (`Camera*`), замки
  (`DoorLock*`), термостаты, шторы, датчики протечки; даже **HVAC/кузов автомобиля**
  (`SetHvac*`, `OpenBodyTrunk…`) — общий бинарь на всю линейку устройств
- **Телефония/звонки:** `PhoneCalls*`, `*VideoCall*` (SIP + WebRTC/DTLS)
- **Управление браузером/ТВ:** `BrowserControl*`, `Tv*`, `WebOS*`
- **Биометрия:** `CalculateVoiceprint`, `StartFaceRecording`, `AddEnrolledPerson`
- **Потенциально чувствительные для приватности:**
  `TakeScreenshot`, `CameraSnapshotTakePicture`, `StartFileUpload`,
  `CollectDiagnosticArtifact`, `SendBugReport`, `ForceOtaRequest`, `OtaApply`

### Локальный протокол glagol (управление по LAN, порт 1961)
Эндпоинты выдачи/проверки токена на бэкенде:
```
https://quasar.yandex.net/glagol/token?device_id=…
/glagol/check_token   /glagol/v2.0/check_token
/glagol/device_list   /glagol/family_device_list
```
- Устройство получает glagol-токен с бэкенда, затем принимает **локальные команды по
  TLS на :1961**, анонсируясь через mDNS (`_yandexio._tcp`). Multiroom = «glagol cluster».

### Телефония
`alicesbc.tel.yandex.net` (SBC), SIP на :5081, SIP-instance через `urn:uuid:…`.

### Прочее
- Музыка: `wss://ws.api.music.yandex.net/quasar/websocket`
- Загрузки/артефакты в S3 `quasar.s3.yandex.net` — подпись **AWS SigV4**
  (`…4-HMAC-SHA256 Credential=…, Signature=…`)
- Метрики: AppMetrica, `clck.yandex.net`, лог-стрим `log.strm.yandex.ru`
- Международный контур Yasmina/Yango присутствует параллельно (см. `quasar.cfg`)

## 5. Безопасность транспорта (важно для перехвата трафика)

- **Certificate / public-key pinning**: строки
  `SSL public key does not match pinned public key`, `:Pinned-%s`.
  → Простой MITM с подменой CA **не пройдёт**; для анализа облачного трафика нужен
  обход пиннинга (патч бинаря/хук функции сравнения ключа, т.к. root уже есть).
- TLS 1.0–1.3 + **DTLS 1.0/1.2** (медиа/звонки/WebRTC).
- Авторизация к облаку: `Authorization: Bearer <OAuth>` — токен лежит в
  `account_storage.dat` (protobuf).

## 6. Выводы и куда копать дальше

1. **Протокол директив — самая богатая поверхность.** Весь список `DirectiveType`/`EventType`
   выгружен в `artifacts/maind.strings` — это фактически спецификация того, что станции
   можно приказать из облака (и, через glagol, частично локально).
2. **glagol (1961)** — реальный локальный вектор: имея токен (получается из привязанного
   аккаунта/бэкенда), можно слать команды/TTS на колонку по LAN без облака.
3. **Pinning** — главный барьер для прослушки облачного канала; при наличии root обходится
   патчем в `.text` (бинарь stripped, но строку-ошибку пиннинга легко заякорить).
4. **Биометрия и медиа-директивы** (`CalculateVoiceprint`, `CameraSnapshot`, `StartFileUpload`)
   — зона приватности; стоит проверить, какие из них доступны без подтверждения.
5. Для полноценного реверса нужен **дизассемблер** (radare2/Ghidra/IDA, ARM32):
   якориться по строкам в `.rodata` → xref на обработчики директив и на функцию пиннинга.

### Артефакты
```
artifacts/maind            # бинарь (21 МБ)
artifacts/maind.strings    # все строки (116 953 строк) — грепать здесь
artifacts/quasar.cfg       # полный конфиг (63 КБ)
```
Полный дамп категорий строк: см. tool-results в сессии.
