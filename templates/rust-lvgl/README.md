<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Hello Cardputer (Rust / LVGL)

A CardputerZero app in Rust that builds its UI with LVGL 9.5, the widget
library the launcher uses: the standard top bar (title, clock, battery),
fonts, labels, buttons, sliders and more, through the `cp0_lvgl` platform
layer. It runs as an SDL window on your desktop and full-screen on the device.
No crates and no bindgen: `src/lvgl.rs` declares the C functions by hand.

It greets you with "Hello, Rust!" over a wallpaper and opens four demos:
**Colors** (a spinning RGB triangle and a color wheel drawn on an
`lv_canvas`), **Motion** (a glowing ball to push around, with live physics
numbers), **REPL** (a terminal-style calculator) and **Widgets** (real LVGL
widgets: text field, button, slider, counter, roller, switch, driven by the
keyboard). F/X choose, ENTER opens, TAB goes to the next demo, ESC goes back
(and quits from home). Keep what you need, delete the rest. It is the same app
as the C++ template (`templates/cpp-lvgl`), file for file.

Guides: [docs/app-development/lvgl-apps.md](../../docs/app-development/lvgl-apps.md)
and [docs/app-development/rust.md](../../docs/app-development/rust.md).
Run every command from this directory; it should stay at `projects/<Name>/`
(or set `CP0_LVGL_RUNTIME`, see below).

## Build the LVGL runtime (once)

The app links against LVGL, `cp0_lvgl` and its C API
([`cp0_app.h`](../../ext_components/cp0_lvgl/include/cp0_app.h)), built by
one script ([scripts/lvgl-runtime](../../scripts/lvgl-runtime/README.md)) in
the Python environment from [setup](../../docs/app-development/setup.md):

```bash
../../scripts/lvgl-runtime/build.sh desktop    # for cargo build / cargo run
../../scripts/lvgl-runtime/build.sh device     # for the device build
```

Run it again after pulling changes to `ext_components/cp0_lvgl` or LVGL.
Without it, `cargo build` stops and tells you which command to run.

## Run on your computer

```bash
cargo run                                          # SDL window: F/X choose, ENTER open, ESC back/quit
cargo test                                         # the calculator's unit tests
```

Run it from this directory: the app finds `wallpaper.png` in
`./APPLaunch/share/images`. Headless, e.g. for a screenshot:
`python3 ../../scripts/fbsim/headless.py --settle 2.5 --keys "1" --png colors.png -- target/debug/hello-cardputer`.

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
on Debian/Ubuntu `sudo apt install gcc-aarch64-linux-gnu`. The binary links
LVGL statically and only needs libraries every CardputerZero has (libinput,
xkbcommon, FreeType, libstdc++, glibc).

Install it: `scp packages/*.deb pi@<device>: && ssh pi@<device> sudo dpkg -i hello-cardputer_0.1.0_arm64.deb`.
The app appears on the home screen within a few seconds.

## Where things are

| Path | What |
| --- | --- |
| `src/app.rs` | The app: owns the screens, shows one at a time, routes keys. Start here. |
| `src/main.rs` | Entry point: `lvgl::run("Hello Cardputer", HelloCardputer::new)` |
| `src/lvgl.rs` | The bindings: hand-written `extern "C"` declarations of LVGL and `cp0_app.h`, the constants, and the safe layer (`Obj`, `Label`, `Slider`, ..., `Font`, `Timer`, `Group`, `run`). Its header explains how to add more LVGL functions. |
| `src/ui.rs` | Language name and color, palette, `Action`, key helpers, label/panel helpers, the `Screen` trait |
| `src/home.rs` | Home screen: wallpaper, greeting, menu |
| `src/colors.rs`, `src/motion.rs`, `src/repl.rs`, `src/widgets.rs` | The four demos (`widgets.rs` explains how keys drive LVGL widgets on the device) |
| `src/canvas.rs` | Pixel drawing on an `lv_canvas`: `fill_rect`, `fill_circle`, `draw_line`, ... (used by Colors and Motion) |
| `src/calc.rs` | The REPL's calculator language, with unit tests |
| `build.rs` | Links the LVGL runtime: `scripts/lvgl-runtime/out/<desktop\|device>/ldflags.txt` |
| `APPLaunch/applications/hello-cardputer.desktop` | Home-screen entry (name, icon, command) |
| `APPLaunch/share/images/hello-cardputer_100.png` | 100x100 icon (`scripts/make_app_icon.py` makes new ones) |
| `APPLaunch/share/images/wallpaper.png` | Home-screen picture, 320x150 (Qubix artwork, Apache-2.0; see `LICENSES/Qubix-wallpaper-Apache-2.0.txt`) |
| `cardputer-app.json` | Package metadata for `scripts/package_app.py` |

`build.rs` looks for the runtime in `../../scripts/lvgl-runtime`. If the app
lives elsewhere, point `CP0_LVGL_RUNTIME` at that directory of a repository
checkout. It links the device runtime when cross-compiling for aarch64 Linux
and the desktop one otherwise; `CP0_LVGL_TARGET=device` forces the device one
(e.g. when building on the CardputerZero itself).

## How the Rust code talks to LVGL

Screens live as long as the app (`&'static`), so LVGL callbacks can point at
them; the state they change sits in `Cell`/`RefCell`. A callback is a method:

```rust
self.button.on_event(LV_EVENT_CLICKED, self, Self::button_clicked);
```

Widgets are `Copy` handles (`Label`, `Slider`, ...) that deref to `Obj`, so
`label.set_pos(8, 0)` and `label.set_text("Hi")` both work. All `unsafe` code
is in `src/lvgl.rs`.
