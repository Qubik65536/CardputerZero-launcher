<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (C++ / LVGL)

A CardputerZero app built like the launcher's own apps: LVGL 9.5 widgets, the
standard top bar (title, clock, battery) and the `cp0_lvgl` platform layer, so
it runs as an SDL window on your desktop and full-screen on the device.

It greets you with "Hello, C++!" over a wallpaper and opens three demos:
**Colors** (a spinning RGB triangle and a color wheel drawn on an
`lv_canvas`), **Motion** (a glowing ball to push around) and **REPL** (a
terminal-style calculator). F/X choose, ENTER opens, TAB goes to the next
demo, ESC goes back (and quits from home). Keep what you need, delete the rest.

Full guide: [docs/app-development/cpp-lvgl.md](../../docs/app-development/cpp-lvgl.md).
Run every command from this directory (it must stay at `projects/<Name>/`).

## Run on your computer

```bash
scons -j8                          # picks the macOS or Linux SDL2 profile
cd dist && ./hello-cardputer       # F/X choose, ENTER open, ESC back/quit
```

In the device emulator (build it once, see `docs/app-development/emulator.md`):

```bash
EMU=../../projects/CardputerZero-Emulator/build/cardputer-zero-emu
scons -j8 && $EMU --fb -- dist/hello-cardputer
python3 ../../scripts/emulator_install.py .     # or: add it to the emulator's home screen
```

## Build for the device

```bash
CONFIG_DEFAULT_FILE=linux_x86_cross_cp0_config_defaults.mk scons -j8
python3 ../../scripts/package_app.py .     # -> packages/hello-cardputer_0.1.0_arm64.deb
```

Install it: `scp packages/*.deb pi@<device>: && ssh pi@<device> sudo dpkg -i hello-cardputer_0.1.0_arm64.deb`.
The app appears on the home screen within a few seconds.

## Where things are

| Path | What |
| --- | --- |
| `main/ui/hello_cardputer_page.cpp` | The page: owns the screens, shows one at a time, routes keys. Start here. |
| `main/ui/app_ui.hpp` | Language name and color, palette, `Action`, key helpers, the `Screen` base class |
| `main/ui/home_screen.cpp` | Home screen: wallpaper, greeting, menu |
| `main/ui/colors_screen.cpp`, `motion_screen.cpp`, `repl_screen.cpp` | The three demos |
| `main/ui/pixel_canvas.cpp` | Pixel drawing on an `lv_canvas` (used by Colors and Motion) |
| `main/ui/calc.cpp` | The REPL's calculator language (plain C++17, no LVGL) |
| `main/src/main.cpp` | Entry point: runs the page until ESC on the home screen |
| `main/SConstruct` | Sources, libraries, executable name |
| `APPLaunch/applications/hello-cardputer.desktop` | Home-screen entry (name, icon, command) |
| `APPLaunch/share/images/hello-cardputer_100.png` | 100x100 icon (`scripts/make_app_icon.py` makes new ones) |
| `APPLaunch/share/images/wallpaper.png` | Home-screen picture, 320x150 (Qubix artwork, Apache-2.0; see `LICENSES/Qubix-wallpaper-Apache-2.0.txt`) |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
| `*_config_defaults.mk` | Build profiles: `darwin` (macOS window), `linux_x86_sdl2` (Linux window), `linux_x86_cross_cp0` (device, from macOS or Linux), `config_defaults` (building on the device) |

Switching profiles is automatic; if a build ever looks stale, run `scons distclean`.
