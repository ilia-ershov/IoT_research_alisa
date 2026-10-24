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

- **`glagol_client.py`** — a general client for the whole reverse-engineered glagol command
  set (not just TTS):

  ```bash
  python3 glagol_client.py status            # one state snapshot (now-playing, volume, ...)
  python3 glagol_client.py monitor --seconds 30
  python3 glagol_client.py ping
  python3 glagol_client.py volume 0.3
  python3 glagol_client.py play|pause|stop|next|prev
  python3 glagol_client.py say "Любой текст" [--volume 0.3]
  ```

  Same runtime token recovery as `alice_tts.py`. Demonstrates the privilege tiers from the
  protocol chapter (owner-only `say`; low-priv media/volume/`ping`; read-only state).
