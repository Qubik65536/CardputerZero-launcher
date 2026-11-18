<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Build your own CardputerZero app

The CardputerZero is a pocket Linux computer: an AArch64 board running Debian 13
("trixie"), a **320x170** color LCD and a built-in keyboard. Its home screen,
**APPLaunch**, starts apps listed as `.desktop` entries. An app is simply a Linux
program that APPLaunch starts; this guide shows how to write one in C++, Rust,
Zig or OCaml (or anything that runs in a terminal), test it on your computer,
and install it on the device.

## Pick a starting point

| You want... | Use | Language guide |
| --- | --- | --- |
| An app that looks like the built-in ones (LVGL widgets, top bar with clock and battery) | `cpp-lvgl` template | [C++ / LVGL](cpp-lvgl.md) |
| Full control of every pixel (games, visualizations, custom UIs) in Rust | `rust-fb` template | [Rust](rust.md) |
| The same in Zig (static binary, zero-setup cross-compiling) | `zig-fb` template | [Zig](zig.md) |
| The same in OCaml | `ocaml-fb` template | [OCaml](ocaml.md) |
| A text/CLI program in any language (Python, Go, shell, ...) | no template needed | [Terminal apps](terminal-apps.md) |

The three `*-fb` templates share one design: the app writes RGB565 pixels to the
Linux framebuffer and reads key presses from the keyboard's evdev device. These
are plain files, so no graphics library, binding or SDK is needed. On your computer,
`fbsim` (a small SDL2 window) or the [emulator](emulator.md) stands in for both
files, so the code you test is exactly the code that runs on the device.

## 10-minute quick start (Rust example; the others are the same shape)

```bash
# 1. Once per machine: see setup.md for your OS (Python venv, SDL2, toolchains)
git clone --recursive https://github.com/CardputerZero/launcher.git && cd launcher
scripts/fbsim/build.sh                                  # desktop simulator

# 2. Create your app from a template
python3 scripts/new_app.py rust-fb "Pixel Pet"          # -> projects/PixelPet/
cd projects/PixelPet

# 3. Run it on your computer
../../scripts/fbsim/fbsim -- cargo run                  # F/X/Z/C or arrows move, ESC quits
#    ...or inside the device emulator (see emulator.md)
../../projects/CardputerZero-Emulator/build/cardputer-zero-emu --fb -- cargo run

# 4. Build for the device and package it
cargo build --release --target aarch64-unknown-linux-gnu
python3 ../../scripts/package_app.py .                  # -> packages/pixel-pet_0.1.0_arm64.deb

# 5. Install on the device (it appears on the home screen within ~3 s)
scp packages/pixel-pet_0.1.0_arm64.deb pi@<device-ip>:
ssh pi@<device-ip> sudo dpkg -i pixel-pet_0.1.0_arm64.deb
```

## How it fits together

```
your app (projects/MyApp/)                    on the device (/usr/share/APPLaunch/)
├── source code            ── build ──▶       bin/my-app                     the program
├── APPLaunch/applications/my-app.desktop ─▶  applications/my-app.desktop   home-screen entry
├── APPLaunch/share/images/my-app_100.png ─▶  share/images/my-app_100.png   100x100 icon
└── cardputer-app.json     ── scripts/package_app.py ──▶ my-app_0.1.0_arm64.deb
```

1. APPLaunch watches `/usr/share/APPLaunch/applications/` and adds a home-screen
   card for each valid `.desktop` file.
2. When the user opens the card, APPLaunch stops drawing and runs `Exec`. Your app
   owns the screen and gets the keyboard, until it exits.
3. When your app exits, APPLaunch redraws the home screen. Holding **ESC for 3
   seconds** always force-quits an app (SIGTERM, then SIGKILL 3 s later), so
   apps should quit on a short ESC press themselves.

Details: [device reference](device-reference.md).

## All guides

| Guide | Contents |
| --- | --- |
| [Setup](setup.md) | Installing everything on macOS, Linux and Windows |
| [Bundled projects](bundled-projects.md) | Building and running every project in `projects/` (good first test of your setup) |
| [C++ / LVGL](cpp-lvgl.md) | LVGL pages, widgets, keys, fonts, images, platform services |
| [Emulator](emulator.md) | Running your app in the device emulator, directly or from its home screen; scripted tests |
| [Framebuffer apps](framebuffer-apps.md) | The shared model of the Rust/Zig/OCaml templates: pixels, keys, fbsim, headless tests, images, running on the device |
| [Rust](rust.md) · [Zig](zig.md) · [OCaml](ocaml.md) | Each language's toolchain, API and recipes |
| [Terminal apps](terminal-apps.md) | Text programs in any language, terminal size and keys |
| [Device reference](device-reference.md) | Screen, keyboard codes, `.desktop` rules, environment, paths |
| [Packaging and deploying](packaging-and-deploying.md) | `.deb` packages, installing over SSH/ADB, logs, publishing to the App Store |
| [Troubleshooting](troubleshooting.md) | The app is missing, crashes, shows nothing, ignores keys, ... |

## Tools in this repository

| Tool | What it does |
| --- | --- |
| `scripts/new_app.py <template> "Name"` | Creates an app from a template, renamed |
| `scripts/fbsim/fbsim -- <app>` | Desktop window that stands in for the device screen and keyboard |
| `scripts/fbsim/headless.py --keys ... --png ... -- <app>` | Same, without a window: scripted keys, screenshot (for CI and tests) |
| `cardputer-zero-emu --fb -- <app>` | Runs the app in the device emulator (`projects/CardputerZero-Emulator`) |
| `scripts/emulator_install.py <app-dir>` | Adds the app to the emulator's home screen |
| `scripts/package_app.py <app-dir>` | Builds the arm64 `.deb` and checks the launcher's rules |
| `scripts/make_app_icon.py XY -o icon.png` | Makes a 100x100 placeholder icon |
| `scripts/linux-sim/linux-sim.sh` | Builds/runs/tests Linux-only projects in Docker, viewable over VNC |
