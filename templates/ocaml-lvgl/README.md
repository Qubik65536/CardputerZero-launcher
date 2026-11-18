<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (OCaml / LVGL)

A CardputerZero app in OCaml 5 built like the launcher's own apps: LVGL 9.5
widgets, the standard top bar (title, clock, battery) and the `cp0_lvgl`
platform layer, reached through small C stubs. It uses only the OCaml standard
library (no opam packages) and runs as an SDL window on your computer and
full-screen on the device.

It greets you with "Hello, OCaml!" over a wallpaper and opens four demos:
**Colors** (a spinning RGB triangle and a color wheel drawn on an
`lv_canvas`), **Motion** (a glowing ball to push around, with live physics
numbers), **REPL** (a terminal-style calculator) and **Widgets** (real LVGL
widgets: text field, button, slider, counter, roller, switch, driven by the
keyboard). F/X choose, ENTER opens, TAB goes to the next demo, ESC goes back
(and quits from home). Keep what you need, delete the rest.

Full guide: [docs/app-development/lvgl-apps.md](../../docs/app-development/lvgl-apps.md).
Run every command from this directory (it must stay at `projects/<Name>/`,
next to the repository's `scripts/` and `SDK/`).

## Run on your computer

```bash
opam install dune                          # or: brew install dune / apt install ocaml-dune
../../scripts/lvgl-runtime/build.sh desktop  # once: builds LVGL + cp0_lvgl (needs SDL2, see the guide)
dune build
./_build/default/src/main.exe              # F/X choose, ENTER open, ESC back/quit
```

`dune test` runs the calculator's unit tests. If the runtime is missing, the
build stops with "the LVGL runtime for the desktop is not built" and the
command to run.

In the device emulator (build it once, see `docs/app-development/emulator.md`):

```bash
EMU=../../projects/CardputerZero-Emulator/build/cardputer-zero-emu
dune build && $EMU --fb -- _build/default/src/main.exe
python3 ../../scripts/emulator_install.py .     # or: add it to the emulator's home screen
```

## Build for the device

OCaml has no practical cross compiler from macOS, so the device binary is built
natively in an arm64 Debian trixie container (the device's own OS and glibc),
against the device runtime and sysroot. The script mounts the repository at
the same path in the container, because the runtime's flags are absolute paths.

```bash
../../scripts/lvgl-runtime/build.sh device     # once (downloads the device sysroot)
./device/build-device.sh                       # -> device/hello-cardputer (needs Docker)
python3 ../../scripts/package_app.py .         # -> packages/hello-cardputer_0.1.0_arm64.deb
```

Install it: `scp packages/*.deb pi@<device>: && ssh pi@<device> sudo dpkg -i hello-cardputer_0.1.0_arm64.deb`.
The app appears on the home screen within a few seconds.

## Where things are

| Path | What |
| --- | --- |
| `src/main.ml` | Entry point: `Lvgl.App.run` builds the page and runs until ESC on the home screen |
| `src/app_page.ml` | The page: owns the screens, shows one at a time, routes keys. Start here. |
| `src/app_ui.ml` | Language name and color, palette, `action`, key helpers, the `screen` record |
| `src/home_screen.ml` | Home screen: wallpaper, greeting, menu |
| `src/colors_screen.ml`, `motion_screen.ml`, `repl_screen.ml`, `widgets_screen.ml` | The four demos (`widgets_screen.ml` explains how keys drive LVGL widgets on the device) |
| `src/pixel_canvas.ml` | Pixel drawing on an `lv_canvas`: `fill_rect`, `fill_circle`, `draw_line`, ... (used by Colors and Motion) |
| `src/lvgl.ml` | The LVGL and `cp0_app.h` bindings: `Lvgl.Obj`, `Label`, `Textarea`, `Group`, `Timer`, `App`, constants. How to add more is at its top |
| `src/lvgl_stubs.c` | The C side of `lvgl.ml`: one small function per call, pointer and callback handling explained at its top |
| `src/calc.ml`, `test/` | The REPL's calculator language and its tests |
| `src/dune`, `src/lvgl_flags.ml` | Build: `lvgl_flags.ml` reads `scripts/lvgl-runtime/out/<desktop\|device>/` and writes the C and link flags for dune (`CP0_LVGL_TARGET=device` selects the device) |
| `device/` | Dockerfile + script for the aarch64 build |
| `APPLaunch/applications/hello-cardputer.desktop` | Home-screen entry (name, icon, command) |
| `APPLaunch/share/images/hello-cardputer_100.png` | 100x100 icon (`scripts/make_app_icon.py` makes new ones) |
| `APPLaunch/share/images/wallpaper.png` | Home-screen picture, 320x150 (Qubix artwork, Apache-2.0; see `LICENSES/Qubix-wallpaper-Apache-2.0.txt`) |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
