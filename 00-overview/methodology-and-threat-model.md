# Methodology, threat model & timeline

## Goal
Take a retail **Yandex Station Lite** from no privileged access to a complete
understanding of its software — and demonstrate concrete local control — using only a LAN
foothold and the device itself.

## Threat model
- **Attacker position:** control of the local router and one host on the same LAN. No
  physical disassembly, no JTAG/serial soldering, no firmware flashing of foreign images.
- **Trust anchor abused:** the device's firmware trust store still contains eMudhra/emSign
  roots whose intermediate keys leaked publicly ("eQuasar"). That lets a local server
  present a certificate the device accepts for `quasar.yandex.net`.
- **Everything reversible:** DNS hijack and the MITM stand are torn down at the end; the
  device keeps working on the real cloud afterwards.

## Phases
1. **Gain root** — redirect the Quasar activation hostnames via router DNS to a local
   HTTPS stand; serve a `get_sync_info` with `adbd.remoteActivation=true`; pivot one OTA to
   a still-trusting build so a 2021 factory image can activate; make root persistent.
   → [`01-gaining-root/`](../01-gaining-root/)
2. **Recon / dossier** — enumerate hardware, partitions, filesystem, services and the local
   + cloud endpoints. → [`02-device-dossier/`](../02-device-dossier/)
3. **Reverse the platform** — pull `maind` and analyse it in IDA Pro (driven through an MCP
   bridge): service mesh, the Alice directive protocol, audio, IPC.
   → [`03-reversing-quasar/`](../03-reversing-quasar/)
4. **Telemetry & privacy** — determine exactly what is collected, stored, and sent, under
   what conditions, and whether the device records the user.
   → [`04-telemetry-and-privacy/`](../04-telemetry-and-privacy/)
5. **Subsystems** — audio (and how to make it speak) and the LED ring format.
   → [`05-audio-and-led/`](../05-audio-and-led/)
6. **Local control** — reverse the glagol LAN protocol and build a tool that makes the live
   assistant speak arbitrary text. → [`06-glagol-protocol/`](../06-glagol-protocol/)

## Two investigation tracks, merged
This repo consolidates two parallel efforts on the same unit: the **rooting campaign**
(cloud-config MITM, chapter 01 + the dossier) and the **post-root reverse engineering**
(chapters 03–06, IDA + glagol). Together they form one narrative: *get in → understand
everything → control it locally.*

## A note on tooling constraints
The operator host was sandboxed (no `sudo`/Docker/pty in places), and the target is a
stripped BusyBox/armhf system with **no on-device debugger** (`strace`/`gdb`/`tcpdump`
absent). Reversing therefore relied on pulling artifacts to the host and on IDA; string
virtual addresses were computed locally (image base 0) to work around an MCP per-call time
limit. These constraints — and how each was worked around — are part of the write-ups.
