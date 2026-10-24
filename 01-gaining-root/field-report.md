# Rooting the Yandex Station Light (`yandexmicro`) from Scratch

## A field report on MITM-ing the Quasar cloud config to enable root ADB

> **Abstract.** We obtained persistent root (`uid=0`) on a Yandex Station Light
> (Quasar platform `yandexmicro`) without flashing any firmware. The device's
> activation flow was redirected, via local DNS, to a self-hosted HTTPS server
> that impersonates `quasar.yandex.net` using a certificate issued from the
> leaked eMudhra/emSign CA material (the public "eQuasar" method). The server
> delivered a config with `adbd.remoteActivation=true`, causing the device to
> self-enable a network `adbd` running as root. Root was then made persistent by
> (1) wrapping the native ADB activation script so that `deactivate` is a no-op,
> and (2) disabling OTA in three independent layers. The final state survives
> reboot without the MITM stand, without DNS hijacking, and across a Wi-Fi
> network migration.
>
> **Key non-obvious finding:** the device's factory firmware (`0.1.1.6`, July
> 2021) is too old to complete activation — it never calls `/get_sync_info`.
> Activation only completed after we offered exactly one OTA update to `.46`
> (2026-10-13), the last build known to still trust the eMudhra chain.

---

## 1. Introduction

This document describes, from zero, how we gained root ADB access to a Yandex
Station Light (the device self-identifies on the network as `yandex-micro`, and
its Quasar platform is `yandexmicro`). The work was performed **on our own
device and inside our own network** as a learning/security-research exercise;
no foreign firmware was flashed and no third-party device was touched.

The public method we built on is **eQuasar** (bitracker), which was originally
validated against the Yandex Station Mini 2 (`yandexmini_2`). A central question
of this exercise was whether the same technique transfers to a *different*
platform (`yandexmicro`), and what breaks along the way. This report focuses on
the investigation process, the failures, and how each was resolved.

---

## 2. Background

### 2.1 Yandex Station and the Quasar backend

Yandex smart speakers run a Linux-based firmware with a service layer called
Quasar. During initial setup the device contacts `quasar.yandex.net` /
`quasar.yandex.ru` / `scbh.yandex.net` to:

1. `POST /register` — bind the device to an account using an activation code,
2. `GET /get_sync_info` — fetch the device configuration,
3. `GET /check_updates` — poll for firmware updates,
4. `GET /glagol/device_list`, `GET /get_timezone`, etc. — smart-home/timezone data.

The `get_sync_info` response contains an `adbd` section with a
`remoteActivation` flag. The real backend can use this to remotely enable ADB on
a device. This is the hook the whole technique exploits.

### 2.2 The eMudhra CA leak and eQuasar

The device firmware's trust store (`/system/vendor/quasar/ca-certificates.crt`)
contains eMudhra/emSign roots cross-signed by the public "AAA Certificate
Services" root. The private keys of the eMudhra intermediate CAs leaked (the
"eQuasar" set). This makes it possible to mint a leaf certificate for
`quasar.yandex.net` that the device will accept as genuine.

The public repository **eQuasar** (`git.gay/iwakura/eQuasar`) packages exactly
this: an nginx stand plus `fullchain.pem` / `quasar-all.key`. A repack with a
safer persistence tool is **hu553in/yandex-station-root** (`persistence.py`).

### 2.3 Threat model / scope

- Attacker (us) controls the LAN router and a computer on the same network.
- We redirect the three Quasar hostnames to our stand and block voice/streaming
  hostnames during setup only.
- Everything is reversible; the stand is torn down at the end.

---

## 3. Reconnaissance

### 3.1 Environment

| Object | Value |
|---|---|
| Computer | macOS 15.8.1 (Apple Silicon), initially `192.168.50.218` (en0), later `192.168.1.79` |
| Router | OpenWrt `25.12.6` (mediatek/filogic), LAN `192.168.50.1`, WAN `192.168.1.101`, upstream gateway/DNS `192.168.1.254` |
| Target device | hostname `yandex-micro`, MAC `[REDACTED-MAC]`, initially `192.168.50.163`, later `192.168.1.80` |
| Stand cert | `CN=quasar.yandex.net`, issuer `EM OV TLS CA - G3C` (eMudhra), valid to `2029-01-22` |

### 3.2 Initial findings

- **The target is `yandexmicro`, not `yandexmini_2`.** The firmware archive
  (`144.76.194.29:62891`) lists `yandexmicro/` as a distinct platform. The
  public method is only validated for `yandexmini_2`. This was the primary
  unknown.
- **The router was already half-configured** by a previous attempt:
  - a `force-station-dns` DNAT rule (forced the device's DNS through the router),
  - `local=/quasar.yandex.../` entries in `/etc/dnsmasq.conf` (which resolve
    Quasar to NXDOMAIN — *not* what we want),
  - stale DHCP reservations `yandexmini2` / `infosec` pointing at a foreign
    subnet (`192.168.1.x`), copied verbatim from the Mini 2 guide,
  - an inactive static route `0.0.0.0/0 via 192.168.50.223`.
- **Sandbox constraints on the operator side:** `sudo` is blocked, there is no
  Docker, no nginx, and `brew` cannot write to `/opt/homebrew`. This shaped the
  whole stand-deployment strategy.

---

## 4. Tooling

- **eQuasar** certs: `fullchain.pem` (leaf + `EM OV TLS CA - G3C`) and
  `quasar-all.key` (2048-bit RSA).
- **hu553in/yandex-station-root**: `persistence.py` — a careful, idempotent
  ADB-guard / OTA-off installer with format validation and backups.
- On the Mac: `adb`, `curl`, `dig`, `openssl`, `nginx` (Homebrew),
  Python 3.12 + `paramiko` (for password SSH to the router without a pty).

---

## 5. Implementation and the failures along the way

### 5.1 Router access (failure #1: pty)

First attempt to drive the router used `expect` for password SSH. It failed with
`The system has no more ptys` (the sandbox does not allocate pseudo-terminals).

**Fix:** switch to Python `paramiko`, which runs commands over the SSH channel
directly without a local pty. Two helpers were written: `rssh.py` (run a single
command) and `rrun.py` (upload a script over SFTP and run it).

### 5.2 The stand (failure #2: no sudo / no docker / no nginx)

`sudo` is blocked, there is no Docker, and `brew install nginx` cannot write to
`/opt/homebrew` inside the sandbox.

**Fix:** prepare everything (certs, config, self-check) and hand the user a
root script (`stand-setup.sh`) to run as `sudo bash stand-setup.sh` on the Mac.
The operator does all the *content*, the user supplies the *privilege*.

The certs were fetched directly through the Gitea API (a full `git clone` of
`git.gay` stalled and was killed). The certificate was verified:

```
subject=CN=quasar.yandex.net
issuer=EM OV TLS CA - G3C (eMudhra)
notAfter=2029-01-22
SAN: quasar.yandex.net, *.quasar.yandex.net, scbh.yandex.net,
     rpc.alice.yandex.net, uniproxy.alice.yandex.net, strm.yandex.ru, ...
```

The final nginx `/get_sync_info` returns `adbd` in **both** config paths
(`config.adbd` and `config.system_config.adbd`) with
`fullDurationMs=31536000000`, and the proxying `location /` carries
`resolver 8.8.8.8 1.1.1.1;` (otherwise every proxied request 502s).

### 5.3 Stand first check (failure #3: "Empty reply")

The first curl to `/get_sync_info` returned "Empty reply from server".

**Diagnosis:** nginx was still restarting (the setup script does
`nginx -s stop; nginx`), and an `nc` probe logged a single `400`.
**Fix:** wait and re-test — `/get_sync_info` → 200 (307 bytes),
`/check_updates` → `{"hasUpdate":false}`, `/generate_204` → 204, `/` → 404 from
the real Quasar through the proxy.

### 5.4 Router DNS

Replaced the wrong `local=` entries with `address=`:

```
address=/quasar.yandex.net/192.168.50.218
address=/quasar.yandex.ru/192.168.50.218
address=/scbh.yandex.net/192.168.50.218
address=/strm.yandex.ru/127.0.0.1
address=/strm.yandex.net/127.0.0.1
address=/rpc.alice.yandex.net/127.0.0.1
address=/uniproxy.alice.yandex.net/127.0.0.1
address=/alice.yandex.net/127.0.0.1
address=/alice-ats.yandex.net/127.0.0.1
address=/alice-ats-test.yandex.net/127.0.0.1
```

Disabled the `force-station-dns` DNAT (`enabled=0`) at the operator's request,
and removed the stale `yandexmini2`/`infosec` reservations.

### 5.5 Factory reset — activation starts, then stalls (failure #4)

After a factory reset and re-setup through the "House with Alice" app, the
stand log showed:

```
POST /register?...&platform=yandexmicro&firmware=0.1.1.6...factory  -> 200 (51 B)
GET  /check_updates?...&platform=yandexmicro                        -> 200 (19 B)
```

- ✅ The eMudhra certificate **was accepted** (register completed over TLS).
  So the method transfers to `yandexmicro`.
- ❌ `GET /get_sync_info` **never arrived**. The device looped on
  `/check_updates` every ~90 s and did nothing else.

### 5.6 Diagnosis of the stall

**False lead:** the device held a direct TLS connection to `87.250.251.227:443`.
We suspected a hardcoded IP bypass. Probing the real server showed it serves
`*.oauth.yandex.ru` — i.e., ordinary Yandex OAuth token exchange, which we are
not supposed to intercept. Red herring.

**Real cause:** the request carried `firmware=0.1.1.6...factory` — a build from
July **2021**. That factory firmware is too old to finish activation: it never
calls `/get_sync_info` and instead polls `/check_updates`, waiting for an update
that our own `hasUpdate:false` shield was suppressing. This matches the known
behavior in the eQuasar fork: *factory recovery needs one OTA update before
activation completes*.

### 5.7 The OTA-offer pivot

We switched `/check_updates` to serve exactly one offer — `yandexmicro`
`0.369.1.46.4778262442.20261013.297` (2026-10-13), the last build known to still
trust the eMudhra chain (newer `.50`/`.372` removed it):

```json
{"hasUpdate":true,"version":"0.369.1.46.4778262442.20261013.297",
 "downloadUrl":"https://cdn...svc.cdn.yandex.net/yandexmicro/ota/user/.../0.369.1.46....zip",
 "crc32":371630625,"critical":true,
 "fallbackUrl":"https://quasar.s3.yandex.net/yandexmicro/ota/user/...",
 "fallbackIp":"93.158.134.158","updateId":"150484"}
```

The device picked up the offer (452 B response instead of 19 B), downloaded
`update.zip` from the real Yandex CDN (~67 MB observed in conntrack and growing),
installed it, and rebooted.

### 5.8 Root obtained

On `.46` the device completed activation, and the log finally showed the
decisive line:

```
GET /get_sync_info?device_id=...&platform=yandexmicro&version=0.369.1.46...  -> 200 (307 B)
```

Then:

```
adb connect 192.168.50.163:5555
adb shell id   -> uid=0(root) gid=0(root)
```

The activation markers `activate_adb_quasmodrom` and `activate_network_adb`
appeared in `/data/quasar/`.

The device subsequently self-updated from `.46` to `.50` (updatesd bypasses DNS
via direct IPs), but the markers live in `/data` and survived the system-partition
change — root kept working on `.50`.

### 5.9 Persistence (failures #5 and #6)

Used `persistence.py` (fortress + OTA-off, with validation and backups).

- **Failure #5 — `mktemp`:** `install-adb` failed because `/data/local/tmp`
  does not exist on `yandexmicro` (the tool assumed Mini 2).
  **Fix:** `adb shell mkdir -p /data/local/tmp`, then retry.

- **Failure #6 — remount:** `disable-updates` failed with
  `mount: mounting ubi0:rootfs on / failed: Device or resource busy`.
  **Diagnosis:** the root filesystem is UBIFS and is already mounted `rw`;
  remounting it fails with EBUSY. Crucially, `launch.json` **had already been
  modified** (the `updatesd` task removed) and the backup
  `launch.root_original.json` written — only the cleanup remount failed.
  **Fix:** verify the on-device result (it was correct) and move on.

Final persistence state — **three independent OTA-off layers plus the ADB guard:**

| Component | Change | Original backup |
|---|---|---|
| `activate_adb.sh` | wrapper: `deactivate` → no-op, `activate` → always `--network` | `activate_adb.root_original.sh` |
| `launch.json` | `updatesd` task removed | `launch.root_original.json` |
| `device_ota_update.sh` | replaced with `#!/bin/sh` + `exit 0` | `device_ota_update.root_original.sh` |
| `ota_script.pub` | replaced with a freshly generated RSA key | `ota_script.root_original.pub` |

Verification: `ADB guard installed`, `OTA disabled in launcher configuration`,
markers present, and no `updatesd` process after reboot.

### 5.10 Autonomous verification

Removed the router DNS hijack (`quasar.yandex.net` → `213.180.193.230` again),
and rebooted the device **without the stand and without DNS hijacking**.
Result: `uid=0(root)` persisted.

### 5.11 Network migration

The computer moved to the `192.168.1.0/24` network (`192.168.1.79`) and the old
OpenWrt router became unreachable. The device was re-located on the new network
by MAC (`[REDACTED-MAC]`) and by the open ADB port 5555: **`192.168.1.80`**.
Root survived the network change.

---

## 6. Failures → resolutions (summary)

| # | Failure | Root cause | Resolution |
|---|---|---|---|
| 1 | `expect` can't allocate pty | sandbox has no ptys | Python `paramiko` |
| 2 | `sudo`/Docker/nginx unavailable | sandbox writes only to workspace | root script run by the user |
| 3 | "Empty reply from server" | nginx still restarting | wait, re-test |
| 4 | no `/get_sync_info` after register | factory `0.1.1.6` (2021) too old to activate | offer one OTA update to `.46` |
| 5 | suspected hardcoded IP bypass | it was `*.oauth.yandex.ru` (OAuth) | ignore (red herring) |
| 6 | `install-adb` fails on `mktemp` | no `/data/local/tmp` | `mkdir -p /data/local/tmp` |
| 7 | `disable-updates` fails on remount | UBIFS already `rw`, remount → EBUSY | verify actual result (it applied) |
| 8 | user typo `192.168.80.1` + `adb shell <ip>` | wrong IP + wrong adb order | `adb connect` first, then `adb shell` |

---

## 7. Results

- Root shell: `uid=0(root) gid=0(root)`.
- Firmware at the end: `0.369.1.50.4794655315.20261021.297`.
- ADB guard active; OTA disabled (launcher task removed + update script no-op +
  signing key replaced).
- Root survives: reboot without the stand, without DNS hijacking, and after a
  Wi-Fi network migration.

---

## 8. Discussion

### Why root survives

- **Markers** in `/data/quasar/` (`activate_adb_quasmodrom`,
  `activate_network_adb`) are read by `onboot.sh` at every boot, which starts a
  network `adbd` on `:5555` as root. `/data` is userdata, so it survives power
  cycles and OTA (the system partition changes; `/data` does not).
- **The fortress wrapper** makes the `deactivate` path a no-op, so a later cloud
  config without `remoteActivation` cannot turn ADB off.
- **OTA-off** blocks the updater three ways, preventing a future update from
  replacing the guard.

### Limitations / caveats

- The device ended on `.50`, which **rejects** the eMudhra chain. A factory
  reset would wipe `/data/quasar/` and could not be re-activated with this
  method on `.50` — it would require rolling the firmware back to `.46`.
- Network ADB on this firmware has **no authentication**; keep port 5555 inside
  a trusted LAN.
- The `.46` offer URL/hash came from a community firmware archive and was
  served as a real Yandex CDN download; the proxy did not host any ZIP.

---

## 9. Conclusion

The eQuasar technique transfers from `yandexmini_2` to `yandexmicro`, with one
important caveat: a 2021 factory firmware will not activate until it receives
one OTA update to a still-trusting build (`.46`). The main engineering
challenges were environmental (sandbox/pty/sudo), the stale factory firmware
stall, and two UBIFS-specific quirks in the persistence tool. The result is a
persistent, OTA-resistant root shell obtained entirely in software on our own
device.

---

## 10. References

- eQuasar — <https://git.gay/iwakura/eQuasar>
- hu553in/yandex-station-root (repack with `persistence.py`) — <https://github.com/hu553in/yandex-station-root>
- eMudhra CA disclosure ("Fluepke's disclosure") — <https://github.com/Fluepke/emudrahahahahaha>
- Yandex Station firmware archive — <http://144.76.194.29:62891/>
- News coverage of the Mini 2 root — <https://habr.com/ru/news/1097812/>

---

## Appendix A — Key commands

```bash
# locate + connect (auto, any network)
cd ~/алиса && ./find-alisa.sh

# manual
adb connect <IP>:5555
adb shell id                       # uid=0(root) gid=0(root)
adb shell cat /system/vendor/quasar/version_full

# persistence status
./.venv/bin/python yandex-station-root/persistence.py --adb adb --serial <IP>:5555 status
```

## Appendix B — The `.46` update offer (yandexmicro)

```json
{
  "hasUpdate": true,
  "version": "0.369.1.46.4778262442.20261013.297",
  "downloadUrl": "https://cdnriqbxswemmatxzibl.svc.cdn.yandex.net/yandexmicro/ota/user/770338e8-a517-4642-a442-d26be2632873/0.369.1.46.4778262442.20261013.297.zip",
  "crc32": 371630625,
  "critical": true,
  "fallbackUrl": "https://quasar.s3.yandex.net/yandexmicro/ota/user/770338e8-a517-4642-a442-d26be2632873/0.369.1.46.4778262442.20261013.297.zip",
  "fallbackIp": "93.158.134.158",
  "updateId": "150484"
}
```

## Appendix C — Rollback

```bash
# restore ADB script and OTA launcher (backups live on the device)
./.venv/bin/python yandex-station-root/persistence.py --adb adb --serial <IP>:5555 restore-adb
./.venv/bin/python yandex-station-root/persistence.py --adb adb --serial <IP>:5555 restore-updates

# restore device_ota_update.sh and ota_script.pub from on-device backups
adb shell 'cd /system/vendor/quasar && cp device_ota_update.root_original.sh device_ota_update.sh && cp ota_script.root_original.pub ota_script.pub'
```
