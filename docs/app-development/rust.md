<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Rust apps

The `rust-fb` template is a dependency-free Rust program that draws into the
framebuffer and reads the keyboard. Read [framebuffer apps](framebuffer-apps.md)
first for the shared model; this page covers the Rust specifics.

Want widgets (text fields, lists, sliders) instead of pixels? The `rust-lvgl` template is the
same app built with LVGL: see [LVGL apps in Rust, Zig and OCaml](lvgl-apps.md).

## Create, run, ship

```bash
python3 scripts/new_app.py rust-fb "Pixel Pet"       # -> projects/PixelPet/
cd projects/PixelPet

../../scripts/fbsim/fbsim -- cargo run               # desktop: F/X choose, ENTER open, TAB next, ESC back
#   or in the emulator: cardputer-zero-emu --fb -- cargo run   (see emulator.md)

rustup target add aarch64-unknown-linux-gnu          # once
cargo build --release --target aarch64-unknown-linux-gnu
python3 ../../scripts/package_app.py .               # packages/pixel-pet_0.1.0_arm64.deb
```

Cross-linking uses `aarch64-linux-gnu-gcc` (configured in `.cargo/config.toml`;
install it as described in [setup](setup.md)). The release profile in
`Cargo.toml` optimizes for size, enables LTO and strips symbols, which gives
a binary of roughly 400 KB.

## Project tour

The app is described in [framebuffer apps](framebuffer-apps.md#the-template-app):
a home screen and four demos.

| File | Contents |
| --- | --- |
| `src/main.rs` | `App` (the current `Screen` and each screen's state), `handle_key`, `tick`, `draw`, and the main loop in `run()` |
| `src/ui.rs` | `LANGUAGE`, `LANGUAGE_COLOR` and the palette; `draw_header`, `draw_hint`, `draw_shadowed_text`; `enum Action` |
| `src/home.rs` | The home screen: wallpaper (`include_bytes!("../assets/wallpaper.rgb565")`), greeting, menu (`DEMOS`) |
| `src/colors.rs` | RGB triangle (barycentric shading) and HSV wheel |
| `src/motion.rs` | The ball: momentum, bounces, trail, sparks; the physics readout and speed graph |
| `src/repl.rs` | The terminal-style screen: scrollback, input line, history, `help`/`vars`/`clear` |
| `src/widgets.rs` | The widget form: `Widget` rows, focus, `change` (Z/C) and `activate` (ENTER), one `draw_*` function per widget |
| `src/calc.rs` | The calculator language (`Calculator::run(line) -> Result<String, String>`) and its unit tests |
| `src/display.rs` | `Display::open()`, `width()`, `height()`, `clear`, `fill_rect`, `set_pixel`, `blend_pixel`, `shade_rect`, `stroke_rect`, `draw_line`, `fill_circle`, `draw_image`, `draw_text(x, y, text, color, scale) -> width`, `Display::text_width`, `present()`; `rgb(r, g, b)`, `blend(under, over, alpha)`, `BLACK`, `WHITE`, `CHAR_WIDTH`, `CHAR_HEIGHT` |
| `src/input.rs` | `Keyboard::open()`, `poll() -> Option<KeyEvent>`; `KeyEvent { code, state }`, `is_down()`; `keys::*`; `direction(code) -> Option<Direction>`; `Typist::new()`, `char_for(event) -> Option<char>` |
| `src/font.rs` | The 8x16 glyph table |
| `assets/wallpaper.rgb565` | The home screen's 320x170 picture |

Errors are `std::io::Error`: `main` prints them and exits with status 1, which
you will see in `journalctl --user -u APPLaunch.service` on the device.

## Common tasks

**Start from one demo.** Delete the screens you don't want: remove the
`mod`, its field and `Screen` variant in `main.rs`, its entry in
`DEMO_SCREENS` and in `home::DEMOS`. Or make one demo the whole app by
starting `App` on its screen.

**A new screen.** Copy the shape of `motion.rs`: a struct with
`handle_key(event) -> Action`, `draw(&self, display)` and, if it animates,
`tick()`. Add a `Screen` variant, the match arms in `main.rs`, and a line in
`home::DEMOS` and `DEMO_SCREENS`.

**Timed updates (animation, games).** `App::tick` runs every frame and returns
whether to redraw; the demos advance by one frame per tick. For speed that
doesn't depend on the frame rate, pass the elapsed time:

```rust
let mut last = std::time::Instant::now();
// in the loop:
let now = std::time::Instant::now();
app.update(now - last);          // move things by elapsed time
last = now;
```

**Text input.** Pass every event to `Typist::char_for` (see `run()`), then use
the character in the screen that wants text, as `Repl::handle_key` and the
Widgets text field do.

**Forms and widgets.** `widgets.rs` shows the pattern: a list of rows, one
focused index, and per-widget functions to change, activate and draw. Add a
row by adding a `Widget` variant, its label in `ROWS`, and arms in `change`,
`activate` and `draw`.

**Images.** Convert with `scripts/png_to_rgb565.py art/player.png assets/player.rgb565 --alpha`
and draw with `display.draw_image(10, 30, include_bytes!("../assets/player.rgb565"))`
(a `const` like `home.rs`'s `WALLPAPER` keeps it tidy). A new wallpaper:
`python3 ../../scripts/png_to_rgb565.py my-picture.png assets/wallpaper.rgb565`
with a 320x170 PNG.

**Saving data.** `std::env::var("HOME")` is `/home/pi` on the device; write to
`$HOME/.local/share/pixel-pet/` with `std::fs`.

**Crates.** Add whatever you like to `Cargo.toml`. Pure-Rust crates
cross-compile without effort. Crates with C dependencies (OpenSSL, SQLite, ...)
need either the device sysroot or a pure-Rust alternative (rustls instead of
OpenSSL, for example). If you want more drawing primitives, the
[`embedded-graphics`](https://crates.io/crates/embedded-graphics) crate works
well on top of `Display`: implement its `DrawTarget` trait with `fill_rect`.

## Testing

```bash
cargo test                                                       # unit tests (calc.rs has some)
cargo build && python3 ../../scripts/fbsim/headless.py \
    --keys "3 6 shift+8 7 enter" --png /tmp/shot.png -- ./target/debug/pixel-pet
```

To check the device binary itself on a Mac with Docker/OrbStack (Debian
trixie, arm64, same as the device):

```bash
docker run --rm --platform linux/arm64 -v "$PWD/../..":/repo -w /repo/projects/PixelPet \
    python:3-slim python3 /repo/scripts/fbsim/headless.py --keys esc --expect-exit 0 \
    -- ./target/aarch64-unknown-linux-gnu/release/pixel-pet
```
