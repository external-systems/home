# Whisper Dictation

Local, privacy-first push-to-talk speech-to-text for kamrui-h1, built on
[whisper-dictation](https://github.com/jacopone/whisper-dictation)
(whisper.cpp) with Vulkan acceleration on the AMD iGPU. 100% local — no cloud,
works offline.

## Usage

1. Click into any text field
2. Hold <kbd>Super</kbd>+<kbd>Semicolon</kbd>
3. Speak naturally
4. Release the key — the transcription is typed into the focused window

The daemon (`systemd --user` unit `whisper-dictation`) starts automatically
with the KDE Wayland session. Desktop notifications show recording /
transcribing / success states.

## What the module does

`hostSpec.services.whisper-dictation.enable = true;` wires only the
NixOS-specific glue (everything else is upstream stock):

- `programs.ydotool.enable` — system `ydotoold` (uinput text insertion,
  socket `/run/ydotoold/socket`)
- `boot.kernelModules = ["uinput"]`
- Adds the user to the `input` (evdev hotkey capture) and `ydotool` groups
- Runs `whisper-dictation-vulkan` as a user service gated to the user
  (`ConditionUser`) with `YDOTOOL_SOCKET=/run/ydotoold/socket`
- Re-wraps upstream's package with the full Gtk-4.0 typelib closure
  (`glib`, `graphene`, `pango`, `gdk-pixbuf`, `cairo`, `harfbuzz`) —
  upstream's wrapper omits `GI_TYPELIB_PATH` entirely, and
  `Gtk-4.0.typelib` resolves all of those namespaces; with glib alone the
  daemon crash-loops on `Typelib namespace Graphene not found`

Options: `enable`, `user` (default `netsa`).

## Configuration (`homeSpec.programs.whisper-dictation`)

`config.yaml` is managed declaratively by the home-manager module
`flake.homeModules.whisper-dictation` (enabled in `profile-netsa`), which
writes `~/.config/whisper-dictation/config.yaml`. The daemon only reads
it at startup — restart the unit after changes
(`systemctl --user restart whisper-dictation`).
Options: `inputDevice` (name substring or event path; null = upstream
auto-select), `hotkey.modifiers` (`super`/`ctrl`/
`alt`/`shift`, each matches left AND right), `hotkey.key` (`period`,
`comma`, `space`, `slash`, `semicolon` — anything else silently falls
back to `period`), `whisper.model`, `whisper.language`, and `extraConfig`
for remaining upstream keys (`processing`, `typing`, `ui`).

The current profile pins the Samsers KT06 bluetooth keyboard with
<kbd>Super</kbd>+<kbd>Semicolon</kbd>.

Key settings to know:

- `inputDevice` — **pin the push-to-talk keyboard** by name substring
  (event nodes renumber across reboots/reconnects, so don't pin
  `/dev/input/eventN`). First substring match wins: pick a string unique
  to the keyboard's typing interface (a bare vendor word can match the
  mouse or a phantom dongle node that never emits keys).
- `hotkey` — Super+Semicolon here; `super`+`period` collides with the
  KDE Plasma emoji picker
- `whisper.model` — `small` (provisioned), `tiny`, `base`, `medium`
- `whisper.language` — `en` (or `auto`)

## Bluetooth / compact keyboards

The daemon watches exactly **one** evdev device — the one pinned by
`input_device` (or its single auto-pick). A bluetooth keyboard is a
different input node than the wired Logitech, so the stock `event1` pin
never sees its keys: a hotkey that "does nothing" on a new keyboard is
almost always the **device pin**, not the binding.

1. Find the bluetooth keyboard's evdev name (the typing interface):
   `libinput list-devices` or `grep -B1 -A5 Keyboard /proc/bus/input/devices`
2. Pin a distinctive substring of it in config.yaml:
   `input_device: "<name>"` — substring match, first hit wins, so pick a
   string unique to the keyboard (a bare vendor word like `Logitech` can
   match the mouse or a phantom dongle node). BT keyboards often expose
   several nodes (consumer-control etc.); pin the one that emits letters.
3. `systemctl --user restart whisper-dictation` and confirm
   `Found configured device:` in the journal.

### Supported hotkey values

Only these are recognized (upstream `config.py`):

- modifiers: `super`, `ctrl`, `alt`, `shift` — each matches **both** left
  and right, so "no right ctrl" is a non-issue: left ctrl already works.
  Combine as a list (`["ctrl", "alt"]`).
- trigger keys: `period`, `comma`, `space`, `slash`, `semicolon`.
  **Anything else silently falls back to `period`** — F-keys etc. are not
  supported as the trigger.

### Suggested bindings for compact keyboards

| Binding | Notes |
| --- | --- |
| `alt` + `semicolon` | one-handed (Alt by the spacebar), no KDE conflict; `alt` includes RightAlt — AltGr layouts beware |
| `ctrl` + `semicolon` | classic, free on KDE |
| `super` + `semicolon` | safe on KDE; Super can be a "meta" key on some BT keyboards |
| `ctrl`+`alt` + `period` | two modifiers, zero collisions anywhere |

Avoid: `shift`+key (typing `>`/`<` would trigger dictation),
`super`+`period` (KDE emoji picker), `ctrl`+`slash` (comment toggle in
editors), `ctrl`+`comma` (settings/zoom), `ctrl`+`space` (IME / IntelliSense).

Example config.yaml for a bluetooth keyboard:

```yaml
input_device: "<your BT keyboard evdev name>"
hotkey:
  modifiers: ["alt"]
  key: "semicolon"
```

## Model

`~/.local/share/whisper/models/ggml-small.bin` is a symlink into the Nix
store (provisioned during the initial deployment). To switch models:

```console
$ curl -L -o ~/.local/share/whisper/models/ggml-base.bin \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

then set `whisper.model: base` in config.yaml.

| Model | Size | Accuracy | Notes |
| --- | --- | --- | --- |
| tiny | 39 MB | ~60% | Fastest, noisy output |
| base | 142 MB | ~70% | Upstream's speed pick |
| small | 466 MB | ~80% | Default here — good balance with iGPU Vulkan |
| medium | 1.5 GB | ~85% | Slower on an iGPU |

## Devices on kamrui-h1

- **Microphone**: the Logitech C270 webcam's mic ("Webcam C270 Mono") is the
  PipeWire default source — recording uses it automatically.
- **Push-to-talk keyboard**: the wired `Logitech LogiG MKeyboard`, pinned via
  `input_device` in config.yaml (see above).
- Text insertion goes through the system `ydotoold` (`/run/ydotoold/socket`).

## Troubleshooting

- **Daemon logs**: `journalctl --user -u whisper-dictation -f`
- **Verbose run** (shows hotkey detection and recording):
  `systemctl --user stop whisper-dictation && whisper-dictation --verbose`
  (restart the unit afterwards)
- **Hotkey does nothing**: confirm the daemon watches `/dev/input/event1`
  (`Found configured device: … at /dev/input/event1` in the journal); verify
  the by-id mapping if nodes renumbered; only the pinned keyboard triggers
- **No text appears**: `systemctl status ydotoold` must be active
- **No audio recorded**: confirm `Webcam C270 Mono` is the default source
  (`wpctl status`)
- **Slow transcription**: lower `whisper.model` (small → base → tiny)
