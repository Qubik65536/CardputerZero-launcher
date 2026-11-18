<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Device reference

Facts an app developer needs, checked against the launcher source (file
references are relative to the repository root, so you can read further).

## System

| | |
| --- | --- |
| CPU / OS | AArch64 (arm64), Debian 13 "trixie" (Raspberry Pi OS based), glibc 2.41, libstdc++ from GCC 14 |
| User | `pi` (UID 1000). APPLaunch runs as a systemd **user** service: `systemctl --user status APPLaunch.service` |
| Launcher files | `/usr/share/APPLaunch/` (`bin/`, `applications/`, `share/images/`, `share/font/`, `share/audio/`) |
| Logs | `journalctl --user -u APPLaunch.service -f` (apps started by the launcher inherit its stdout/stderr, so your prints appear here) |

Binaries must be built for `aarch64` Linux. glibc-linked binaries need a glibc
of 2.41 or older at build time (the cross toolchains and Debian trixie
containers satisfy this); static binaries (Zig's default for the device) do not
care.

## Screen

| | |
| --- | --- |
| Size | **320 x 170** pixels, landscape, no rotation |
| UI convention | 20 px top bar + 320 x 150 content area (`ext_components/cp0_lvgl/include/ui_app_page.hpp`) |
| Framebuffer device | `$LV_LINUX_FBDEV_DEVICE` (the launcher exports it to the apps it starts), else `/dev/fb_lcd`, else the `/proc/fb` entry named `st7789`/`fb_st7789v`, else `/dev/fb0` (`ext_components/cp0_lvgl/src/cp0/cp0_lvgl_freambuffer.c`) |
| Pixel format | Read `bits_per_pixel` from `/sys/class/graphics/fbN/`: 16 = RGB565 (expected), 32 = XRGB8888. Row length: `/sys/class/graphics/fbN/stride` (bytes). The templates handle both |
| Buffering | Single buffer, no page flipping: write the whole frame (`pwrite` at offset 0) or `mmap` it |
| Backlight | `/sys/class/backlight/backlight/brightness` (0..`max_brightness`) |

While your app runs, the launcher does not draw. It does **not** clear the
screen first: the first frame you see is the launcher's "Loading..." overlay, so
draw a full frame right away. When your app exits the launcher redraws
everything; you do not need to restore the screen.

## Keyboard

| | |
| --- | --- |
| Device | `$LV_LINUX_KEYBOARD_DEVICE` (exported by the launcher), default `/dev/input/by-path/platform-3f804000.i2c-event` (a TCA8418 key matrix) |
| Format | Linux evdev: 24-byte `struct input_event` records (`type`, `code`, `value`): `EV_KEY`=1 with value 1 press, 0 release, 2 auto-repeat |
| Exclusive access | Nobody grabs the device: the launcher keeps watching it for ESC. **Do not `EVIOCGRAB`** it, or the "hold ESC to quit" safety net stops working |
| Repeat | 500 ms delay, 50 ms interval |

### Key codes

Letters, digits, ESC (1), BACKSPACE (14), TAB (15), ENTER (28) and SPACE (57)
use the standard Linux codes (`linux/input-event-codes.h`). Two things differ
from a PC keyboard:

**No arrow keys.** By convention **F / X / Z / C** are **up / down / left /
right** (`cp0_keyboard_navigation_alias` in
`ext_components/cp0_lvgl/include/cp0_keyboard_navigation_contract.h`). The
launcher and LVGL apps use them in navigation contexts; raw apps should accept
both these and the real arrow codes (103/108/105/106, which the desktop
simulator and USB keyboards send). The templates do this with a `direction()`
helper.

**Symbols reuse codes.** The symbol layer sends codes that mean something else
in the Linux table. APPLaunch translates them with
`/usr/share/keymaps/tca8418_keypad_m5stack_keymap.map` (format
`keycode N = <keysym>`) or this built-in default
(`ext_components/cp0_lvgl/src/cp0/cp0_keyboard_keymap.c`):

| Code | Symbol | Code | Symbol | Code | Symbol | Code | Symbol |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 26 | `!` | 41 | `%` | 69 | `` ` `` | 79 | `;` |
| 27 | `@` | 43 | `^` | 70 | `_` | 80 | `:` |
| 39 | `#` | 51 | `&` | 71 | `-` | 81 | `'` |
| 40 | `$` | 52 | `*` | 72 | `+` | 82 | `"` |
| 53 | `(` | 94 | `)` | 73 | `=` | 83 | `<` |
| 55 | `~` | 74 | `[` | 75 | `]` | 85 | `>` |
| 76 | `{` | 77 | `}` | 86 | `\` | 89 | `\|` |
| 90 | `,` | 91 | `.` | 92 | `/` | 93 | `?` |

If your app needs text with symbols, apply this table (Calculator does:
`projects/Calculator/main/src/calculator_keymap.cpp`). Shift produces
`KEY_LEFTSHIFT`; Fn is `KEY_FN` (0x1d0); SYM is `KEY_COMPOSE` (127). LVGL apps
get all of this pre-translated (see [C++ / LVGL](cpp-lvgl.md)).

## How the launcher runs your app

For a `.desktop` entry with `Terminal=false` (`projects/APPLaunch/main/ui/launch.cpp`,
`ext_components/cp0_lvgl/src/cp0/cp0_external_app_runner.cpp`):

1. Shows "Loading...", stops all launcher timers and drawing, pauses its own key handling.
2. Runs `Exec` with `/bin/sh -c` in a **new process group**, as the same user
   (`pi`), working directory `/usr/share/APPLaunch`, with the launcher's
   environment plus `LV_LINUX_FBDEV_DEVICE`, `LV_LINUX_KEYBOARD_DEVICE`,
   `XDG_RUNTIME_DIR=/run/user/1000` and `PULSE_SERVER` (audio via PipeWire/Pulse).
3. Waits until **every process in the group** has exited (background children count).
4. Watches ESC: held **3 s** sends SIGTERM to the group, still alive 3 s later gets SIGKILL.
5. Redraws the home screen and resumes.

Consequences: quit on a short ESC press; handle SIGTERM if you need to save
state; don't leave background processes running; don't rely on the working
directory (use absolute paths, e.g. `/usr/share/APPLaunch/share/...` for
installed assets).

For `Terminal=true` see [terminal apps](terminal-apps.md).

## `.desktop` entries

Only `/usr/share/APPLaunch/applications/*.desktop` is scanned; changes appear
within ~3 s (`projects/APPLaunch/main/ui/desktop_entry.cpp`,
`desktop_app_loader.cpp`, `ext_components/cp0_lvgl/src/cp0/cp0_desktop_exec_policy.cpp`).

```ini
[Desktop Entry]
Name=Pixel Pet
Exec=/usr/share/APPLaunch/bin/pixel-pet
Icon=share/images/pixel-pet_100.png
Terminal=false
Type=Application
```

| Key | Rules |
| --- | --- |
| `Name` | Required, at most 128 bytes |
| `Exec` | Required, at most 512 bytes. Must be an **absolute path to an executable file** (or one of `bash`, `python3`, `vim`, `vi`, `nano`, `sh`), followed by plain arguments. Rejected if it contains any of `\| & ; < > \` $ \\` or a newline. `%f`-style field codes are not expanded |
| `Icon` | `share/images/<file>.png` (relative to `/usr/share/APPLaunch`). A PNG that decodes to RGBA; shown at **100 x 100** (other sizes are resampled). Paths outside `/usr/share/APPLaunch` or containing `..` do not work |
| `Terminal` | `true` runs the program in the built-in terminal; default `false` |
| `Type` | Optional; if present it must be exactly `Application` |
| `Hidden` / `NoDisplay` | `true` hides the entry |
| `Sysplause` | Terminal apps only; see [terminal apps](terminal-apps.md) |

Boolean values must be `true`, `True` or `1`. Entries are skipped (with a
message in the log) when `Name`/`Exec` is missing, `Exec` fails the checks
above, `Exec` duplicates another entry or a built-in app (`python3`, the Store,
the Calculator), or the icon cannot be resolved. At most 128 entries are loaded.

## Running other tools

| Need | How |
| --- | --- |
| Root actions | `sudo` (the `pi` user is a sudoer; prefer doing root work at install time in your package) |
| Network | Ordinary Linux networking: sockets, `curl`, HTTP libraries |
| Sound | PulseAudio/PipeWire for user `pi` (`paplay`, `libpulse`, miniaudio) |
| Storage | Your home directory `/home/pi`; `~/Downloads` exists |
