<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Rust apps

The `rust-fb` template is a dependency-free Rust program that draws into the
framebuffer and reads the keyboard. Read [framebuffer apps](framebuffer-apps.md)
first for the shared model; this page covers the Rust specifics.

## Create, run, ship

```bash
python3 scripts/new_app.py rust-fb "Pixel Pet"       # -> projects/PixelPet/
cd projects/PixelPet

../../scripts/fbsim/fbsim -- cargo run               # desktop (F/X/Z/C or arrows, ENTER, ESC)
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

| File | Contents |
| --- | --- |
| `src/main.rs` | `App` (your state), `handle_key`, `draw`, and the main loop in `run()` |
| `src/display.rs` | `Display::open()`, `width()`, `height()`, `clear(color)`, `fill_rect(x, y, w, h, color)`, `draw_text(x, y, text, color, scale) -> width`, `Display::text_width(text, scale)`, `present()`; `rgb(r, g, b)`, `BLACK`, `WHITE` |
| `src/input.rs` | `Keyboard::open()`, `poll() -> Option<KeyEvent>`; `KeyEvent { code, state }`, `is_down()`; `keys::*` constants; `direction(code) -> Option<Direction>` |
| `src/font.rs` | The 8x8 glyph table |

Errors are `std::io::Error`: `main` prints them and exits with status 1, which
you will see in `journalctl --user -u APPLaunch.service` on the device.

## Common tasks

**A new screen or mode.** Add an `enum Screen { Menu, Game, GameOver }` field to
`App`, branch in `handle_key` and `draw`.

**Timed updates (animation, games).** Redraw every frame instead of only when
dirty, and advance your simulation by the elapsed time:

```rust
let mut last = std::time::Instant::now();
while app.running {
    while let Some(event) = keyboard.poll() { app.handle_key(event, &display); }
    let now = std::time::Instant::now();
    app.update(now - last);          // move things by elapsed time
    last = now;
    app.draw(&mut display);
    display.present()?;
    std::thread::sleep(FRAME_TIME);
}
```

**Images.** Convert with `scripts/png_to_rgb565.py art/player.png assets/player.rgb565 --alpha`,
then add this to `src/display.rs` (inside `impl Display`):

```rust
/// Draw an image made by scripts/png_to_rgb565.py (with or without --alpha).
pub fn draw_image(&mut self, x: i32, y: i32, image: &[u8]) {
    let width = u16::from_le_bytes([image[0], image[1]]) as usize;
    let height = u16::from_le_bytes([image[2], image[3]]) as usize;
    let pixels = &image[4..4 + width * height * 2];
    let alpha = image.get(4 + width * height * 2..);
    for row in 0..height {
        for column in 0..width {
            let index = row * width + column;
            if alpha.is_some_and(|alpha| alpha[index] < 128) {
                continue; // transparent
            }
            let color = u16::from_le_bytes([pixels[index * 2], pixels[index * 2 + 1]]);
            self.fill_rect(x + column as i32, y + row as i32, 1, 1, color);
        }
    }
}
```

and use it with `display.draw_image(10, 30, include_bytes!("../assets/player.rgb565"));`.

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
cargo test                                                       # your unit tests
cargo build && python3 ../../scripts/fbsim/headless.py \
    --keys "c c enter esc" --png /tmp/shot.png --expect-exit 0 -- ./target/debug/pixel-pet
```

To check the device binary itself on a Mac with Docker/OrbStack (Debian
trixie, arm64, same as the device):

```bash
docker run --rm --platform linux/arm64 -v "$PWD/../..":/repo -w /repo/projects/PixelPet \
    python:3-slim python3 /repo/scripts/fbsim/headless.py --keys esc --expect-exit 0 \
    -- ./target/aarch64-unknown-linux-gnu/release/pixel-pet
```
