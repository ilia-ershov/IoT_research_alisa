# 03 — Reversing the Quasar platform (`maind`)

The entire assistant is one 21 MB, stripped, 32-bit ARM binary — `maind` — built from
Yandex's Arcadia monorepo. Every daemon is the same binary in a different mode
(`--platformd`, `--mediad`, `--telemetry`, `--fluent-bitd`, and `argv[0]` symlinks like
`quasar_client`, `metrics_collector`, `led_util`). This chapter reverses it in IDA Pro.

## Read
- **[binary-analysis.md](binary-analysis.md)** — first-pass: ELF profile, dependencies
  (TFLite, VQE, BoringSSL, avahi), the service mesh, and the embedded Alice
  directive/event vocabulary.
- **[directives-and-ipc.md](directives-and-ipc.md)** — the directive protocol: the TTS
  path (`handleVocalizeDirective`), text input (`quasar_voice_service_impl`), the
  `quasar_client` IPC envelope (base64 protobuf + reflection), and the service→port map.
- **[re-findings.md](re-findings.md)** — glagol token model (the `/glagol/token` and
  `check_token` functions) and the cert-pinning location.
- **[ida-setup.md](ida-setup.md)** — how IDA Pro 9.4 + `ida-pro-mcp` were wired up for
  agent-driven RE, and the practical workarounds (per-call time limit → local VA
  computation at image base 0; raising the tool timeout for big functions).

## Highlights
- Cloud control plane is **UniProxy** (`wss://uniproxy.alice.yandex.net`); the binary
  carries the full `…DirectiveType` / `…EventType` set and protobuf reflection descriptors.
- Transport is pinned (BoringSSL public-key pinning) → passive cloud interception needs a
  pinning bypass (feasible with root).
- The directive dispatch + glagol live in exception-heavy regions IDA doesn't always
  auto-define as functions; reversing used string/data anchors and targeted decompiles.
