# Telemetry Deep-Dive — Yandex Station Lite

Complete analysis of the device's telemetry: **what** it stores, **how** it stores/sends,
**when** it sends, **where** it goes, how it is **authenticated**, and what is **remotely
controllable**. Based on on-device inspection + IDA reverse of `maind`.
Device ID `[REDACTED-DEVICE-ID]`, Passport UID `[REDACTED-UID]`, Quasar 3.21.

---

## 0. TL;DR
- Two telemetry channels: **AppMetrica** (analytics events) and **clickdaemon/clck**
  (metrics + shipped logs). A third path uploads **crash minidumps** to metrica.
- Events are buffered **on disk, gzip-compressed**, in `/data/quasar/appmetrica/persistedBatch`,
  then POSTed in batches over TLS, **signed with a device key** (`X-Quasar-Signature`).
- Payloads are **operational only** (connectivity, Wi-Fi, system metrics, directive
  names, errors) — **no audio, no transcripts**. But each batch carries a rich device
  **environment fingerprint**, including the **current Wi-Fi SSID** and the **account UID**.
- Sending is **event-driven + periodic**, gated by **sampling** and **batch-size/flush**
  rules, with **retry/backoff**. The backend can tune sampling **remotely**
  (`config_capability` → `statisticSampeRate`).

---

## 1. What is stored (on-disk)

| Path | Content | Format |
|---|---|---|
| `/data/quasar/appmetrica/persistedBatch` | queued AppMetrica event batches awaiting upload | framed **gzip** blobs |
| `/data/quasar/data/metrica/session_id_part.txt` | metrica session counter (`6`) | text |
| `/data/quasar/data/metrica/clickdaemon/metadata.json` | `{"UUID":"[REDACTED-UUID]"}` | JSON |
| `/data/quasar/data/metrica/clickdaemon/session_id_part.txt` | clickdaemon session counter (`1`) | text |
| `/data/quasar/quasar_metricad.json` | `{"UUID":"[REDACTED-UUID]","created":1792845731,"reports":[...],"startups":[...]}` | JSON |
| `/data/quasar/minidump/*.dmp.env.json` | crash-upload metadata per daemon | JSON |
| `/data/quasar/daemons_logs/*.log` | per-daemon logs (shipped by fluent-bit, sampled) | text |

### Decompressed `persistedBatch` — the actual queued events
Each record = 6-byte frame header + gzip stream. Decompressed, a record is an AppMetrica
event plus the session environment. Example (real data):
```
event: connectionStats = {"connected":false,"duration":1214746,
                          "endpointName":"uniproxy","previousConnected":true}
env/session attributes attached to every batch:
  login(UID)=[REDACTED-UID]  locale=ru-RU  timezone=Europe/Moscow  country=RU
  wifi_ssid=[REDACTED-SSID]   wifi_freq=2412   wifihw=Realtek
  currentVolume=…  areMicsMuted=…  is_bluetooth_on=…  is_bt_source_connected=0
  bt_fw_version=Unknown  spotterModel=alisa
  quasmodrom_group=production  quasmodrom_subgroup=production
  test_buckets=1669619,0,68;1730437,0,28;…   (A/B experiment assignments)
```
> Privacy note: the batch environment includes the **current Wi-Fi SSID** and the **Yandex
> account UID**, alongside volume / mic-mute / Bluetooth state. No audio or ASR text is stored.

---

## 2. Identifiers
- **metrica UUID** `[REDACTED-UUID]` (`quasar_metricad.json`; also the
  AppMetrica `uuid=` query param).
- **clickdaemon UUID** `[REDACTED-UUID]` (separate).
- **deviceid** `[REDACTED-DEVICE-ID]` (hardware id; sent as `deviceid=` and
  header `x-yaquasardeviceid`).
- **UID** `[REDACTED-UID]` (Yandex Passport account; sent as `login`).
- **session_id_part** counters increment per boot/session (metrica=6, clickdaemon=1).
- Device "props" (synthetic, Android-like) reported for compatibility: `model/brand/
  device/manufacturer=yandexmicro`, `ro.build.version.release=<quasar ver>`,
  `cpu.abi=arm64-v8a`, `sys.boot_completed=1`.

---

## 3. What is collected (event schema)

### AppMetrica event whitelist (`appmetrica.events`, `mode:"black"`, empty blacklist → all env sent)
30 operational events, grouped:
- **Connectivity:** `connectionStats`, `pings`, `internetRecovery[/Start/Success/Fail]`,
  `ysk_error_network`, `ysk_error_timeout`.
- **Wi-Fi / IP:** `wifiConnect`, `wifiDisconnect`, `wifiReport`, `wifiReset`,
  `NetInterfaceUp`, `NetInterfaceGotAddress`, `associationFailed`,
  `emptyIp[/Fixed]`, `emptyNetworks[/Fixed]`, `emptyScan[/Fixed]`, `wrongIp[/Fixed]`.
- **Lifecycle / health:** `processStart`, `systemMetrics`, `setupConfigurationError`.
- **Assistant (metadata only):** `directiveStarted`, `directiveHandled`,
  `directiveCompleted` (directive *names*, not content), `phraseSpottedWithoutInternet`.

### systemMetrics source — `monitord` (port 9895)
```
metricsCollectorPeriodSec: 10     # sample every 10 s
metricsDumperPeriodSec:    300    # emit every 5 min
disksList: [ubi0_0, ubi1_0]       # flash usage
servicesList: quasar_launcher2,updatesd,mediad,telemetry,platformd,fluent-bitd  # RSS/liveness
pinger: ping quasar.yandex.ru every 10 s (raw socket) -> "pings" event
pstorePath: /sys/fs/pstore        # kernel crash store -> crash telemetry
```
Per-daemon RSS limits are enforced (`memoryLimitRssKB`, `selfDestroyer` restarts on breach).

### Network traffic accounting — `traffic_monitor`
```
counterBin: yio_iptables_count.sh   # reads & zeroes (-Z) byte/packet counters of
                                     # iptables chains yio_INPUT/yio_OUTPUT (+per-category)
periodSec: 1200                      # every 20 min
sampleRate: 0.11                     # ~11% of periods
```
→ categorized up/down traffic volumes per destination class.

### Crash telemetry (minidumps)
`telemetry.Minidump.enabled=true`, `moveToMetrica=true`, `sizeLimitKB=200`. Each daemon has
`minidump/<daemon>.dmp` + `<daemon>.dmp.env.json` tagging the dump with
`quasmodrom_group/subgroup` and `test_buckets`. On crash the dump is handed to metrica for
upload.

---

## 4. How it is sent (transport)

### Endpoints
- **AppMetrica:** `https://report.appmetrica.yandex.net/report?...` — query carries
  `deviceid`, `uuid`, `api_key_128=46b160aa-bba7-421a-9e3d-f366e76386ef`, `app_id=aliced`,
  `app_platform=linux`, `model=yandexmicro`, `os_version`, `locale`. Startup/config from
  `https://startup.mobile.yandex.net`.
- **clickdaemon (clck):** `https://clck.yandex.net:443/quasar/write/json/batch` (TLS, gzip)
  for metrics; `clck.yandex.net/quasar_metrics/write/batch` variant. International contour:
  `clck.yasmina.yango.com`, `startup.appmetrica.yango.com`.
- **fluent-bit (daemon logs):** tails `/data/quasar/daemons_logs/*.log` **and
  `/var/log/messages`**, ships to `clck.yandex.net:443/quasar/write/json/batch`.

### Encoding & batching
- Events serialized, accumulated into a batch, **gzip-compressed**, persisted to
  `persistedBatch`, then POSTed. Confirmed by the gzip framing on disk and
  `persistent_batch_sender`/`appmetrica_batcher` log lines.

### Authentication / integrity (IDA)
Requests to the Yandex backend are **signed with a device key**. `sub_C96F24` emits headers:
```
X-Quasar-Signature-Version        (scheme selector: 2 or 4)
X-Quasar-Signature-Cryptography
X-Quasar-Signature                (the signature)
x-yaquasardeviceid                (device id)
```
This binds telemetry to the physical device identity (device key; OP-TEE/keymaster present
on the unit — `keymaster_svc`, `platformKey.h.sha256`). No account OAuth is required for
the metrics channel — identity is the device signature + deviceid + metrica UUID.

---

## 5. When it is sent (triggers & gating)

### Flush / batch rules (IDA: `appmetrica_batcher.cpp:tryAdd`, `sub_13CC69C`)
- Add event while `batch_bytes + event_bytes <= 204800` **and** event count `< maxCount`.
- If adding would exceed **204 800 bytes** → **flush** current batch, start new one
  (log: *"…exceeded limit 204800 bytes. Delay event to next batch"*).
- If event count reaches the per-batch max → **flush**.
- `persistent_batch_sender` then uploads queued batches (periodically / when online); on
  failure it **retries with backoff** (observed `curl error: 28` → "delaying next attempt
  for 14318ms / 24934ms", queue preserved; "sent successfully 252 batches, dropped 0").

### Periodic emitters
- `systemMetrics`: sample 10 s / emit 5 min. `pings`: every 10 s. `traffic_monitor`:
  every 20 min (11% sampled). fluent-bit log flush: every **60 s**.

### Event-driven emitters
- Network/Wi-Fi transitions (`connectionStats`, `wifi*`, `internetRecovery*`),
  `processStart` (boot), `directive*` (each assistant directive), crash → minidump upload.

### Sampling (what fraction actually leaves)
- **fluent-bit** daemon-log shipping: `samplingRatio 0.5` (on the observed boot it rolled
  *disabled* → logs not shipped that session).
- **traffic_monitor**: `sampleRate 0.11`.
- **statistic sample rate**: `statisticSampeRate` delivered at runtime by
  `config_capability` (currently `1.0`).

### Rate limiters (anti-flood, from runtime)
- `log_error, ysk_error_client, ysk_error_workingthread_block`: max **3 / 10 s**.
- `ysk_spotter_queue_overflow`: max **1 / 120 s**.

---

## 6. Remote control of telemetry
`config_capability` (port **9882**) receives runtime config from the backend and already
delivers `{"statisticSampeRate":1.0}`. This means Yandex can **change telemetry behaviour
remotely** (sampling, and the fluent-bit config block is also pushed at runtime — observed
`Got fluent-bit config update: {...samplingRatio, tailPaths, clickdaemonHost...}`), without
a firmware update. There is no user-facing opt-out exposed on the device; the
`envKeysBlacklist` is empty and `appmetrica.mode` is `"black"` (nothing suppressed).

---

## 7. Privacy assessment (telemetry-specific)
- **Not collected:** audio, ASR transcripts, request text, contact/message content. The
  `directive*` events record *which* directive ran, not its payload.
- **Collected / sent (fingerprinting):** account **UID**, **Wi-Fi SSID** + band + NIC
  vendor, timezone, locale, country, volume, mic-mute & Bluetooth state, spotter model,
  A/B buckets, per-process RSS, disk usage, connectivity timings, categorized traffic
  volumes, crash dumps, and synthetic device props. Enough to fingerprint the home network
  (SSID) and tie all metrics to the account.
- **At rest:** batches live gzip-compressed in `/data` (rw flash) until uploaded; not
  encrypted at rest, but signed and TLS-protected in transit.

---

## 8. How to reduce/neutralize telemetry (owner, with root)
- Blackhole the endpoints locally (the device already runs `unbound` at 127.0.0.1:53):
  null-route `report.appmetrica.yandex.net`, `startup.mobile.yandex.net`,
  `clck.yandex.net`. (Note: breaks nothing critical for local glagol control, but the
  device will queue batches and retry.)
- Remove/neuter `metrics_collector`/`--telemetry`/`--fluent-bitd` tasks in `launch.json`
  (rootfs is read-only; needs remount or an overlay in `/data`).
- Firewall outbound 443 to the metrics hosts at the router.
- Be aware the backend can re-enable/retune via `config_capability`.

---

## 9. Runtime-config evidence (`/data/quasar/data/user_config.dat`)
The device's live account/device/system config (a protobuf wrapping a large JSON blob,
keyed by the account UID) confirms and extends the above:

- **Persistent batcher** (`system_config.teleme3d.appmetrica.persistentBatcher`):
  `enabled:true`, `storagePath:${DATA}/appmetrica/persistedBatch`, **`maxStorageSizeMb:1`**,
  **`syncPeriodSec:360`** (upload queue every 6 min), `maxBatchCollectingWhenNoInternetTimeSec:360`,
  `lookForNetworkConnection:true`. This is the "when it sends" ground truth.
- **Event lists**: `teleme3d.appmetrica.+events` and `persistentAppmetrica.+events` match
  the 30-event whitelist in §3.
- **Spotter audio logging** (`voiceDialogSettings`): `spotterLoggingVeryRareEventPercent:1`,
  **`spotterLoggingVeryRareStreamingLengthMillis:5000`**, `spotterLoggingRareEventPercent:0`,
  `spotterLoggingHeadMillis:0`, `spotterLoggingTailMillis:0`. → a configured **~1 % of
  "very-rare" spotter events logs ~5 s of streaming audio** (quality sampling). The only
  path by which short activation audio is sampled off-device beyond online validation.
- **User-logging flags**: `account_config.doNotUseUserLogs:false`, `saveHistoryUsage:true`,
  `onlineSpotterEnabled:true`, `voice_activation.enabled:true` — user logging/history on.
- **Other cadences**: `syncd.pollPeriodSec:1800` (config re-poll every 30 min),
  `wifiSettings.generate204` connectivity probe (`periodSec:300`, 8 s timeout, 3 fails →
  recovery), `telemetry.rate_limiter` `ysk_spotter_queue_overflow` 1 / 120 000 ms.
- **Environment echoed into telemetry**: `appmetrikaReportEnvironment` and `env` both carry
  `quasmodrom_group/subgroup=production` and the `test_buckets`/`testids` A/B assignments —
  the same attributes attached to every batch (§1).

## Appendix — key IDA anchors
```
sub_13CC69C  appmetrica_batcher.cpp:134 tryAdd  (204800-byte flush logic)
sub_C96F24   X-Quasar-Signature header builder (version/cryptography/signature)
sub_E9A108   request header builder (x-yaquasardeviceid + signature)
strings: persistent_batch_sender.cpp, metrica_batch_sender_base.cpp,
         appmetrica_batcher.cpp, clickdaemonBatchSender, X-Quasar-Signature*
config: monitord (9895), config_capability (9882), traffic_monitor, appmetrica, telemetry
```
