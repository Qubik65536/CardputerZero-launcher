<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# OCaml apps

The `ocaml-fb` template is an OCaml 5 program that uses only the standard
library and `unix` to draw into the framebuffer and read the keyboard. Read
[framebuffer apps](framebuffer-apps.md) first for the shared model; this page
covers the OCaml specifics.

## Create, run, ship

```bash
python3 scripts/new_app.py ocaml-fb "Pixel Pet"      # -> projects/PixelPet/
cd projects/PixelPet

dune build
../../scripts/fbsim/fbsim -- ./_build/default/src/main.exe     # desktop
#   or in the emulator: cardputer-zero-emu --fb -- _build/default/src/main.exe   (see emulator.md)

./device/build-device.sh                             # device/pixel-pet (aarch64), needs Docker
python3 ../../scripts/package_app.py .               # packages/pixel-pet_0.1.0_arm64.deb
```

### Why the device build uses Docker

OCaml compiles to native code for the machine it runs on, and there is no
maintained macOS → aarch64-Linux cross compiler. `device/build-device.sh`
therefore compiles natively inside an **arm64 Debian 13 (trixie)** container,
the device's own OS and glibc version, using Debian's `ocaml-nox` and
`ocaml-dune` (OCaml 5.3). On Apple Silicon (Docker Desktop or OrbStack) the
container runs natively and takes seconds. On x86_64 hosts Docker emulates
arm64, which is slower but works. The first run builds a small image
(`cardputerzero-ocaml-arm64`).

Alternatives: build on the device itself (`sudo apt install ocaml-nox ocaml-dune`,
then `dune build --profile release`), or use any arm64 Linux machine running
Debian trixie.

## Project tour

The app is described in [framebuffer apps](framebuffer-apps.md#the-template-app):
a home screen and three demos.

| File | Contents |
| --- | --- |
| `src/main.ml` | `app` (the current `screen` and each screen's state), `handle_key`, `tick`, `draw`, and the loop |
| `src/ui.ml` | `language`, `language_color` and the palette; `draw_header`, `draw_hint`, `draw_shadowed_text`; `type action` |
| `src/home.ml` | The home screen: wallpaper (`Wallpaper.data`), greeting, menu (`demos`) |
| `src/colors.ml` | RGB triangle (barycentric shading) and HSV wheel |
| `src/motion.ml` | The ball: momentum, bounces, trail, sparks |
| `src/repl.ml` | The terminal-style screen: scrollback, input line, history, `help`/`vars`/`clear` |
| `src/calc.ml` | The calculator language (`Calc.run calculator line : (string, string) result`), a library of its own so the tests can use it |
| `src/display.ml` | `open_display ()`, `width`, `height`, `clear`, `fill_rect d x y w h color`, `set_pixel`, `blend_pixel`, `shade_rect`, `fill_circle`, `draw_image d x y image`, `draw_text d x y text color scale`, `text_width`, `present`, `close`; `rgb r g b`, `blend`, `black`, `white`, `char_width`, `char_height` |
| `src/input.ml` | `open_keyboard ()`, `poll : t -> event option`, `close`; `event = { code; state }`, `is_down`; `Keys.*`; `direction code : direction option`; `create_typist ()`, `char_for typist event : char option` |
| `src/font.ml` | The 8x16 glyph table |
| `src/wallpaper.rgb565`, `src/embed.ml` | The home screen's 320x170 picture, and the script that embeds it (see Images) |
| `src/dune` | Library `calc`, executable `main` (libraries `unix`), the wallpaper rule |
| `test/` | `test_calc.ml`, run by `dune test` |
| `device/` | Dockerfile and build script for the aarch64 binary |

## Common tasks

**Start from one demo.** Delete the screens you don't want: remove the
module, its `screen` case and field in `main.ml`, its entry in
`demo_screens` and in `Home.demos`. Or make one demo the whole app by starting
on its screen.

**A new screen.** Copy the shape of `motion.ml`: a state record with
`handle_key`, `draw` and, if it animates, `tick`. Add a `screen` case, the
`match` arms in `main.ml`, and entries in `Home.demos` and `demo_screens`.

**Timed updates.** `tick` runs every frame; the demos advance by one frame per
tick. For speed that doesn't depend on the frame rate, read
`Unix.gettimeofday ()` each frame and pass the difference to your update.

**Text input.** Pass every event to `Input.char_for` (see `main.ml`), then use
the character in the screen that wants text, as `Repl.handle_key` does.

**Images.** OCaml has no `include_bytes`, so `src/dune` has a rule that runs
`src/embed.ml` with the `ocaml` toplevel to turn `wallpaper.rgb565` into the
module `Wallpaper` (`let data = "..."`). For another picture, convert it with
`scripts/png_to_rgb565.py art/player.png src/player.rgb565 --alpha`, copy the
rule with `player.ml` / `player.rgb565`, and draw it with
`Display.draw_image display 10 30 Player.data`. A new wallpaper:
`python3 ../../scripts/png_to_rgb565.py my-picture.png src/wallpaper.rgb565`
with a 320x170 PNG.

**Saving data.** `Sys.getenv "HOME"` is `/home/pi`; write under
`~/.local/share/<app>/`.

**opam libraries.** Add them to `src/dune`. Pure-OCaml libraries work
anywhere. For the device build, install them in `device/Dockerfile`: use
Debian packages (`libfoo-ocaml-dev`), or add opam to the image.

## Testing

```bash
dune test                                          # test/test_calc.ml
dune build && python3 ../../scripts/fbsim/headless.py \
    --keys "3 6 shift+8 7 enter" --png /tmp/shot.png -- ./_build/default/src/main.exe
```
