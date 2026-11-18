<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (Zig / LVGL)

A CardputerZero app in Zig 0.17 built like the launcher's own apps: LVGL 9.5
widgets, the standard top bar (title, clock, battery) and the `cp0_lvgl`
platform layer, called through its C API
[`cp0_app.h`](../../ext_components/cp0_lvgl/include/cp0_app.h). It runs as an
SDL window on your desktop and full-screen on the device.

It greets you with "Hello, Zig!" over a wallpaper and opens four demos:
**Colors** (a spinning RGB triangle and a color wheel drawn on an
`lv_canvas`), **Motion** (a glowing ball to push around, with live physics
numbers), **REPL** (a terminal-style calculator) and **Widgets** (stock LVGL
widgets with the default theme, flex layout and a focus group: text area,
buttons, slider, spinbox, dropdown, switch, checkbox, driven by the keyboard).
F/X choose, ENTER opens, TAB goes to the next demo, ESC goes back
(and quits from home). It is the same app as the C++ template `cpp-lvgl`.
Keep what you need, delete the rest.

Full guide: [docs/app-development/lvgl-apps.md](../../docs/app-development/lvgl-apps.md).
Paths below assume the app lives in `projects/<Name>/` of the launcher
repository; run every command from the app's directory.

## Build the LVGL runtime (once)

The app links against a prebuilt runtime: LVGL, `cp0_lvgl` and `cp0_app.h`
(see [scripts/lvgl-runtime](../../scripts/lvgl-runtime/README.md)). Build it
once per machine, with the Python environment from
[setup](../../docs/app-development/setup.md) active:

```bash
../../scripts/lvgl-runtime/build.sh desktop    # for zig build / zig build run
../../scripts/lvgl-runtime/build.sh device     # for zig build device (downloads the device sysroot)
```

Run it again after pulling changes to `ext_components/cp0_lvgl` or LVGL. If
the runtime is missing, `zig build` says which command to run. For an app
outside the repository, add `-Dlvgl-runtime=/path/to/launcher/scripts/lvgl-runtime`
to every `zig build` command.

## Run on your computer

```bash
zig build run       # SDL window; F/X choose, ENTER open, ESC back/quit
zig build test      # the unit tests (calculator, Motion readout); no runtime needed
```

`zig build` alone puts the binary in `zig-out/bin/hello-cardputer`. Start it
from this directory: it loads its images from `./APPLaunch/share/images`.

In the device emulator (build it once, see `docs/app-development/emulator.md`):

```bash
EMU=../../projects/CardputerZero-Emulator/build/cardputer-zero-emu
zig build && $EMU --fb -- zig-out/bin/hello-cardputer
python3 ../../scripts/emulator_install.py .     # or: add it to the emulator's home screen
```

Headless, e.g. for a screenshot:
`python3 ../../scripts/fbsim/headless.py --settle 2.5 --keys "4" --png shot.png -- zig-out/bin/hello-cardputer`.

## Build for the device

```bash
zig build device                               # -> zig-out/device/hello-cardputer (aarch64, glibc 2.41)
python3 ../../scripts/package_app.py .         # -> packages/hello-cardputer_0.1.0_arm64.deb
```

Zig cross-compiles by itself; the device runtime brings the sysroot to link
against. The binary uses libraries every CardputerZero has (libinput,
xkbcommon, FreeType, libstdc++). Install it:
`scp packages/*.deb pi@<device>: && ssh pi@<device> sudo dpkg -i hello-cardputer_0.1.0_arm64.deb`.
The app appears on the home screen within a few seconds.

## Where things are

| Path | What |
| --- | --- |
| `src/main.zig` | Entry point and the app: `cp0_app_run`, the setup (sets the theme first) and key callbacks, showing one screen at a time. Start here. |
| `src/lvgl.zig` | The C functions the app calls (LVGL and `cp0_app.h`), declared by hand, plus small helpers. Its header explains how to add more. |
| `src/ui.zig` | Language name and color, palette, `setTheme()`, `Action`, key helpers, label/panel helpers, `Screen` (container + frame timer) |
| `src/home.zig` | Home screen: wallpaper, greeting, menu |
| `src/colors.zig`, `src/motion.zig`, `src/repl.zig`, `src/widgets.zig` | The four demos (`widgets.zig` explains how keys drive LVGL widgets on the device) |
| `src/pixel_canvas.zig` | Pixel drawing on an `lv_canvas`: `fillRect`, `fillCircle`, `drawLine`, ... (used by Colors and Motion) |
| `src/calc.zig` | The REPL's calculator language (plain Zig, no LVGL), with tests |
| `build.zig` | `zig build`, `run`, `device`, `test`; links the runtime from its `ldflags.txt` |
| `APPLaunch/applications/hello-cardputer.desktop` | Home-screen entry (name, icon, command) |
| `APPLaunch/share/images/hello-cardputer_100.png` | 100x100 icon (`scripts/make_app_icon.py` makes new ones) |
| `APPLaunch/share/images/wallpaper.png` | Home-screen picture, 320x150 (Qubix artwork, Apache-2.0; see `LICENSES/Qubix-wallpaper-Apache-2.0.txt`) |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
