<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (Rust)

A CardputerZero app in plain Rust (no crates): it draws into the 320x170
framebuffer and reads the keyboard as Linux input events. On your computer the
`fbsim` simulator stands in for both, so the code you run is the code that
ships.

Full guide: [docs/app-development/rust.md](../../docs/app-development/rust.md)
(paths below assume the app lives in `projects/<Name>/`).

## Run on your computer

```bash
../../scripts/fbsim/build.sh                       # once: builds the simulator (needs SDL2)
../../scripts/fbsim/fbsim -- cargo run             # F/X/Z/C or arrows move, ENTER color, ESC quits
```

In the device emulator (build it once, see `docs/app-development/emulator.md`):

```bash
EMU=../../projects/CardputerZero-Emulator/build/cardputer-zero-emu
cargo build && $EMU --fb -- target/debug/hello-cardputer
python3 ../../scripts/emulator_install.py .     # or: add it to the emulator's home screen
```

## Build for the device

```bash
rustup target add aarch64-unknown-linux-gnu         # once
cargo build --release --target aarch64-unknown-linux-gnu
python3 ../../scripts/package_app.py .              # -> packages/hello-cardputer_0.1.0_arm64.deb
```

The linker is `aarch64-linux-gnu-gcc` (`.cargo/config.toml`): on macOS
`brew tap messense/macos-cross-toolchains && brew install aarch64-unknown-linux-gnu`,
on Debian/Ubuntu `sudo apt install gcc-aarch64-linux-gnu`.

Install it: `scp packages/*.deb pi@<device>: && ssh pi@<device> sudo dpkg -i hello-cardputer_0.1.0_arm64.deb`.

## Where things are

| Path | What |
| --- | --- |
| `src/main.rs` | The app: `App::handle_key` and `App::draw`. Start here. |
| `src/display.rs` | Framebuffer canvas: `clear`, `fill_rect`, `draw_text`, `present`, `rgb` |
| `src/input.rs` | Keyboard events, key codes, F/X/Z/C navigation |
| `src/font.rs` | Built-in 8x8 font (Unscii, public domain) |
| `APPLaunch/` | Home-screen entry and 100x100 icon, installed under `/usr/share/APPLaunch` |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |
