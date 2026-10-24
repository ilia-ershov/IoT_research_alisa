# 04 — Telemetry and privacy

What the speaker collects, how it stores and sends it, when, to whom, how it's signed — and
whether it listens to you.

## What to read
- [telemetry.md](telemetry.md) — the full analysis: the on-disk stores, the actual
  decompressed event payloads, the identifiers, the endpoints, the batching and flush rules,
  the device-key signing, system metrics and traffic accounting, crash minidumps, remote
  config, and what `user_config.dat` confirms at runtime.
- [privacy.md](privacy.md) — the "does Alice listen to me?" question on its own.

## The short version
- Two channels: AppMetrica (`report.appmetrica.yandex.net`) and the clickdaemon
  (`clck.yandex.net`). Daemon logs go out through fluent-bit; crash dumps go to metrica.
- Events are buffered on disk, gzip-compressed, synced about every six minutes, flushed at a
  200 KB cap, retried on failure, and signed with a device key rather than account OAuth.
- Collected: connectivity and Wi-Fi events, per-process memory, disk and traffic figures,
  directive names, A/B buckets, and a device fingerprint that includes the Wi-Fi network name
  and the account id. Not collected: audio or transcripts.
- On privacy: no continuous recording. Wake-word runs on-device; activation audio is kept
  only in encrypted RAM buffers; raw-mic dumping is off. The one caveat is a configurable
  ~1% "very-rare" spotter sample that logs about five seconds of audio.
- The backend can change sampling and the log-shipping config at runtime, and there's no
  opt-out on the device.
