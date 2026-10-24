# 06 — glagol protocol & local control

**glagol** is Yandex's LAN control protocol: a TLS WebSocket on **:1961**, discovered via
mDNS (`_yandexio._tcp`). This chapter reverses it and turns it into a working tool.

## Read
- **[internals.md](internals.md)** — message envelope, the command set and its **privilege
  tiers** (guest media control vs owner-only `sendText`/`serverAction`), the cloud
  `conversationToken` auth model, the internal bypass commands, and the
  `serverAction → BypassDirectiveHandler::handleDirective` path that executes **any**
  directive (arbitrary TTS, LED, media, IoT).
- **[live-tts.md](live-tts.md)** — the full, validated chain: recover the account OAuth
  token on-device → fetch a `conversationToken` from the backend → send a `serverAction`
  that runs the `repeat_phrase` scenario. The speaker says the exact text.
- **[alice_tts.py](alice_tts.py)** — the tool.

## Use
```bash
pip install websockets
python3 alice_tts.py "Любой текст"          # the speaker says it
python3 alice_tts.py "Громче!" --volume 0.4 # set platform volume first
```
No app login needed: because we are root on the device, the tool pulls the account OAuth
token from the speaker over ADB, requests a fresh `conversationToken`, and sends the
glagol command itself. (All token values are handled at runtime and never stored.)

## Why it matters
This is the end state of the whole project: from a leaked-CA root (chapter 01) to
**arbitrary, authenticated local control of the live assistant** — speech, lights, media,
and smart-home directives — entirely over the LAN.
