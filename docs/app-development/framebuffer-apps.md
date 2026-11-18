<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Framebuffer apps (Rust, Zig, OCaml and others)

The `rust-fb`, `zig-fb` and `ocaml-fb` templates all work the same way. This
page explains the shared model; the [Rust](rust.md), [Zig](zig.md) and
[OCaml](ocaml.md) pages cover each language's toolchain and API. Any language
that can open files works the same way.

## The template app

All three templates (and, built with LVGL widgets, the C++ one) are the same
app, so you can compare languages line by line:

| Screen | What it shows | Keys |
| --- | --- | --- |
| **Home** | The wallpaper, "Hello, *Language*!" in GitHub's color for the language, and a menu | F/X choose, ENTER or 1-4 open, ESC quits |
| **Colors** | A spinning RGB triangle and an HSV color wheel, computed pixel by pixel | Z/C turn, SPACE pause, ENTER switch |
| **Motion** | A glowing ball with momentum, a trail and sparks when it bounces, plus live physics: speed, direction, velocity, kinetic energy, wall hits, a velocity arrow and a speed graph | F/X/Z/C push, ENTER color, SPACE stop |
| **REPL** | A terminal-style calculator: `x = 6 * 7`, `ans`, `abs` `min` `max`, `help`, `vars`, `clear` | type, ENTER runs, UP/DOWN history |
| **Widgets** | A form: text field, button, slider, counter, chooser (which recolors the form) and switch, with a status line | F/X move, Z/C change, ENTER press; in the text field type, ENTER moves on |

TAB jumps to the next demo and ESC goes back home. The code is split the same
way in every language:

| Module | Contents |
| --- | --- |
| `main` | Which screen shows, key dispatch, the main loop |
| `ui` | The language name and color, the palette, header and hint drawing, the `Action` a screen returns (stay, home, next, open, quit) |
| `home`, `colors`, `motion`, `repl`, `widgets` | One screen each: state, `handle_key`, `draw` (and `tick` for animation) |
| `calc` | The REPL's language: tokenizer, recursive-descent parser, evaluator. No screen code, with unit tests |
| `display`, `input`, `font` | The framebuffer canvas, the keyboard, the 8x16 font |

To make it your own, keep the screens you need and delete the others: remove
the module, its entry in `main` and its line in the home menu. A new screen is
a new module with the same three functions.

## The model: two files

| | Device | Desktop (fbsim / headless.py) |
| --- | --- | --- |
| **Screen**: write 320x170 RGB565 pixels | `$LV_LINUX_FBDEV_DEVICE` (e.g. `/dev/fb0`) | file named by `CARDPUTER_FB` (size in `CARDPUTER_FB_SIZE`, e.g. `320x170`) |
| **Keyboard**: read 24-byte `input_event` records | `$LV_LINUX_KEYBOARD_DEVICE` | FIFO named by `CARDPUTER_INPUT` |

Each template has a `display` module (an in-memory RGB565 canvas with `clear`,
`fill_rect`, `stroke_rect`, `draw_line`, `fill_circle`, `blend`/`shade_rect`,
`draw_image`, `draw_text` and `present`) and an `input` module (non-blocking `poll` returning key
events, `direction()` for F/X/Z/C and arrows, and a `Typist` that turns key
events into typed characters). `main` runs a loop that handles keys, redraws
when something changed or moves, and sleeps ~16 ms.

```
loop:
    while let event = keyboard.poll():   # never blocks
        update state; mark dirty
    if dirty: draw(canvas); canvas.present()
    sleep 16 ms                          # ~60 frames per second
```

### Pixels

RGB565 packs a color into 16 bits: 5 bits red, 6 green, 5 blue,
little-endian in memory. Use the templates' `rgb(r, g, b)` helper with ordinary
0-255 values. A pixel at `(x, y)` lives at byte offset `y * stride + x * 2`;
`present()` takes care of the stride and of 32-bit framebuffers.

### Text

The templates draw ASCII with an embedded 8x16 font (Unscii 16, public
domain): `draw_text(x, y, "text", color, scale)`; scale 1 is 8x16 px per
character, scale 2 is 16x32 (titles). At scale 1 the screen fits 40 x 10
characters, which is what the REPL demo uses. For other fonts, render them to
a bitmap at build time, or use the C++/LVGL template, which has FreeType and
many sizes.

### Keys

Act on `is_down()` events (press or auto-repeat). Use `direction(code)` for
movement so both F/X/Z/C (device) and arrows (desktop) work. **Quit on ESC.**
The launcher force-kills an app after ESC is held for 3 s, so a short press
should exit cleanly.

For text, feed **every** event (releases too, so it sees Shift) to the
`Typist` and use the character it returns, as the REPL demo does. The device
keyboard sends its symbols (`!`, `@`, `(`, ...) with special codes, listed in
the [device reference](device-reference.md#key-codes), and the Typist knows
them. It uses that device layout unless `CARDPUTER_INPUT` is set (fbsim, the
emulator, headless.py), where keys follow a US desktop keyboard. A USB
keyboard plugged into the device is read with the device layout, so its
punctuation keys type the wrong symbols.

### Images

Convert PNGs to raw RGB565 once and embed them:

```bash
python3 scripts/png_to_rgb565.py art/player.png assets/player.rgb565 --alpha
```

The file holds `u16 width, u16 height`, the pixels, and with `--alpha` one
alpha byte per pixel; `draw_image(x, y, image)` draws it, blending by the
alpha. The home screen's wallpaper is an example: a 320x170 picture without
alpha, embedded into the binary (see your language's guide for how). To use
your own, convert a 320x170 PNG over the template's `wallpaper.rgb565`.

## Running on your computer

```bash
scripts/fbsim/build.sh                         # once; needs SDL2
scripts/fbsim/fbsim -- <command that runs your app>
scripts/fbsim/fbsim --scale 3 -- ...           # bigger window (default 2x)
```

fbsim creates the two files, starts your app with the environment variables
set, shows the screen and turns your key presses into Linux key codes (arrows,
letters, digits, ENTER, ESC, BACKSPACE, TAB, SPACE, punctuation). Closing the
window stops the app.

To see the app inside the device frame, or open it from the launcher's home
screen, use the [emulator](emulator.md): `cardputer-zero-emu --fb -- <command>`.

### Automated checks (no window)

```bash
python3 scripts/fbsim/headless.py --keys "c c f enter" --png shot.png -- ./my-app
python3 scripts/fbsim/headless.py --keys "esc" --expect-exit 0 -- ./my-app
python3 scripts/fbsim/headless.py --keys "3 2 shift+8 3 enter" --png repl.png -- ./my-app
```

`headless.py` presses keys from a script, saves a PNG of the screen and checks
the exit status, which makes it handy in CI, over SSH, or inside a container.
It needs only Python. Key names are letters, digits, `esc` `backspace` `tab`
`enter` `space` `up` `down` `left` `right` and the punctuation keys (`minus`
`equal` `comma` `period` `slash` `semicolon` `apostrophe` `grave` `backslash`
`leftbracket` `rightbracket`); `shift+<name>` holds Shift, so `shift+8` types
`*` and `shift+9` types `(` (US layout).

## Running on the device

The normal way is to [package and install](packaging-and-deploying.md) the app
and start it from the home screen. While developing, a quicker loop:

```bash
scp target/aarch64-unknown-linux-gnu/release/my-app pi@<device>:/tmp/
ssh pi@<device>
systemctl --user stop APPLaunch.service     # the launcher would draw over you
/tmp/my-app                                 # output appears in your SSH session
systemctl --user start APPLaunch.service
```

Because the app is not started by the launcher in this case, the
`LV_LINUX_*` variables are not set. The templates then fall back to
`/dev/fb_lcd`, the ST7789 framebuffer and the keyboard's fixed device path. If
you get "Permission denied", add your user to the `video` and `input` groups
(`sudo usermod -aG video,input pi`, then log in again) or run with `sudo`.

## Going further

- **State that survives restarts:** write a file under `$HOME` (`/home/pi`), e.g. `~/.local/share/<app>/`.
- **Sound:** the device runs PulseAudio/PipeWire for `pi`; play files with `paplay`, or use a library such as `libpulse` or miniaudio.
- **Networking:** ordinary sockets/HTTP.
- **Bigger UIs:** keep a `screen` enum in your state and switch drawing and key handling on it; that's how the LVGL apps organize pages, too.
- **Performance:** a full frame is 108,800 bytes. Redrawing only when something changed (the templates' `dirty` flag) keeps CPU use near zero; games can simply redraw every frame.
