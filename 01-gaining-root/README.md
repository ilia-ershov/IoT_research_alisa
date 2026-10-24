# 01 — Getting root

Persistent root on the speaker without flashing anything, by pretending to be the Quasar
cloud and letting the device turn on root ADB by itself.

Read the [field report](field-report.md) first (English). The [Russian writeup](writeup-ru.md)
covers the same ground.

## The short version
The firmware still trusts leaked eMudhra CA certificates, so you can present a valid-looking
certificate for `quasar.yandex.net`. Point the speaker's DNS at a local server, answer
`get_sync_info` with `adbd.remoteActivation=true`, and the device starts a root ADB server on
:5555. Then make it stick: wrap the ADB activation script so "deactivate" does nothing, and
turn OTA off so an update can't undo any of it. The activation markers live in `/data`, so
they survive reboots.

One catch worth knowing: a 2021 factory build won't finish activation until it receives a
single OTA. So you have to offer exactly one update — to build `.46`, the last one that still
trusts the eMudhra chain.

## What's here
- [`toolkit/`](toolkit/) — the rooting tool: `persistence.py` (installs the ADB guard and
  turns OTA off, with backups) and the config/DNS/certificate helpers. The leaked CA keys
  that would go under `toolkit/certs/` are left out.
- [`mitm-stand/`](mitm-stand/) — the OpenWrt DNS redirect and the nginx stand setup, OTA
  offer, and teardown scripts.
- [`helpers/`](helpers/) — small SSH runners (pty-free, over paramiko), a script to find the
  speaker on any subnet, and so on.

Credentials and the leaked CA private key are not in the repo. The method builds on the
public eQuasar project and the eMudhra CA disclosure, both linked from the field report.
