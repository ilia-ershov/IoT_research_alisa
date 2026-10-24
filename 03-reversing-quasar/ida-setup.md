# Настройка IDA Pro + MCP для реверса `maind`

## Как это устроено
```
Claude Code ──stdio──> ida-pro-mcp (сервер) ──HTTP RPC :13337──> плагин внутри IDA Pro
                                                                   (где открыт maind)
```
MCP-сервер уже установлен (venv) и прописан в `.mcp.json`. Нужна сама IDA Pro с плагином.

---

## Шаг 1 — Установить IDA Pro (это на тебе, я не могу)

IDA сейчас **не установлена**. Нужна **IDA Pro с декомпилятором ARM** (Hex-Rays ARM):
- ⚠️ **IDA Free не подойдёт** — в ней нет декомпилятора ARM32, а `maind` — именно ARM32.
  Нужна платная IDA Pro (или IDA Home с ARM-декомпилятором).
- Скачать из личного кабинета на hex-rays.com по своей лицензии, установить `.app` в
  `/Applications`, активировать лицензию.
- После установки привязать Python:
  ```bash
  "/Applications/IDA Professional 9.X.app/Contents/MacOS/idapyswitch"
  ```
  (нужно, чтобы плагин MCP работал с системным Python 3).

Проверка, что IDA видна:
```bash
ls -d /Applications/IDA*          # должен появиться .app
ls -la ~/.idapro                  # папка настроек IDA
```

## Шаг 2 — Поставить плагин MCP в IDA (делаю я, когда IDA будет)

```bash
/Users/thomas/alisa_discovery/tools/ida-mcp-venv/bin/ida-pro-mcp --install
```
Это скопирует `mcp-plugin.py` в пользовательскую папку плагинов IDA и настроит клиентов.

## Шаг 3 — Загрузить и проанализировать `maind` в IDA
1. Открыть IDA Pro → **File ▸ Open** → `/Users/thomas/alisa_discovery/artifacts/maind`.
2. Процессор определится как **ARM little-endian (ARMv7, 32-bit)** — подтвердить.
3. Дождаться окончания автоанализа (внизу статус **AU: idle**; на 14 МБ `.text` это
   займёт заметное время — это нормально).
4. Плагин MCP стартует сам (меню **Edit ▸ Plugins ▸ MCP** / по умолчанию слушает
   `127.0.0.1:13337`). В Output-окне появится строка про MCP server.

## Шаг 4 — Подключить MCP в Claude Code
Конфиг уже лежит в `/Users/thomas/alisa_discovery/.mcp.json`. Чтобы Claude Code его
подхватил — **перезапусти сессию** (новый MCP-сервер цепляется только при старте).
После рестарта у меня появятся инструменты `mcp__ida-pro-mcp__*`
(`decompile_function`, `get_xrefs_to`, `list_functions`, `rename_function`, …).

> Если захочешь дать мне право не только читать, но и патчить/переименовывать агрессивно —
> сервер можно запускать с флагом `--unsafe` (по умолчанию выключено, это безопаснее).

---

## Что я сделаю, как только MCP поднимется
Точечный реверс (не весь бинарь — это нереально), якорясь по строкам из `.rodata`:
1. **Cert pinning** — функция, печатающая `SSL public key does not match pinned public key`
   → xrefs → найти проверку и понять, как обойти для перехвата облачного трафика.
2. **glagol-токен** — обработчики `/glagol/check_token`, `/glagol/token?device_id=`
   → как валидируется локальная команда на :1961.
3. **Диспетчер директив** — таблица `...DirectiveType` → где `maind` маршрутизирует
   команды из UniProxy, какие доступны без подтверждения (`CameraSnapshot`, `StartFileUpload`).
4. **Форматы protobuf** — сверить с `account_storage.dat` / `user_config.dat` / `wifi.dat`.

---

## Альтернатива (если лицензии IDA нет)
Тот же ARM32-декомпил бесплатно даёт **Ghidra** (Java у тебя есть) — я уже начал её ставить
и могу продолжить с **GhidraMCP** (качество декомпиляции ARM у Ghidra сопоставимо с IDA).
Скажи, если захочешь переиграть.
