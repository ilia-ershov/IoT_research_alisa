# 03 — Reversing the Quasar platform (`maind`)

The whole assistant is one 21 MB, stripped, 32-bit ARM binary: `maind`. Every daemon is the
same binary started in a different mode (`--platformd`, `--mediad`, `--telemetry`,
`--fluent-bitd`, and symlinks like `quasar_client`, `metrics_collector`, `led_util`). I
pulled it off the device and read it in IDA Pro.

## What to read
- [binary-analysis.md](binary-analysis.md) — the first pass: what the binary is, its
  dependencies (TFLite, the VQE audio library, BoringSSL, avahi), the service layout, and the
  directive protocol baked into it.
- [directives-and-ipc.md](directives-and-ipc.md) — the directive protocol: how TTS works
  (`handleVocalizeDirective`), how text input is routed, the `quasar_client` IPC format, and
  the service-to-port map.
- [re-findings.md](re-findings.md) — the glagol token functions and where the TLS pinning
  lives.
- [ida-setup.md](ida-setup.md) — how IDA Pro and `ida-pro-mcp` were set up, and the
  practical snags (a per-call time limit, worked around by computing string addresses on the
  host; raising the timeout for large functions).

## Worth noting
The cloud side runs over UniProxy (`wss://uniproxy.alice.yandex.net`), and the binary carries
the full directive/event vocabulary plus protobuf descriptors. The cloud transport is pinned
(BoringSSL public-key pinning), so capturing that traffic needs a pinning bypass — located
here, not weaponized.
