<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (Zig)

A CardputerZero app in Zig 0.17: it draws into the 320x170 framebuffer and
reads the keyboard as Linux input events. The device binary is fully static
(no libc), so it does not care which glibc the device has. On your computer the
`fbsim` simulator stands in for the screen and keyboard.

It greets you with "Hello, Zig!" over a wallpaper and opens three demos:
**Colors** (a spinning RGB triangle and a color wheel), **Motion** (a glowing
ball to push around) and **REPL** (a terminal-style calculator). F/X choose,
ENTER opens, TAB goes to the next demo, ESC goes back (and quits from home).
Keep what you need, delete the rest.

Full guide: [docs/app-development/zig.md](../../docs/app-development/zig.md)
(paths below assume the app lives in `projects/<Name>/`).

## Run on your computer

```bash
../../scripts/fbsim/build.sh       # once: builds the simulator (needs SDL2)
zig build sim                      # F/X choose, ENTER open, ESC back/quit
zig build test                     # the calculator's unit tests
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
| `src/main.zig` | Screen switching and the main loop. Start here. |
| `src/ui.zig` | Language name and color, palette, header and hint drawing |
| `src/home.zig` | Home screen: wallpaper, greeting, menu |
| `src/colors.zig`, `src/motion.zig`, `src/repl.zig` | The three demos |
| `src/calc.zig` | The REPL's calculator language, with tests |
| `src/display.zig` | Framebuffer canvas: `fillRect`, `fillCircle`, `drawImage`, `drawText`, `present`, `rgb`, ... |
| `src/input.zig` | Keyboard events, key codes, F/X/Z/C navigation, `Typist` for typed text |
| `src/font.zig` | Built-in 8x16 font (Unscii, public domain) |
| `src/wallpaper.rgb565` | Home-screen picture (Qubix artwork, Apache-2.0; see `LICENSES/Qubix-wallpaper-Apache-2.0.txt`) |
| `build.zig` | `zig build`, `zig build sim`, `zig build device` |
| `APPLaunch/` | Home-screen entry and 100x100 icon, installed under `/usr/share/APPLaunch` |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
