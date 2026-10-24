# 05 — Audio & LED subsystems

## Read
- **[audio.md](audio.md)** — the audio stack (4-mic array → VQE → TFLite spotter →
  UniProxy; playback via `mediad`/GStreamer → ALSA → TAS5825M), the two independent volume
  controls, and **how to make the speaker emit sound** (direct WAV via `aplay`, and live
  assistant speech).
- **[led.md](led.md)** — the 3-LED ring, `led_util`, and the **`.led` pattern file
  format** (per-frame `RRGGBB ×3 + duration_ms`, `loop`/`gammacorrection` flags);
  `ledconfigs/*.json` are 3×3 colour-correction matrices.

## Highlights
- Making Alice talk splits into two mechanisms: inject arbitrary PCM to the amp locally
  (`aplay`), or drive the real assistant (see chapter 06 for the glagol TTS exploit).
- A sample pattern is in [`../artifacts/alice_speaking.led`](../artifacts/alice_speaking.led)
  — the breathing animation Alice shows while speaking.
