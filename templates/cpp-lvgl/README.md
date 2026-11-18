<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (C++ / LVGL)

A CardputerZero app built like the launcher's own apps: LVGL 9.5 widgets, the
standard top bar (title, clock, battery) and the `cp0_lvgl` platform layer, so
it runs as an SDL window on your desktop and full-screen on the device.

Full guide: [docs/app-development/cpp-lvgl.md](../../docs/app-development/cpp-lvgl.md).
Run every command from this directory (it must stay at `projects/<Name>/`).

## Run on your computer

```bash
scons -j8                          # picks the macOS or Linux SDL2 profile
cd dist && ./hello-cardputer       # Up/Down change the number, ESC quits
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
| `main/ui/hello_cardputer_page.cpp` | The screen: widgets and key handling. Start here. |
| `main/src/main.cpp` | Entry point: runs the page until ESC |
| `main/SConstruct` | Sources, libraries, executable name |
| `APPLaunch/applications/hello-cardputer.desktop` | Home-screen entry (name, icon, command) |
| `APPLaunch/share/images/hello-cardputer_100.png` | 100x100 icon (`scripts/make_app_icon.py` makes new ones) |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
| `*_config_defaults.mk` | Build profiles: `darwin` (macOS window), `linux_x86_sdl2` (Linux window), `linux_x86_cross_cp0` (device, from macOS or Linux), `config_defaults` (building on the device) |

Switching profiles is automatic; if a build ever looks stale, run `scons distclean`.
