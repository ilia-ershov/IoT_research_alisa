# artifacts/

Small, non-sensitive artifacts pulled from the device, kept for reference.

- `quasar.cfg` — the Quasar platform's firmware config (endpoints, spotter models,
  telemetry/metrica settings, glagol/SIP ports). A firmware artifact, not user data.
- `alice_speaking.led` — a real LED animation pattern (the "speaking" breathing effect);
  illustrates the `.led` format documented in [`../05-audio-and-led/led.md`](../05-audio-and-led/led.md).
- `version_full` — the firmware version string.

## Deliberately **not** included
- `maind` (21 MB binary) and its IDA database (`*.id0/id1/id2/nam/til`, ~400 MB) — large
  and copyrighted; the analysis lives in [`../03-reversing-quasar/`](../03-reversing-quasar/).
- Raw device dumps and pulled user state (logs, `account_storage.dat`, certs) — contain
  live secrets.
- The leaked eMudhra CA key material used by the rooting method.
