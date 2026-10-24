# Yandex Station Lite — security research

A writeup of taking apart a Yandex Station Lite (the small Alice speaker) on my own
network: getting root, reading the firmware in a disassembler, working out what the
telemetry actually sends, and ending up able to drive the assistant over the local network.

Everything here was done on a device I own, on my own LAN, as a learning project. It is not
affiliated with Yandex. Live secrets — account tokens, the Wi-Fi password, and the leaked
CA key used for rooting — are kept out of the repo (see the note at the end).

## How it went

Three parts, roughly in the order I did them.

**Getting root** ([chapter 01](01-gaining-root/)). No flashing, no soldering. The firmware
still trusts a set of eMudhra CA certificates whose private keys leaked a while ago, so a
machine on the same network can present a valid-looking certificate for
`quasar.yandex.net`. Point the speaker's DNS at that machine, answer its config request
with `remoteActivation` turned on, and the device starts a root ADB server by itself. The
one real snag: a 2021 factory build won't finish setup until it is offered a single OTA
update, so I had to serve exactly one.

**Reading the platform** ([chapter 03](03-reversing-quasar/)). The whole assistant is one
21 MB binary, `maind` — every daemon is the same binary started in a different mode. I
pulled it off the device and worked through it in IDA Pro.

**Telemetry, privacy and control** (chapters [04](04-telemetry-and-privacy/)–[06](06-glagol-protocol/)).
What the device records and sends, and when. The audio and LED subsystems, including how to
make it play or say something. And the "glagol" LAN protocol, which I reversed far enough to
make the live assistant speak arbitrary text over Wi-Fi.

![Attack and research chain](assets/attack-chain.svg)

## The device

| | |
|---|---|
| Model | Yandex Station Lite — Quasar platform `yandexmicro` |
| OS | Buildroot Linux (BusyBox), kernel 4.9.68 aarch64. Not Android. |
| SoC / amp | Amlogic (quad-core) / TAS5825M |
| Userland | 32-bit ARM (armhf) on a 64-bit kernel |
| Core | `maind` (21 MB), the whole Quasar platform, built from Yandex's Arcadia |

## Repository

| Chapter | What's in it |
|---|---|
| [01-gaining-root](01-gaining-root/) | How root was obtained: the [field report](01-gaining-root/field-report.md), the Russian [writeup](01-gaining-root/writeup-ru.md), the MITM [toolkit](01-gaining-root/toolkit/) and [stand scripts](01-gaining-root/mitm-stand/). |
| [02-device-dossier](02-device-dossier/) | Hardware, flash layout, [filesystem](02-device-dossier/filesystem.md) and [endpoints](02-device-dossier/endpoints.md). |
| [03-reversing-quasar](03-reversing-quasar/) | `maind` [binary analysis](03-reversing-quasar/binary-analysis.md), the [directive/IPC protocol](03-reversing-quasar/directives-and-ipc.md), and the [IDA setup](03-reversing-quasar/ida-setup.md). |
| [04-telemetry-and-privacy](04-telemetry-and-privacy/) | What the [telemetry](04-telemetry-and-privacy/telemetry.md) does, and the [privacy](04-telemetry-and-privacy/privacy.md) question answered with evidence. |
| [05-audio-and-led](05-audio-and-led/) | The [audio stack](05-audio-and-led/audio.md) and the [LED](05-audio-and-led/led.md) subsystem and file format. |
| [06-glagol-protocol](06-glagol-protocol/) | The [glagol protocol](06-glagol-protocol/internals.md), the [TTS chain](06-glagol-protocol/live-tts.md), and [`alice_tts.py`](06-glagol-protocol/alice_tts.py). |
| [00-overview](00-overview/) | Methodology and threat model. |

![System architecture](assets/architecture.svg)

## A few things worth pointing out

- The network ADB is open to anyone on the LAN and runs as root. On this unit the rooting
  also keeps it pinned open.
- `root` has no password at all, and there is a login prompt on the serial console.
- The Wi-Fi password and the account's OAuth tokens are stored in the clear on the device.
- The telemetry is operational only — connectivity, Wi-Fi events, system metrics, directive
  names. No audio, no transcripts. It does tag every batch with the Wi-Fi network name and
  the account id, though, and there is no opt-out on the device.
- Wake-word detection runs locally; audio only leaves the device after activation, and the
  short buffers it keeps are encrypted in RAM. So it is not quietly recording you.
- With an owner token, one glagol message makes the speaker run any assistant directive:
  speech, lights, media, smart-home.

The full severity-rated list is in [SECURITY_FINDINGS.md](SECURITY_FINDINGS.md).

## Tools

`adb`, IDA Pro 9.4 (driven through `ida-pro-mcp`), Python (`websockets`, `paramiko`), and an
`openssl`/`nginx` MITM stand. The target is a stripped BusyBox/armhf system with no
on-device debugger, so almost everything was pulled to the host and analysed there. The two
scripts worth keeping are in [`tools/`](tools/).

## Redaction and ethics

This repo documents how things work, not a way to attack other people's speakers. Removed or
redacted: the account OAuth/x-tokens and the glagol `conversationToken`, the Wi-Fi password
and SSID, the device serial / MAC / account id, and the leaked eMudhra CA private key (the
public eQuasar project is cited instead). Network ADB on this firmware has no
authentication, so keep port 5555 on a network you trust.

## License

MIT — see [LICENSE](LICENSE). My own device; not affiliated with Yandex.
