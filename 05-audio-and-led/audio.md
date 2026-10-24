# Часть 2 — Звук: как устроен и как заставить говорить

## 1. Аудио-железо и ALSA
- SoC-звук: **Amlogic `AML-AUGESOUND`**, усилитель **TAS5825M** (`card 0, device 0:
  TDM-B-tas5825m-amplifier`). Инициализация — `/etc/init.d/S45tas58xx`.
- Формат тракта: `audio/x-raw, rate=48000, channels=2, format=S16LE`.
- Микшер (`amixer`): `Master` (громкость 0–255), `SPK mute`, `TAS5805M Analog`,
  loopback-контролы. Хелпер: `set_volume.sh` → `amixer set 'Master' N%`.
- Микрофоны: массив из 4 шт. (`yandexmicro`, каналы `raw_mic_0..3`).

## 2. Полный аудио-пайплайн
```
[4 mic] raw_mic_0..3 ─▶ VQE (YandexVqeC: beamforming, AEC, шумоподавление, DoA)
        ─▶ vqe_0 ─▶ TFLite-споттер (alisa/vad/command/counteractivation)
        ─▶ [активация] ─▶ VoiceDialog ─▶ wss://uniproxy.alice.yandex.net
Воспроизведение:
  mediad (GStreamer, GST_PLUGIN_PATH=/system/vendor/quasar/libs)
    ─▶ ALSA (plughw:0,0) ─▶ TAS5825M ─▶ динамик
```
GStreamer-конвейер из конфига:
`appsrc ! {input_media_type} ! multiqueue ! audioresample ! VOLUME_MASTER ! spectrum ! sink`.

## 3. Звуковые файлы устройства
`/system/vendor/quasar/sounds/{common,ru-RU}` (+ оверлей `/data/quasar/data/sounds`):
- `common/`: earcon'ы — `spotter_start.opus`, `spotter_cancel.opus`, `timer.opus`,
  `notification_sound.opus`, `volume_sound.opus`, звуки звонков.
- `ru-RU/`: голосовые подсказки — `no_internet.opus`, `configure_success.opus`,
  `wrong_wifi_password.opus`, `stolen.wav`, и т.д.
Формат: в основном **Opus** (нужен GStreamer/mediad для декода), несколько MP3 и один WAV.

## 4. CLI управления (режимы `maind`)
- **`maind --cli`** — интерактивный пульт. Команды:
  `q`=Text Input Query (ввести текст запроса), `s`=Start/`t`=Toggle/`c`=Cancel
  Conversation, `p`=PlayPause, `n`/`l`=next/prev, `o`=Pause, `m`=mute, `x`=exit.
- **`quasar_client -s <service> [-h host -p port] -m <base64>`** — IPC-клиент: шлёт
  сырой protobuf (base64) в сервис на localhost (порты 9875–9926 из `quasar.cfg`).
  Это канал для инъекции директив в работающий стек.

## 5. Как заставить колонку «сказать» — два пути

### Method B — проигрывание произвольного аудио (РАБОТАЕТ, проверено)
Самый надёжный способ вывести звук в динамик, в обход облака:
```bash
D=192.168.1.80:5555
say -v Milena -o phrase.wav --file-format=WAVE --data-format=LEI16@48000 "<текст>"  # на Mac
adb -s $D push phrase.wav /tmp/phrase.wav
adb -s $D shell "amixer set 'Master' 45%; aplay -D plughw:0,0 /tmp/phrase.wav"
```
Результат: `aplay` открыл `plughw:0,0` и проиграл WAV (48 кГц) — колонка произнесла
заданную фразу. `plughw` сам конвертирует mono→stereo и частоту под TAS5825M.

### Method A — голос самой Алисы (её TTS) — требует инъекции в живой стек
`maind --cli` → `q` регистрирует Text Input Query, НО это **отдельный** процесс maind:
к работающему `mediad`/плееру он не подключается («Not connected to
PlaybackControlCapability»), свой ALSA открыть не может (устройство занято основным
стеком), и в живом `mediad.log` TTS не появляется. Значит, чтобы говорила именно Алиса,
нужно послать директиву **Vocalize** (или Text Input) в РАБОТАЮЩИЙ `platformd`/`aliced`
через `quasar_client -s <service> -m <protobuf>`. Для этого нужна схема protobuf
директивы — реверс в IDA (строки `VocalizeDirectiveType`, обработчик в `maind`).
Это следующий шаг, когда поднят IDA-MCP.

> Безопасность/обратимость: Method B не меняет систему (временный wav в tmpfs),
> громкость возвращается `amixer set 'Master' <N>%`.
