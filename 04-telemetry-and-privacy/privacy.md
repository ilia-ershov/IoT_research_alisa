# Часть 1 — Телеметрия и приватность Яндекс Станции Лайт

**Устройство:** Device ID `[REDACTED-DEVICE-ID]`, ПО `0.369.1.50…297`,
git `ce2b8fc`, локаль `ru-RU / COUNTRY_RU`, модель `yandexmicro`.

---

## 1. Как устроена телеметрия

Телеметрия — это режимы одного бинарника `maind` (симлинк `metrics_collector` → `maind`)
плюс отдельные демоны, запускаемые `quasar_launcher2` по `launch.json`:

| Демон (`maind --…`) | Роль |
|---|---|
| `--telemetry` | сбор событий, батч-отправка в AppMetrica + clickdaemon |
| `--fluent-bitd` | отгрузка текстовых логов демонов в облако (с семплингом) |
| `metrics_collector` (argv0) | сбор системных/железных метрик |
| `--platformd`, `--mediad` | генерируют события, которые собирает телеметрия |

### Куда уходит (подтверждено логами)
- **AppMetrica:** `https://report.appmetrica.yandex.net/report?...` — в query-строке
  метаданные устройства: `locale=ru_RU`, `app_id=aliced`, `app_platform=linux`,
  `model=yandexmicro`, `os_version=<kernel>`, **`deviceid=LG…294823`**,
  `uuid=[REDACTED-UUID]`, `api_key_128=46b160aa-…`.
- **Clickdaemon:** `https://clck.yandex.net/quasar/write/json/batch` (TLS, gzip) —
  батчи событий. За сессию: «sent successfully 252 batches, dropped 0».
- Международный контур (если выбран): `clck.yasmina.yango.com`, `startup.appmetrica.yango.com`.
- Startup-хост: `startup.mobile.yandex.net`.

### Что именно собирается (whitelist `appmetrica.events`, 30 событий — ВСЕ операционные)
```
NetInterfaceUp/GotAddress, wifiConnect/Disconnect/Report/Reset, connectionStats,
associationFailed, emptyIp/Networks/Scan(+Fixed), internetRecovery*, pings,
processStart, systemMetrics, setupConfigurationError, wrongIp(+Fixed),
directiveStarted/Handled/Completed, phraseSpottedWithoutInternet,
ysk_error_network, ysk_error_timeout
```
→ Это **сетевая диагностика, статусы Wi-Fi, факты выполнения директив (имена, не
содержимое), системные метрики и ошибки**. Аудио, транскриптов, текста запросов —
**нет**. `directiveHandled` фиксирует, что команда выполнена, но не что было сказано.

### fluent-bit (отгрузка логов демонов)
Конфиг: tail `/data/quasar/daemons_logs/*.log` + `/var/log/messages` →
`clck.yandex.net:443/quasar/write/json/batch`, gzip, TLS. **`samplingRatio: 0.5`** —
на текущей загрузке в лог: «fluentbit disabled by sampling» (т.е. логи шлются не всегда,
по вероятности). Содержит технические логи работы, не аудио.

---

## 2. «Слушает ли меня Алиса?» — ответ по фактам

**Коротко: микрофоны всегда включены и обрабатываются ЛОКАЛЬНО для детекта слова
«Алиса»; запись/передача наружу происходит только при (предполагаемой) активации;
на постоянную запись в долгую память ничего не идёт.**

Доказательная база:

1. **Wake-word — на устройстве, не в облаке.**
   4 локальные TFLite-модели в `/data/quasar/data/spotter_model/` (из `spotter.json`):
   `activation/alisa`, `command`, `counteractivation`, `vad` (детектор голоса человека).
   Телеметрическое событие **`phraseSpottedWithoutInternet`** прямо подтверждает: слово
   ловится даже без интернета.

2. **Аудио-буфер — только в ОЗУ, ограниченный, не растёт.**
   `audioStorageHistory.json = ["/tmp"]` → кэш в **tmpfs (RAM)**, не во флеше.
   Файлы `/tmp/*.audiostoragecache` ~1.4–2.9 МБ, **за 6 c не изменились**, метки времени
   старые (прошлые активации). Это кольцевой буфер (`audiosender.historySeconds: 10`),
   а не непрерывная запись. После перезагрузки — исчезает.

3. **Буферы активаций ЗАШИФРОВАНЫ.**
   `*.audiostorageinfo`: `{"decodeKeyHash":"…","streamId":"…","usage":0/1,"vsid":"…"}`.
   Хранится только **хэш ключа**, сам ключ на устройстве отсутствует; привязка к
   облачной голосовой сессии (`vsid`). Локально расшифровать дамп нельзя.

4. **Отладочный дамп сырого звука — ВЫКЛЮЧЕН.**
   Механизм `audiosender` умеет дампить сырые каналы `raw_mic_0..3`, `raw_spk`, `vqe`,
   но управляется файлом `${DATA}/data/audiosender.json`, которого **на устройстве нет**
   → сбор сырого микрофонного потока не активирован.

5. **Что всё же уходит наружу и когда:**
   - **Онлайн-валидация активации:** `onlineSpotterValidationDisabledTypes:[noise-detection,
     vad]` — значит сами активации (`alisa`/`yandex`) проходят проверку в облаке → короткий
     фрагмент вокруг срабатывания отправляется, чтобы отсеять ложные.
   - **Голосовой поток после активации:** `audioClientStartedFromVoiceInput` → соединение
     VoiceDialog на `wss://uniproxy.alice.yandex.net` (это штатный диалог с ассистентом).

### Вывод
Непрерывной слежки/записи «всего подряд» на диск или в облако по данным устройства
**не обнаружено**. Приватность опирается на: локальный wake-word, эфемерный
зашифрованный буфер в RAM, выключенный raw-дамп. Точки, где звук покидает устройство, —
онлайн-валидация активации и штатный диалог после «Алиса». Полную гарантию дало бы
снятие TLS-трафика (нужен обход pinning) — отдельная задача.

> Проверка для владельца: событие `phraseSpottedWithoutInternet` и каталог
> `spotter_model` подтверждают локальный детект; отсутствие `audiosender.json`
> подтверждает, что сырой дамп не ведётся.
