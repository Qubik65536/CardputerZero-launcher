<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Testing in the emulator

`projects/CardputerZero-Emulator` runs the real launcher (APPLaunch) inside a
picture of the device: the 320x170 screen, the keyboard you can click, and the
side buttons. Your app can run in it in two ways:

| | Command | Use it for |
| --- | --- | --- |
| **Run directly** | `cardputer-zero-emu --fb -- <your desktop build>` | The quickest edit-build-look loop, in the device frame |
| **Open from the home screen** | `python3 scripts/emulator_install.py <app>`, then `cardputer-zero-emu` | The whole experience: your icon on the home screen, opening the app, ESC back home, holding ESC to force-quit |

Both work for every template (C++/LVGL, Rust, Zig, OCaml) on macOS and Linux.
They run the **desktop build** of your app, the same one you use with `fbsim`;
the device build is for the device.

## Build the emulator (once)

```bash
cd projects/CardputerZero-Emulator
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j8
```

It needs SDL2, SDL2_image and FreeType (`brew install sdl2 sdl2_image freetype`
or `apt install libsdl2-dev libsdl2-image-dev libfreetype-dev`). The program is
`projects/CardputerZero-Emulator/build/cardputer-zero-emu`; the examples below
call it `$EMU`:

```bash
EMU=$PWD/build/cardputer-zero-emu
```

## Run your app directly

From your app's directory, pass the command that starts its desktop build:

| Template | Command |
| --- | --- |
| C++ / LVGL | `scons -j8 && $EMU --fb -- dist/my-app` |
| Rust | `cargo build && $EMU --fb -- target/debug/my-app` (or `$EMU --fb -- cargo run`) |
| Zig | `zig build && $EMU --fb -- zig-out/bin/my-app` |
| OCaml | `dune build && $EMU --fb -- _build/default/src/main.exe` |
| anything else | `$EMU --fb -- <command> [args...]` |

The app's screen appears in the device frame. The emulator exits when the app
does, with the app's exit status, so `--fb` also works in scripts. Paths are
relative to the directory you start from.

## Open it from the home screen

```bash
python3 scripts/emulator_install.py projects/MyApp     # after building the desktop version
$EMU                                                   # move with Z/C (or arrows), ENTER opens
python3 scripts/emulator_install.py projects/MyApp --remove
```

`emulator_install.py` reads `desktop_binary` from `cardputer-app.json` (every
template sets it), checks the `.desktop` file with the same rules as the
packager, and copies:

```
APPLaunch/applications/my-app.desktop  ->  build/applications/my-app.desktop   (Exec = your desktop build)
APPLaunch/share/...                    ->  build/APPLaunch/share/...           (icon and other files)
```

Installed apps appear to the left of Settings (press Z or the left arrow a
few times). The launcher rescans every 3 seconds, so installing while the
emulator runs works too. After a rebuild, just open the app again; reinstall
only when the `.desktop` file or icon changes. For a different binary:
`--binary path/to/build`.

What happens when you open the app is what happens on the device: the launcher
stops drawing and hands over the screen as it was, your app draws and gets the
keys, and when it exits the launcher redraws the home screen. Holding **ESC for
3 seconds** sends the app SIGTERM (then SIGKILL after 3 more), just like the
real launcher.

## Controls

| Input | What the app receives |
| --- | --- |
| Your computer's keyboard | The key, including arrows (which the device lacks; test F/X/Z/C as well) |
| Clicking a key on the picture | That key |
| Clicking **Aa**, **ctrl**, **alt** or **fn** | Latches it (highlighted) for the next key: Shift, Ctrl, Alt or `KEY_FN` |
| Side buttons | ESC, HOME, TALK (F3), NEXT (TAB) |
| POWER (top right) | Offers to restart the launcher (ignored while an app runs) |
| Closing the window | Sends the app SIGTERM (SIGKILL after 3 s) and exits |

Text follows the US layout of a desktop keyboard. The device's SYM layer and
its special symbol codes are not emulated; see
[device reference](device-reference.md#key-codes) and test symbol input on
the device.

## Automated tests

The emulator can press keys and take screenshots by itself. Times are
milliseconds since start:

```bash
EMU_TEST_KEYS="1500:c,1700:c,2000:Return" \
EMU_TEST_SCREENSHOT="2500:/tmp/after-keys.png" \
EMU_TEST_QUIT_MS=3000 \
$EMU --fb -- target/debug/my-app
```

- `EMU_TEST_KEYS`: comma-separated `time:key`, where key is an SDL key name (`a`, `Return`, `Escape`, `Left`, `F3`, ...). Add `:down` or `:up` to press and release separately, e.g. `4000:Escape:down,8000:Escape:up` to test the hold-ESC force-quit.
- `EMU_TEST_SCREENSHOT`: comma-separated `time:file.png`; saves the 320x170 screen.
- `EMU_TEST_QUIT_MS`: quit at that time (an app still running gets SIGTERM).

The same variables drive the launcher, e.g. to open your app from the home
screen in a test: `EMU_TEST_KEYS="7000:Left,8000:Left,9000:Left,10500:Return"`.
Give the launcher about 7 seconds to start before the first key, and take a
screenshot first to see where the selection is. On a machine without a display,
run under `Xvfb` (Linux). For tests that don't need the device frame or the
launcher, [`headless.py`](framebuffer-apps.md#automated-checks-no-window) is
lighter: no window and no SDL.

## How it works

The emulator implements the same contract as `fbsim`: it creates a
framebuffer file and an input FIFO and starts the app with `CARDPUTER_FB`,
`CARDPUTER_FB_SIZE` and `CARDPUTER_INPUT` set.

- The Rust, Zig and OCaml templates read those variables directly.
- C++/LVGL apps get it from cp0_lvgl: when `CARDPUTER_FB` is set, the desktop build draws into that file and reads keys from the FIFO instead of opening its own window. The same binary still opens a normal window when you run it on its own. This also means `fbsim` and `headless.py` work for LVGL apps.
- Apps opened from the home screen get the variables from the launcher's external-app runner (`cp0_sdl_external_app_*` hooks in `ext_components/cp0_lvgl/src/sdl/sdl_external_app_runner.hpp`, implemented in `src/main.cpp`).

## Differences from the device

- The app is a desktop program running as you, started from the emulator's `build/` directory (on the device: `/usr/share/APPLaunch`, as user `pi`). Use absolute paths, or for LVGL apps `cp0_file_path`.
- An app that ignores `CARDPUTER_FB` (for example a generic SDL program) opens its own window; the emulator still waits for it and handles ESC.
- Wi-Fi, battery, audio routing and other hardware services are simulated by the launcher, not real.
- Speed: your computer is much faster than the device. Check performance on the device.
- The hold-ESC hint overlay is not drawn; the emulator prints a message instead (in `--fb` mode).
- Windows builds of the emulator don't support `--fb` or opening external apps.
