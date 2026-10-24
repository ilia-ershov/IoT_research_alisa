# Security findings register — Yandex Station Lite

Consolidated findings from this research, most-severe first. Severity is a qualitative
rating for a **LAN-local** threat model (attacker on the same network; see
[`00-overview/`](00-overview/methodology-and-threat-model.md)). Each finding links to the
chapter with the evidence.

| ID | Finding | Severity | Component |
|----|---------|----------|-----------|
| F-01 | Unauthenticated network ADB running as root | 🔴 Critical | ADB / `adbd` |
| F-02 | Empty `root` password + serial `getty` | 🔴 Critical | OS auth |
| F-03 | No SELinux/MAC; every Quasar daemon runs as root | 🟠 High | OS hardening |
| F-04 | Secrets stored in cleartext at rest | 🟠 High | `/data/quasar` |
| F-05 | Cloud-config trust via leaked CA → MITM root (eQuasar) | 🟠 High | OTA/activation trust |
| F-06 | glagol `serverAction` → arbitrary directive execution | 🟠 High | glagol :1961 |
| F-07 | glagol low-privilege commands over LAN | 🟡 Medium | glagol :1961 |
| F-08 | Telemetry fingerprint (Wi-Fi SSID + account UID); no opt-out; remotely retunable | 🟡 Medium (privacy) | telemetry |
| F-09 | Bluetooth "Just-Works" pairing (no MITM protection) | 🔵 Low | Bluetooth |
| F-10 | TLS public-key pinning to the cloud (**control, positive**) | ✅ Strength | transport |

---

### F-01 — Unauthenticated network ADB as root  🔴
`adbd` listens on `0.0.0.0:5555` with no `/adb_keys` and no confirmation prompt; `adb
connect` yields `uid=0` from anywhere on the LAN. On this unit it is also pinned open by
the rooting persistence (see F-05). **Impact:** full device takeover from the LAN.
**Remediation:** disable network ADB; if required, require authorized keys and bind to a
trusted host; segment IoT onto its own VLAN. → [03](03-reversing-quasar/) / [01](01-gaining-root/)

### F-02 — Empty root password + serial getty  🔴
`/etc/shadow` has `root::::::::`; a `getty` runs on the serial console. **Impact:** instant
root over UART and trivial privilege assumptions anywhere. **Remediation:** set a strong
`root` password (or disable interactive root), disable the console getty in production.
→ [02](02-device-dossier/)

### F-03 — No MAC; daemons run as root  🟠
No SELinux/AppArmor; `maind` (`--platformd/--mediad/--telemetry/...`) and helpers all run
as root. **Impact:** any memory-safety bug in the assistant is a root bug; no
compartmentalization. **Remediation:** drop privileges per service; apply a MAC policy.
→ [03](03-reversing-quasar/)

### F-04 — Cleartext secrets at rest  🟠
`wifi.dat` holds the Wi-Fi SSID + PSK in cleartext; `account_storage.dat` holds the account
OAuth token, an x-token, and the Passport UID; `user_config.dat` embeds the UID and config.
Directories are mode 777. **Impact:** a read primitive (or root) leaks the home Wi-Fi
password and account tokens. **Remediation:** store credentials in the TEE/keystore
(the device already has OP-TEE/keymaster); restrict permissions. → [03](03-reversing-quasar/) / [04](04-telemetry-and-privacy/)

### F-05 — Cloud-config trust via a leaked CA (ecosystem)  🟠
The firmware trust store still trusts eMudhra/emSign roots whose intermediate keys leaked.
A LAN attacker can impersonate `quasar.yandex.net`, serve `get_sync_info` with
`adbd.remoteActivation=true`, and make the device enable root ADB on itself — then persist
by neutering the ADB-deactivate path and OTA. **Impact:** software-only persistent root.
**Remediation (vendor):** remove the compromised roots (newer builds `.50`/`.372` already
do), pin the activation endpoint, sign the config payload. → [01](01-gaining-root/field-report.md)

### F-06 — glagol `serverAction` → arbitrary directive execution  🟠
With a valid owner `conversationToken`, a glagol `serverAction` carries a VINS
`server_action` that is turned into a native directive via
`BypassDirectiveHandler::handleDirective` — enabling arbitrary TTS, LED, media and IoT
directives. **Impact:** a LAN peer holding an owner token fully drives the assistant
(demonstrated: arbitrary speech). **Remediation:** constrain which directives may originate
locally; treat the local channel as untrusted. → [06](06-glagol-protocol/)

### F-07 — glagol low-privilege commands over LAN  🟡
A limited-state connection still accepts `ping, softwareVersion, setVolume, play, stop,
next, prev, rewind, shuffle, repeat, playMusic, playRadio`, plus the device streams
now-playing metadata (track/artist/cover/playlist). **Impact:** nuisance control and
listening-habit disclosure to LAN peers. **Remediation:** authenticate all commands; don't
broadcast rich now-playing on the local channel. → [06](06-glagol-protocol/)

### F-08 — Telemetry fingerprint & remote control  🟡 (privacy)
Every telemetry batch carries a device/environment fingerprint including the **current
Wi-Fi SSID** and the **account UID**; there is no on-device opt-out (`appmetrica.mode:black`
with an empty blacklist), and the backend can retune sampling at runtime
(`config_capability.statisticSampeRate`). No audio/transcripts are collected; a configurable
~1 % "very-rare" spotter sample logs ~5 s of audio. **Impact:** home-network and account
correlation. **Remediation:** expose an opt-out; drop SSID from analytics. → [04](04-telemetry-and-privacy/)

### F-09 — Bluetooth Just-Works pairing  🔵
A `just-works` BlueZ agent pairs without MITM protection. **Impact:** opportunistic local
pairing. **Remediation:** require confirmation/numeric comparison. → [02](02-device-dossier/)

### F-10 — TLS public-key pinning  ✅ (positive)
`maind` pins cloud server public keys (BoringSSL; `"SSL public key does not match pinned
public key"`). This is a genuine control: passive cloud-traffic interception requires a
pinning bypass (binary patch / instrumentation), which this research located but did not
weaponize. → [03](03-reversing-quasar/)

---

> Findings concern a single owner-operated unit and the general platform design; they are
> documented for defensive and educational value. Network ADB on this firmware is
> unauthenticated — keep port 5555 on a trusted LAN.
