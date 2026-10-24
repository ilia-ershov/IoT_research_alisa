# tools/

- **`alice_tts.py`** — make the live Alice speak arbitrary text over the glagol LAN
  protocol. Self-contained: it pulls the account OAuth token from the device over ADB
  (root), requests a `conversationToken` from the Quasar backend, and sends a
  `serverAction`/`repeat_phrase` command to `wss://<speaker>:1961`.

  ```bash
  pip install websockets
  python3 alice_tts.py "Любой текст" [--volume 0.3] [--adb <ip:5555>] [--ip <speaker-ip>]
  ```

  See [`../06-glagol-protocol/`](../06-glagol-protocol/) for the protocol internals and the
  full exploit chain. No token values are persisted.
