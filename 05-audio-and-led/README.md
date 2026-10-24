# 05 — Audio and LED

## What to read
- [audio.md](audio.md) — the audio path (four mics → VQE → TFLite spotter → UniProxy;
  playback through `mediad`/GStreamer → ALSA → the TAS5825M amp), the two separate volume
  controls, and how to make the speaker play or say something.
- [led.md](led.md) — the three-LED ring, `led_util`, and the `.led` pattern file format
  (each frame is three `RRGGBB` values plus a duration, with `loop`/`gammacorrection` flags).
  The `ledconfigs/*.json` files are 3×3 colour-correction matrices, not a palette.

## Worth noting
There are two ways to get sound out: push raw audio straight to the amp with `aplay`, or
drive the real assistant (that's chapter 06). A sample pattern — the breathing animation
Alice shows while speaking — is at [`../artifacts/alice_speaking.led`](../artifacts/alice_speaking.led).
