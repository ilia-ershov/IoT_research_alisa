# 01 — Gaining root (cloud-config MITM)

Persistent root `uid=0` on the Yandex Station Lite, **without flashing firmware**, by
impersonating the Quasar cloud and letting the device enable network ADB on itself.

## Read
- **[field-report.md](field-report.md)** — the full English field report (abstract →
  recon → every failure and fix → persistence → results). Start here.
- **[writeup-ru.md](writeup-ru.md)** — Russian writeup of the same campaign.

## The idea in four lines
1. The firmware trust store still trusts leaked eMudhra/emSign CAs → mint a cert for
   `quasar.yandex.net` ("eQuasar").
2. Router DNS points the Quasar hostnames at a local HTTPS stand.
3. The stand's `/get_sync_info` sets `adbd.remoteActivation=true` → the device starts a
   **root `adbd` on :5555** itself.
4. Persist: wrap the ADB activation script so `deactivate` is a no-op, and disable OTA in
   three layers so an update can't remove the guard. Markers in `/data` survive reboot/OTA.

**Non-obvious gotcha:** a 2021 factory build won't activate at all until it is offered
**one OTA** to `.46` (the last build that still trusts the eMudhra chain).

## Contents
- [`toolkit/`](toolkit/) — `hu553in/yandex-station-root` repack: `persistence.py`
  (idempotent ADB-guard / OTA-off with backups), `config_proxy.py`, `dns_proxy.py`,
  `issue_certificate.py`, `firmware_offer.py`, `Makefile`. The leaked CA keys under
  `toolkit/certs/` are **omitted** (see the note there).
- [`mitm-stand/`](mitm-stand/) — OpenWrt DNS redirection + nginx stand setup / OTA-offer /
  teardown scripts.
- [`helpers/`](helpers/) — non-interactive SSH runners (`rssh.py`/`rrun.py`, pty-free via
  paramiko), `find-alisa.sh` (locate the speaker on any subnet), `fastfetch.sh`.

> Credentials and the leaked CA private key are redacted/omitted. The method builds on the
> public **eQuasar** project and the eMudhra CA disclosure, both cited in the field report.
