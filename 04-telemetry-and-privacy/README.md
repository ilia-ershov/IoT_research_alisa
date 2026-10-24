# 04 — Telemetry & privacy

The chapter that answers, with evidence: **what the speaker collects, how it stores and
sends it, when, to whom, how it's authenticated — and whether it listens to you.**

## Read
- **[telemetry.md](telemetry.md)** — the exhaustive analysis: on-disk stores, decompressed
  event payloads, identifiers, endpoints, batching/flush rules, device-key signing
  (`X-Quasar-Signature`), systemMetrics/traffic accounting, crash minidumps, remote config,
  and runtime-config evidence from `user_config.dat`.
- **[privacy.md](privacy.md)** — the focused "does Alice listen to me?" write-up.

## The short version
- **Two channels:** AppMetrica (`report.appmetrica.yandex.net`) + clickdaemon
  (`clck.yandex.net/quasar/write/json/batch`); daemon logs shipped by fluent-bit; crash
  minidumps uploaded to metrica.
- **Stored** gzip-compressed on disk in `appmetrica/persistedBatch`, synced every ~6 min
  (`maxStorageSizeMb:1`), flushed at a **204 800-byte** cap, retried with backoff, and
  **signed with a device key** (not account OAuth).
- **Collected:** connectivity/Wi-Fi events, per-process RSS, disk/traffic, directive
  *names*, A/B buckets, and a device fingerprint that includes the **Wi-Fi SSID** and
  **account UID**. **Not** collected: audio or transcripts.
- **Privacy verdict:** no continuous recording. Wake-word is on-device; activation audio
  is buffered only in **encrypted RAM**; raw-mic dumping is off. The one caveat is a
  configurable ~**1 % "very-rare" spotter sample** that logs ~5 s of audio.
- **Remotely controllable:** the backend pushes `statisticSampeRate` and the fluent-bit
  config at runtime via `config_capability` — there is no on-device opt-out.
