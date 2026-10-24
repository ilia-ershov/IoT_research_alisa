#!/usr/bin/env python3
"""
glagol_client.py — a general client for the Yandex Station glagol LAN protocol
(TLS WebSocket on :1961), reverse-engineered in this project.

It covers the command set and privilege tiers documented in
06-glagol-protocol/internals.md:
  - owner-only : say (serverAction/repeat_phrase)
  - low-priv   : volume, play/pause/stop/next/prev/rewind/shuffle/repeat, ping
  - read       : status (one state snapshot), monitor (stream states)

The conversationToken is obtained the same way as alice_tts.py: the account OAuth
token is pulled from the device over ADB (we are root), a conversationToken is
requested from the Quasar backend, and commands are sent to the speaker. No token
value is ever written to disk.

Deps:  pip install websockets
Usage:
  python3 glagol_client.py status
  python3 glagol_client.py monitor --seconds 30
  python3 glagol_client.py ping
  python3 glagol_client.py volume 0.3
  python3 glagol_client.py play | pause | stop | next | prev
  python3 glagol_client.py say "Любой текст" [--volume 0.3]
Options: --adb <ip:5555>  --ip <speaker-ip>  --port 1961
"""
import argparse, asyncio, json, ssl, subprocess, sys, tempfile, os, time, uuid

BACKEND = "https://quasar.yandex.net"

# ---------- token recovery (ADB + backend) ----------
def _pull_account(adb_serial):
    tmp = tempfile.mkdtemp(prefix="glagol_")
    dst = os.path.join(tmp, "account_storage.dat")
    subprocess.run(["adb", "-s", adb_serial, "pull",
                    "/data/quasar/account_storage.dat", dst],
                   check=True, capture_output=True)
    return dst

def _oauth_candidates(path):
    b = open(path, "rb").read()
    def rv(buf, i):
        s = r = 0
        while True:
            x = buf[i]; r |= (x & 0x7f) << s; i += 1; s += 7
            if not x & 0x80: return r, i
    def walk(buf):
        out, j = [], 0
        while j < len(buf):
            key, j = rv(buf, j); wt = key & 7
            if wt == 0: _, j = rv(buf, j)
            elif wt == 2:
                ln, j = rv(buf, j); c = buf[j:j+ln]; j += ln
                if c and all(32 <= x < 127 for x in c): out.append(c.decode())
                else:
                    try: out += walk(c)
                    except Exception: pass
            elif wt == 5: j += 4
            elif wt == 1: j += 8
            else: break
        return out
    return [s for s in walk(b) if s.startswith("y0_")]

def _backend_get(url, oauth):
    import urllib.request
    req = urllib.request.Request(url, headers={"Authorization": "OAuth " + oauth})
    return json.loads(urllib.request.urlopen(req, timeout=20).read().decode())

def get_token(adb_serial):
    import urllib.parse
    cands = _oauth_candidates(_pull_account(adb_serial))
    if not cands:
        sys.exit("no OAuth token found in account_storage.dat")
    last = None
    for tok in cands:
        try:
            dl = _backend_get(f"{BACKEND}/glagol/device_list", tok)
        except Exception as e:
            last = e; continue
        if "devices" not in dl: continue
        dev = next((d for d in dl["devices"]
                    if d.get("platform", "") not in
                    ("iot_app_ios", "iot_app_android", "maps_ios", "maps_android")),
                   dl["devices"][0])
        q = urllib.parse.urlencode({"device_id": dev["id"], "platform": dev["platform"]})
        tk = _backend_get(f"{BACKEND}/glagol/token?{q}", tok)
        if tk.get("token"):
            return tk["token"], dev
        last = tk
    sys.exit(f"could not get conversationToken: {last}")

# ---------- glagol payloads ----------
def _repeat_phrase(text):
    return {"name": "update_form",
            "payload": {"form_update": {
                "name": "personal_assistant.scenarios.quasar.iot.repeat_phrase",
                "slots": [{"name": "phrase_to_repeat", "optional": False,
                           "type": "string", "value": text}]},
                "resubmit": True},
            "type": "server_action"}

def build_payload(args):
    cmd = args.command
    if cmd == "say":     return {"command": "serverAction",
                                 "serverActionEventPayload": _repeat_phrase(args.text)}
    if cmd == "volume":  return {"command": "setVolume", "volume": float(args.value)}
    if cmd == "ping":    return {"command": "ping"}
    if cmd in ("play", "pause", "stop", "next", "prev", "rewind", "shuffle", "repeat"):
        return {"command": cmd}
    if cmd in ("status", "monitor"):
        return {"command": "ping"}  # ping primes an immediate state push
    return None

# ---------- transport ----------
async def run(args, ct):
    import websockets
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    def mk(p): return json.dumps({"conversationToken": ct, "id": str(uuid.uuid4()),
                                  "sentTime": int(time.time()*1000), "payload": p})
    seconds = getattr(args, "seconds", 6)
    async with websockets.connect(f"wss://{args.ip}:{args.port}", ssl=ctx,
                                  ping_interval=None, open_timeout=10) as ws:
        payload = build_payload(args)
        if payload is not None:
            await ws.send(mk(payload)); print(f"[+] sent: {payload.get('command')}")
        t0, last = time.time(), None
        while time.time() - t0 < seconds:
            try: r = await asyncio.wait_for(ws.recv(), timeout=1)
            except asyncio.TimeoutError: continue
            try:
                j = json.loads(r); st = j.get("state") or {}
                snap = {k: st.get(k) for k in
                        ("aliceState", "playing", "volume", "playerState") if k in st}
                if args.command == "status":
                    print(json.dumps(st, ensure_ascii=False, indent=2)[:1500]); return
                if snap and snap != last:
                    print(f"  {time.time()-t0:4.1f}s {snap}"); last = snap
            except Exception:
                pass

def main():
    ap = argparse.ArgumentParser(description="glagol LAN client for Yandex Station")
    ap.add_argument("command", choices=["status", "monitor", "ping", "say", "volume",
                                        "play", "pause", "stop", "next", "prev",
                                        "rewind", "shuffle", "repeat"])
    ap.add_argument("value", nargs="?", help="text for 'say', 0..1 for 'volume'")
    ap.add_argument("--adb", default="192.168.1.80:5555")
    ap.add_argument("--ip", default="192.168.1.80")
    ap.add_argument("--port", type=int, default=1961)
    ap.add_argument("--seconds", type=int, default=6)
    ap.add_argument("--volume", type=float, default=None)
    a = ap.parse_args()
    if a.command == "say": a.text = a.value or "Привет"
    if a.command == "monitor": a.seconds = max(a.seconds, 30)
    ct, dev = get_token(a.adb)
    print(f"[*] device: {dev.get('name')} ({dev.get('platform')})")
    # optional pre-volume for say
    if a.command == "say" and a.volume is not None:
        asyncio.run(run(argparse.Namespace(command="volume", value=a.volume,
                        ip=a.ip, port=a.port, seconds=2), ct))
    asyncio.run(run(a, ct))

if __name__ == "__main__":
    main()
