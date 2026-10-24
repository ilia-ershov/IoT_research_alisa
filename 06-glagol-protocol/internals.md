# Глубокий разбор glagol (IDA) — внутренности протокола

Расширение к GLAGOL_LIVE_TTS.md. Источник: реверс `maind` (IDA Pro), строки/данные,
декомпиляция обработчиков. Файлы исходников: `glagol.cpp`, `bypass_directive_handler.cpp`,
`quasar_voice_service_impl.cpp`, `yandex_io/services/glagold/`.

## 1. Классовая архитектура (namespace `glagol` / `YandexIO`)
- `glagol::BackendApi` / `CachedBackendApi` — запросы к облаку (`/glagol/token`,
  `device_list`, `check_token`).
- `glagol::ext::Connector`, `IConnector`, `IConnectorFactory` — WebSocket-соединения :1961.
- `glagol::AccountDevices` / `IndirectAccountDevices`, `DiscoveredItems`, `IDiscovery` —
  обнаружение колонок аккаунта (mDNS + бэкенд), построение кластера.
- **`glagol::BypassDirectiveHandler::handleDirective(shared_ptr<YandexIO::Directive>)`** —
  исполняет переданную директиву напрямую (ключевой узел инъекции, см. §4).
- `YandexIO::Glagol`, `YandexIO::GlagolCluster` / `GlagolClusterProvider` — верхний слой,
  мультирум-кластер; `GlagolCluster::processExternalCommand(Json::Value&)`.

## 2. Транспорт и обнаружение
- TLS-WebSocket на **:1961**, самоподписанный cert (`CN=localhost, O=Yandex`, ~3 года).
- mDNS-анонс `_yandexio._tcp` → instance `YandexIOReceiver-<deviceId>`
  (подтверждено: `YandexIOReceiver-[REDACTED-DEVICE-ID]`).
- Приватный ключ/cert устройства хранятся в `/data/quasar/devices.json` (секрет).

## 3. Формат сообщения (`onGlagolWSMessage`, glagol.cpp:1310)
```json
{ "conversationToken":"<ct>", "id":"<uuid>", "sentTime":<ms>,
  "payload": { "command":"<cmd>", ... } }
```
Доп. поля для кластера/соединений: `from_device_id`, `from_device_platform`,
`allow_backward_connection`, `backwardConnector`. Лог: `Incoming command '<cmd>', full request …`.

## 4. Команды и уровни доступа

### Разрешённые в ограниченном состоянии (whitelist `sub_FEF31C` → `off_1485208`)
Когда соединение в ограниченном состоянии (флаг `conn+16`), пропускаются ТОЛЬКО:
```
ping, softwareVersion, setVolume, play, stop, next, prev, rewind,
shuffle, repeat, playMusic, playRadio
```
→ медиа-контроль, громкость, пинг, версия. Низкопривилегированный набор.

### Только для владельца (вне whitelist → нужен полноценный conversationToken)
`sendText` (текст→Алиса), **`serverAction`** (произвольная директива), управление
аккаунтом и пр. Авторизация валидируется облаком (`/glagol/check_token` →
`valid`/`owner`/`guest`/`puid`, см. REPORT).

### Внутренние bypass-команды (кластер/лидер)
`externalCommandBypass`, `aliceStateBypass`, `leaderOverrideBypass` — снижают требования к
состоянию при обработке (для мультирум-лидера), ставят `conn_state=0`.

## 5. serverAction → исполнение произвольной директивы (мощный путь)
- Команда `serverAction` несёт payload типа `"type":"server_action"` c **raw-полезной
  нагрузкой** (`Use raw payload in server actions`).
- Через `BypassDirectiveHandler::handleDirective` это превращается в обычную
  **YandexIO::Directive** и исполняется локально.
- Следствие: `serverAction` с директивой **`TVocalizeDirective{Text}`** = заставить Алису
  произнести **произвольный текст** (не запрос, а чистый TTS); аналогично можно слать
  `SetLedMask`, медиа- и IoT-директивы — весь словарь `…DirectiveType`.
- `sendText` (использован в рабочем демо) — частный, более простой случай: текст идёт как
  пользовательский запрос (`quasar_voice_service_impl::startTextInput` →
  `TTextInput`/`handleVocalizeDirective`).

## 6. Мультирум-кластер
- Протоколы (protobuf): `quasar.proto.GlagolClusterMessage`, `GlagolClusterSign`,
  `ExternalCommandMessage`. Команды `multiroom_broadcast`, `multiroom_state`.
- Колонки соединяются между собой теми же glagol-коннекторами; «лидер» рассылает
  команды (там и нужны bypass-команды из §4).

## 7. Практические выводы (для research)
- **Низкопривилегированный LAN-контроль**: play/stop/next/setVolume/ping/version —
  проходят в ограниченном состоянии; это минимальная поверхность для гостя.
- **Полный контроль (владелец)**: `sendText` и особенно `serverAction` → `handleDirective`
  = исполнение любой директивы, включая произвольный TTS и LED. Нужен owner-токен.
- **Следующий шаг для «скажи любой текст»**: собрать `serverAction` с payload-директивой
  `TVocalizeDirective{Text:"…"}` и отправить тем же клиентом (`glagol_say.py`). Требуется
  структура payload server_action — доступна реверсом обработчика serverAction/формата
  директивы.

## 8. Ключевые адреса (IDA)
```
0xFF204C onGlagolWSMessage (glagol.cpp:1310)      0xFEF31C sub = whitelist-проверка команд
0x1485208 off_ = массив из 12 строк whitelist      0x50a751 BypassDirectiveHandler::handleDirective
bypass_directive_handler.cpp @0x28527a            "type":"server_action" @0x2660dc/0x3359b8
0x290d2c serverAction   0x26ec7e glagolSendTextCommand   0x2f8a14 quasar.proto.ExternalCommandMessage
```
