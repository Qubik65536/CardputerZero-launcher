<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (OCaml)

A CardputerZero app in OCaml 5 using only the standard library and `unix`: it
draws into the 320x170 framebuffer and reads the keyboard as Linux input
events. On your computer the `fbsim` simulator stands in for both.

Full guide: [docs/app-development/ocaml.md](../../docs/app-development/ocaml.md)
(paths below assume the app lives in `projects/<Name>/`).

## Run on your computer

```bash
opam install dune                  # or: brew install dune / apt install ocaml-dune
../../scripts/fbsim/build.sh       # once: builds the simulator (needs SDL2)
dune build
../../scripts/fbsim/fbsim -- ./_build/default/src/main.exe
```

F/X/Z/C or arrows move, ENTER changes color, ESC quits.

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
| `src/main.ml` | The app: `handle_key` and `draw`. Start here. |
| `src/display.ml` | Framebuffer canvas: `clear`, `fill_rect`, `draw_text`, `present`, `rgb` |
| `src/input.ml` | Keyboard events, key codes, F/X/Z/C navigation |
| `src/font.ml` | Built-in 8x8 font (Unscii, public domain) |
| `device/` | Dockerfile + script for the aarch64 build |
| `APPLaunch/` | Home-screen entry and 100x100 icon, installed under `/usr/share/APPLaunch` |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
