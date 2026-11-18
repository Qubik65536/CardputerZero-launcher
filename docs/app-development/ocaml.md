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

| File | Contents |
| --- | --- |
| `src/main.ml` | `app` (your state), `handle_key`, `draw`, and the loop |
| `src/display.ml` | `open_display ()`, `width`, `height`, `clear`, `fill_rect d x y w h color`, `draw_text d x y text color scale`, `text_width`, `present`, `close`; `rgb r g b`, `black`, `white` |
| `src/input.ml` | `open_keyboard ()`, `poll : t -> event option`, `close`; `event = { code; state }`, `is_down`; `Keys.*`; `direction code : direction option` |
| `src/font.ml` | The 8x8 glyph table |
| `src/dune` | Executable `main`, libraries `unix` |
| `device/` | Dockerfile and build script for the aarch64 binary |

## Common tasks

**A new screen or mode.** Add `mutable screen : [ `Menu | `Game | `Game_over ]`
to `app`, and `match` on it in `handle_key` and `draw`.

**Timed updates.** `Unix.gettimeofday ()` each frame; pass the difference to an
`update` function and redraw every frame.

**Images.** Convert with `scripts/png_to_rgb565.py art/player.png assets/player.rgb565 --alpha`,
install the file next to your binary (put it under `APPLaunch/share/` so the
package installs it to `/usr/share/APPLaunch/share/...`), and add to `display.ml`:

```ocaml
(* Draw an image made by scripts/png_to_rgb565.py (with or without --alpha). *)
let draw_image display x y image =
  let width = Bytes.get_uint16_le image 0 and height = Bytes.get_uint16_le image 2 in
  let has_alpha = Bytes.length image >= 4 + (width * height * 3) in
  for row = 0 to height - 1 do
    for column = 0 to width - 1 do
      let index = (row * width) + column in
      if not (has_alpha && Bytes.get_uint8 image (4 + (width * height * 2) + index) < 128) then
        fill_rect display (x + column) (y + row) 1 1 (Bytes.get_uint16_le image (4 + (index * 2)))
    done
  done

let load_image path = In_channel.with_open_bin path In_channel.input_all |> Bytes.of_string
```

**Saving data.** `Sys.getenv "HOME"` is `/home/pi`; write under
`~/.local/share/<app>/`.

**opam libraries.** Add them to `src/dune`. Pure-OCaml libraries work
anywhere. For the device build, install them in `device/Dockerfile`: use
Debian packages (`libfoo-ocaml-dev`), or add opam to the image.

## Testing

```bash
dune build && python3 ../../scripts/fbsim/headless.py \
    --keys "c c enter esc" --png /tmp/shot.png --expect-exit 0 -- ./_build/default/src/main.exe
```

Add `(test ...)` stanzas to `src/dune` for unit tests (`dune test`).
