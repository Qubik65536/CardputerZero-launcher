<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (OCaml)

A CardputerZero app in OCaml 5 using only the standard library and `unix`: it
draws into the 320x170 framebuffer and reads the keyboard as Linux input
events. On your computer the `fbsim` simulator stands in for both.

It greets you with "Hello, OCaml!" over a wallpaper and opens three demos:
**Colors** (a spinning RGB triangle and a color wheel), **Motion** (a glowing
ball to push around) and **REPL** (a terminal-style calculator). F/X choose,
ENTER opens, TAB goes to the next demo, ESC goes back (and quits from home).
Keep what you need, delete the rest.

Full guide: [docs/app-development/ocaml.md](../../docs/app-development/ocaml.md)
(paths below assume the app lives in `projects/<Name>/`).

## Run on your computer

```bash
opam install dune                  # or: brew install dune / apt install ocaml-dune
../../scripts/fbsim/build.sh       # once: builds the simulator (needs SDL2)
dune build
../../scripts/fbsim/fbsim -- ./_build/default/src/main.exe
```

F/X choose, ENTER opens, ESC goes back (and quits from home). `dune test`
runs the calculator's unit tests.

In the device emulator (build it once, see `docs/app-development/emulator.md`):

```bash
EMU=../../projects/CardputerZero-Emulator/build/cardputer-zero-emu
dune build && $EMU --fb -- _build/default/src/main.exe
python3 ../../scripts/emulator_install.py .     # or: add it to the emulator's home screen
```

## Build for the device

OCaml has no practical cross compiler from macOS, so the device binary is built
natively in an arm64 Debian trixie container (the device's own OS and glibc):

```bash
./device/build-device.sh                       # -> device/hello-cardputer (needs Docker)
python3 ../../scripts/package_app.py .         # -> packages/hello-cardputer_0.1.0_arm64.deb
```

Or build on the device itself: `sudo apt install ocaml-nox ocaml-dune && dune build --profile release`.
Install it: `scp packages/*.deb pi@<device>: && ssh pi@<device> sudo dpkg -i hello-cardputer_0.1.0_arm64.deb`.

## Where things are

| Path | What |
| --- | --- |
| `src/main.ml` | Screen switching and the main loop. Start here. |
| `src/ui.ml` | Language name and color, palette, header and hint drawing |
| `src/home.ml` | Home screen: wallpaper, greeting, menu |
| `src/colors.ml`, `src/motion.ml`, `src/repl.ml` | The three demos |
| `src/calc.ml`, `test/` | The REPL's calculator language and its tests |
| `src/display.ml` | Framebuffer canvas: `fill_rect`, `fill_circle`, `draw_image`, `draw_text`, `present`, `rgb`, ... |
| `src/input.ml` | Keyboard events, key codes, F/X/Z/C navigation, typist for typed text |
| `src/font.ml` | Built-in 8x16 font (Unscii, public domain) |
| `src/wallpaper.rgb565` | Home-screen picture (Qubix artwork, Apache-2.0; see `LICENSES/Qubix-wallpaper-Apache-2.0.txt`), embedded by `src/embed.ml` |
| `device/` | Dockerfile + script for the aarch64 build |
| `APPLaunch/` | Home-screen entry and 100x100 icon, installed under `/usr/share/APPLaunch` |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
