# Реверс через IDA: путь «речи» и директив (связка всех находок)

IDA Pro 9.4 + ida-pro-mcp. База 0x0 (VA == file offset). Все функции найдены по
строкам-якорям из `maind.strings`.

## 1. Протокол директив Алисы (из `.rodata`)
Полный словарь — сотни `…DirectiveType`/`…EventType`. Protobuf-типы (Arcadia `NAlice`):
- `NAlice.TAliceCapability.TVocalizeDirective` (+ поля `.Text`, `.Voice`) — **синтез речи**
- `NAlice.TAliceCapability.TStartTextInputDirective` — старт текстового ввода
- `NAlice.NAliceApi.TTextInput` (+ `.TClientOptions.PersId`) — текстовый запрос к Алисе
- входные типы: `DATA_INPUT/FILE_UPLOAD/HYBRID_ASR/MUSIC_INPUT/RECOGNIZE/RECORD_INPUT/`
  `SPEECH_INPUT/TEXT_INPUT/TRANSLATE_INPUT/VOCALIZE/VOICEPRINT_MATCH/VOICE_INPUT`

## 2. TTS-обработчик — `handleVocalizeDirective` (`sub_CC5914`)
Исходник: `alice_capability.cpp:1539/1564`. Логика:
1. `sub_CC8B90(&dir, a1, a2)` — распарсить входящую Vocalize-директиву в protobuf-объект.
2. Прочитать источник TTS (`v32`): таблица `dword_376C70[v32]`; при `v32>=4` →
   лог «Unsupported TTS source».
3. Если не сконвертировалось → лог «Can't convert the vocalize directive to protobuf,
   cancelling it» и отмена (`(*(a1+276))(a1,1,...)`).
4. Иначе собрать TTS-запрос (`sub_CC9D2C`, `sub_CC9D8A`) и вызвать плеер-capability:
   **`(*(a1[129] + 52))(a1[129], req)`** — это отдача текста/голоса в аудио-движок → ALSA.

→ Чтобы Алиса произнесла фразу, в работающий `platformd` надо доставить
`TVocalizeDirective{Text:"…", Voice:…}`. Нормально директива приходит из облака
(uniproxy); локально — через IPC-инъекцию в сервис, обрабатывающий директивы.

## 3. Текстовый ввод — `quasar_voice_service_impl.cpp`
- CLI-меню (`sub_A4C990`): клавиши `x/s/t/c/p/l/n/o/q/m`; `q` = «Text Input Query».
- `startTextInput` (`sub_D3881C`, `quasar_voice_service_impl.cpp:119`): форвардит
  text-input-запрос в capability `*(this+44)` через `vtable+40`. Это **сервис голоса**,
  которому шлёт CLI. Вызывается через IPC-диспетчер (прямых callers нет).

Две стратегии «заставить говорить живую Алису»:
- **A. TextInput-инъекция** → как `q`: послать текстовый запрос в сервис голоса; облако
  вернёт Vocalize → речь. Требует: имя IPC-сервиса + protobuf `TTextInput`.
- **B. Vocalize-инъекция** → напрямую `TVocalizeDirective{Text}` в обработчик директив;
  говорит без облака. Требует: protobuf `TVocalizeDirective` + точка приёма директив.

## 4. Что осталось для рабочей инъекции (следующий этап)
`quasar_client -s <service> -m <base64(protobuf)>` уже умеет слать сообщение в сервис.
Нужно доразобрать:
1. **Реестр IPC-сервисов** — как имена (`iohub_services`, voice service) мапятся на порты
   9875–9926 (в `quasar.cfg` есть `"port"`-таблица; сопоставить с сервисами в коде).
2. **Формат конверта IPC** — как `quasar_client` оборачивает `-m` payload (заголовок,
   id метода) перед отправкой в сервис.
3. **Сериализация** нужного protobuf (`TTextInput` или `TVocalizeDirective`) — проще всего
   снять готовый образец, перехватив реальное сообщение (strace/hook отправки), чем
   собирать вручную.

Оценка: это отдельный заметный этап реверса IPC-слоя. Пока подтверждено: внутренний путь
синтеза (`handleVocalizeDirective` → плеер) и точка текстового ввода
(`quasar_voice_service_impl`), адреса зафиксированы выше.

## 5. IPC-слой (реверс через IDA)

### Карта «сервис → порт» (из `quasar.cfg`, localhost)
```
9903 iohub_services   9910 iohub_clients   9850 yio_audio   9922 volume_manager
9906 gogol  9887 metricad  9904 metrica2d  9917 networkd  9926 network_stats
9875 vad  9878 authd  9882 config_capability  9891 external_commandsd
9898 brickd  9907 notificationd  9911 ntpd  9912 setupd  9921 stereo_pair
11124 multiroomd  11125 net_clock  9908 update_health_check  9924 backend …
```

### Как `quasar_client` шлёт сообщение (`sub_12ACDD8`)
1. `-m` строка → проверка base64 (charset `A–Za–z0–9+/=`) → **base64-декод** (`sub_725A9C`).
2. Декод парсится через **protobuf reflection** (`sub_6FC92C`); ошибки:
   «Message must be base64 string», «No reflection. Failed to parse message».
3. Имя `--service` → порт через config (`cfgcapa`, `sub_A808F0`), host по умолчанию `localhost`.
4. Соединение `tcp:<host>:<port>`, объект mixed_ipc-коннектора; **фрейминг делает коннектор**,
   пользователь даёт только сериализованный protobuf.
5. Отправка: `(*(conn+32))(conn, msg)` (лог «Sending message»).
→ Конверт вручную не нужен; нужен валидный сериализованный protobuf нужного типа.

### Локальный протокол glagol на :1961 (`onGlagolWSMessage`, `glagol.cpp:1310`)
Формат входящего сообщения (TLS WebSocket):
```json
{ "conversationToken": "<token>", "id": "<uuid>", "sentTime": <ts>,
  "payload": { "command": "<cmd>", ... } }
```
- Диспетчер логирует `Incoming command '<cmd>', full request <json>` и разводит команды
  (`loc_FEF4E8`): **`sendText`** (→ текст Алисе → ответ голосом), `serverAction`,
  `setVolume`, `ping`, STOP/next/prev и др.
- Внутренние bypass-команды: `externalCommandBypass`, `aliceStateBypass`,
  `leaderOverrideBypass` (для кластера/мультирум, снижают требования к состоянию).
- Аутентификация — `conversationToken`: проверяется облаком (`/glagol/check_token`,
  см. раздел glagol в REPORT). На диске токена нет (`clusterSaves=[]`).
- TLS-идентичность устройства (`server_certificate`/приватный ключ) лежит в
  `/data/quasar/devices.json` (чувствительно).

## 6. Две рабочие стратегии живого TTS (и их блокеры)
- **Route 1 — glagol `sendText` на :1961.** Формат JSON известен (выше). Блокер:
  нужен `conversationToken` — выдаётся бэкендом владельцу (`/glagol/token?device_id=`),
  получается из аккаунта/приложения. С токеном — тривиальный TLS-POST JSON.
- **Route 2 — внутренний IPC через `quasar_client -s <voice_service> -m <b64 proto>`.**
  Без токена (локальное доверие IPC). Блокер: нужен сериализованный protobuf `TTextInput`
  (поля `Text`, `TClientOptions.PersId`), т.к. клиент валидирует через reflection. Схему
  можно восстановить из встроенных protobuf-дескрипторов в бинаре либо снять с живого
  сообщения (на устройстве нет strace/tcpdump — потребуется статический сниффер).

## Якоря (адреса в IDA)
```
0x21022a handleVocalizeDirective (строка)   0xCC5914 sub = обработчик Vocalize
0x3669ad "Text Input Query"                  0xA4C990 sub = CLI-меню
0x2e5fb9 startTextInput                       0xD3881C sub = quasar_voice_service_impl:119
0x2b8a7e TVocalizeDirective.Text   0x28bf03 .Voice   0x2531f9 TStartTextInputDirective
0x12ACDD8 quasar_client main        0xFF204C onGlagolWSMessage (glagol.cpp:1310)
0x26ec7e glagolSendTextCommand      0x328d0c externalCommandBypass
0x2f8a14 quasar.proto.ExternalCommandMessage   0x290d2c serverAction
```
