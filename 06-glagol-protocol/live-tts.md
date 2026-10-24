# Рабочий метод: живой TTS Алисы через glagol (Route 1) — УСПЕХ

Заставили живую Алису произнести ответ по локальной сети через реверснутый протокол
**glagol** (:1961). Подтверждено на слух владельцем.

## Полная цепочка

### Шаг 1 — OAuth-токен аккаунта (шорткат через root)
Вместо логина/перехвата приложения вытащили токен прямо с устройства:
```
adb pull /data/quasar/account_storage.dat
```
protobuf-поля: `1.1` = Passport UID `[REDACTED-UID]`; `1.2`,`1.3` = OAuth `y0_…`;
`1.4` = x-token `2:…`. Рабочим для API оказался токен из поля **1.3**
(поле 1.2 → `USER_IS_NOT_AUTHORIZED_FOR_API`, x-token → `AUTH_TOKEN_INVALID`).

### Шаг 2 — conversationToken с бэкенда
```
GET https://quasar.yandex.net/glagol/device_list          Authorization: OAuth <y0_…1.3>
GET https://quasar.yandex.net/glagol/token?device_id=[REDACTED-DEVICE-ID]&platform=yandexmicro
      → {"token":"<conversationToken>", "status":"ok"}        (JWT-вида, ~237 симв.)
```
Это ровно те запросы, что нашли в прошивке (`sub_D63070`, поле `token`).

### Шаг 3 — отправка команды на колонку
```
wss://192.168.1.80:1961   (TLS, самоподписанный cert CN=localhost/O=Yandex, verify off)
→ {"conversationToken":"<ct>","id":"<uuid>","sentTime":<ms>,
   "payload":{"command":"sendText","text":"<фраза>"}}
```
Ответ колонки: `status=SUCCESS` + поток state-JSON с `aliceState`
(`IDLE→NONE→LISTENING→SPEAKING→IDLE`).

## Важная деталь: две независимые громкости
- **ALSA Master** (`amixer set 'Master' N%`) — аппаратный микшер; влияет на прямой `aplay`.
- **Платформенная громкость Алисы** (`state.volume` 0.0–1.0) — отдельная; при 0.0 речь
  Алисы **не слышна**, даже если ALSA поднят. Поднимается glagol-командой
  `{"command":"setVolume","volume":0.3}` (или голосом). Сейчас выставлена 0.3.

## Команды glagol (из реверса `onGlagolWSMessage`, glagol.cpp:1310)
`sendText` (текст→Алиса), `setVolume`, `ping`, плеер (play/pause/next/prev/stop),
`serverAction`; внутренние bypass: `externalCommandBypass`/`aliceStateBypass`/`leaderOverrideBypass`.

## Скрипты (в scratchpad)
- `glagol_ask.py <token_file> "<фраза>"` — послать текст, логировать состояния.
- `glagol_say.py <token_file> "<фраза>" <vol>` — поднять громкость + послать текст.
- токен: `conv_token.txt`; OAuth-кандидаты: `tok_a/tok_b/tok_x.txt` (НЕ коммитить — секреты).

## Безопасность / приватность вывода
`account_storage.dat` и извлечённые токены — это ключи доступа к аккаунту Яндекса
владельца. В отчётах и чате они **маскированы** и лежат только во временном scratchpad.
Для сброса доступа: отвязать устройство / разлогинить сессии в аккаунте.
