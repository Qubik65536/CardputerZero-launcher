<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (Zig)

A CardputerZero app in Zig 0.17: it draws into the 320x170 framebuffer and
reads the keyboard as Linux input events. The device binary is fully static
(no libc), so it does not care which glibc the device has. On your computer the
`fbsim` simulator stands in for the screen and keyboard.

Full guide: [docs/app-development/zig.md](../../docs/app-development/zig.md)
(paths below assume the app lives in `projects/<Name>/`).

## Run on your computer

```bash
../../scripts/fbsim/build.sh       # once: builds the simulator (needs SDL2)
zig build sim                      # F/X/Z/C or arrows move, ENTER color, ESC quits
```

If the app lives elsewhere: `zig build sim -Dfbsim=/path/to/launcher/scripts/fbsim/fbsim`.

In the device emulator (build it once, see `docs/app-development/emulator.md`):

```bash
EMU=../../projects/CardputerZero-Emulator/build/cardputer-zero-emu
zig build && $EMU --fb -- zig-out/bin/hello-cardputer
python3 ../../scripts/emulator_install.py .     # or: add it to the emulator's home screen
```

## Build for the device

```bash
zig build device                               # -> zig-out/device/hello-cardputer (static aarch64)
python3 ../../scripts/package_app.py .         # -> packages/hello-cardputer_0.1.0_arm64.deb
```

No cross toolchain or sysroot needed: Zig cross-compiles by itself.
Install it: `scp packages/*.deb pi@<device>: && ssh pi@<device> sudo dpkg -i hello-cardputer_0.1.0_arm64.deb`.

## Where things are

| Path | What |
| --- | --- |
| `src/main.zig` | The app: `App.handleKey` and `App.draw`. Start here. |
| `src/display.zig` | Framebuffer canvas: `clear`, `fillRect`, `drawText`, `present`, `rgb` |
| `src/input.zig` | Keyboard events, key codes, F/X/Z/C navigation |
| `src/font.zig` | Built-in 8x8 font (Unscii, public domain) |
| `build.zig` | `zig build`, `zig build sim`, `zig build device` |
| `APPLaunch/` | Home-screen entry and 100x100 icon, installed under `/usr/share/APPLaunch` |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
