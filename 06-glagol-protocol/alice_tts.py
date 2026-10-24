#!/usr/bin/env python3
"""
alice_tts.py — заставить Яндекс Станцию Лайт произнести ПРОИЗВОЛЬНЫЙ текст
через локальный протокол glagol (:1961), команда serverAction / сценарий
personal_assistant.scenarios.quasar.iot.repeat_phrase.

Токен нигде не хранится: скрипт достаёт OAuth-токен прямо с устройства по ADB
(нужен root-ADB, как в этом исследовании), запрашивает conversationToken у
бэкенда Яндекса и шлёт команду колонке.

Зависимости:  pip install websockets
Использование:
    python3 alice_tts.py "Привет, я Алиса"
    python3 alice_tts.py "Громче!" --volume 0.4 --adb 192.168.1.80:5555 --ip 192.168.1.80
"""
import argparse, asyncio, json, ssl, subprocess, sys, time, uuid, urllib.request, urllib.parse, tempfile, os

def adb_pull_account(adb_serial):
    """Тянет account_storage.dat с устройства, возвращает путь к временной копии."""
    tmp = tempfile.mkdtemp(prefix="alice_tts_")
    dst = os.path.join(tmp, "account_storage.dat")
    subprocess.run(["adb", "-s", adb_serial, "pull",
                    "/data/quasar/account_storage.dat", dst],
                   check=True, capture_output=True)
    return dst

def parse_oauth_candidates(path):
    """Мини-парсер protobuf: вернуть строковые поля (кандидаты в OAuth-токены)."""
    b = open(path, "rb").read()
    def rv(i):
        s = r = 0
        while True:
            x = b[i]; r |= (x & 0x7f) << s; i += 1; s += 7
            if not x & 0x80: break
        return r, i
    out, i = [], 0
    def walk(buf, path=""):
        res, j = [], 0
        while j < len(buf):
            key, j = (lambda k, jj: (k, jj))(*rv_buf(buf, j))
            fn, wt = key >> 3, key & 7
            if wt == 0:
                _, j = rv_buf(buf, j)
            elif wt == 2:
                ln, j = rv_buf(buf, j); chunk = buf[j:j+ln]; j += ln
                if chunk and all(32 <= c < 127 for c in chunk):
                    res.append(chunk.decode())
                else:
                    res.extend(walk(chunk, path+str(fn)+"."))
            elif wt == 5: j += 4
            elif wt == 1: j += 8
            else: break
        return res
    def rv_buf(buf, i):
        s = r = 0
        while True:
            x = buf[i]; r |= (x & 0x7f) << s; i += 1; s += 7
            if not x & 0x80: break
        return r, i
    strings = walk(b)
    # OAuth-токены Яндекса начинаются с 'y0_'
    return [s for s in strings if s.startswith("y0_")]

def backend_get(url, oauth):
    req = urllib.request.Request(url, headers={"Authorization": "OAuth " + oauth})
    return json.loads(urllib.request.urlopen(req, timeout=20).read().decode())

def get_conversation_token(oauth_candidates, want_ip):
    """Пробует кандидатов, возвращает (conversationToken, device)."""
    last_err = None
    for tok in oauth_candidates:
        try:
            dl = backend_get("https://quasar.yandex.net/glagol/device_list", tok)
        except Exception as e:
            last_err = e; continue
        if dl.get("status") == "error" or "devices" not in dl:
            continue
        devs = dl["devices"]
        # выбрать колонку по IP недоступно из device_list; берём первую "станцию"
        dev = None
        for d in devs:
            plat = d.get("platform", "")
            if plat not in ("iot_app_ios", "iot_app_android", "maps_ios", "maps_android"):
                dev = d; break
        dev = dev or devs[0]
        q = urllib.parse.urlencode({"device_id": dev["id"], "platform": dev["platform"]})
        tk = backend_get("https://quasar.yandex.net/glagol/token?" + q, tok)
        if tk.get("token"):
            return tk["token"], dev
        last_err = tk
    raise RuntimeError(f"не удалось получить conversationToken: {last_err}")

def repeat_phrase_payload(text):
    """server_action payload сценария repeat_phrase (из прошивки)."""
    return {
        "name": "update_form",
        "payload": {
            "form_update": {
                "name": "personal_assistant.scenarios.quasar.iot.repeat_phrase",
                "slots": [{"name": "phrase_to_repeat", "optional": False,
                           "type": "string", "value": text}],
            },
            "resubmit": True,
        },
        "type": "server_action",
    }

async def send(ip, port, ct, text, volume):
    import websockets
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
    def mk(payload):
        return json.dumps({"conversationToken": ct, "id": str(uuid.uuid4()),
                           "sentTime": int(time.time()*1000), "payload": payload})
    async with websockets.connect(f"wss://{ip}:{port}", ssl=ctx,
                                  ping_interval=None, open_timeout=10) as ws:
        if volume is not None:
            await ws.send(mk({"command": "setVolume", "volume": volume}))
            await asyncio.sleep(1.0)
        await ws.send(mk({"command": "serverAction",
                          "serverActionEventPayload": repeat_phrase_payload(text)}))
        print(f"[+] sent TTS: {text!r}")
        t0, seen = time.time(), set()
        while time.time() - t0 < 15:
            try:
                r = await asyncio.wait_for(ws.recv(), timeout=1)
            except asyncio.TimeoutError:
                continue
            try:
                st = (json.loads(r).get("state") or {})
                a = st.get("aliceState")
                if a and a not in seen:
                    seen.add(a); print(f"    aliceState -> {a}")
            except Exception:
                pass
        print("[+] done; states:", ", ".join(sorted(seen)) or "none")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text", help="фраза, которую произнесёт Алиса")
    ap.add_argument("--adb", default="192.168.1.80:5555", help="adb serial устройства")
    ap.add_argument("--ip", default="192.168.1.80", help="IP колонки для glagol")
    ap.add_argument("--port", type=int, default=1961)
    ap.add_argument("--volume", type=float, default=None, help="0.0–1.0, выставить перед фразой")
    a = ap.parse_args()
    print("[*] достаю OAuth-токен с устройства по ADB…")
    acct = adb_pull_account(a.adb)
    cands = parse_oauth_candidates(acct)
    if not cands:
        sys.exit("не найден OAuth-токен в account_storage.dat")
    print(f"[*] кандидатов OAuth: {len(cands)}; запрашиваю conversationToken…")
    ct, dev = get_conversation_token(cands, a.ip)
    print(f"[*] устройство: {dev.get('name')} ({dev.get('platform')})")
    asyncio.run(send(a.ip, a.port, ct, a.text, a.volume))

if __name__ == "__main__":
    main()
