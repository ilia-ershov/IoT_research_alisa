# 06 — glagol and local control

glagol is Yandex's LAN control protocol: a TLS WebSocket on :1961, found over mDNS
(`_yandexio._tcp`). This is where the research ends up — reversing the protocol and turning
it into a small tool.

## What to read
- [internals.md](internals.md) — the message format, the command set and which commands need
  an owner token versus which a guest can send, how the `conversationToken` is checked, the
  internal bypass commands, and the `serverAction` path that lets one message run any
  assistant directive (speech, LED, media, smart-home).
- [live-tts.md](live-tts.md) — the full chain: pull the account OAuth token off the device,
  get a `conversationToken` from the backend, and send a `serverAction` that runs the
  `repeat_phrase` scenario. The speaker then says the exact text.
- [`../tools/alice_tts.py`](../tools/alice_tts.py) — the tool.

## Running it
```bash
pip install websockets
python3 ../tools/alice_tts.py "Любой текст"
python3 ../tools/alice_tts.py "Громче!" --volume 0.4
```
No app login needed. Because we're root on the device, the tool pulls the account token off
the speaker over ADB, asks the backend for a `conversationToken`, and sends the glagol
message itself. Token values stay in memory only.

For the rest of the commands — status, media, volume, not just TTS — see
[`../tools/glagol_client.py`](../tools/glagol_client.py).
