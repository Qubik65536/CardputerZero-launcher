<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# App templates

Starting points for your own CardputerZero apps. Each one is a complete,
working app called **Hello Cardputer** that builds for the desktop and for the
device. Do not edit them in place: copy one with the scaffolder, which also
renames everything to your app's name.

All seven are the same app: a home screen that says "Hello, *Language*!" in
the language's GitHub color over a wallpaper, and four demos to start from:
**Colors** (pixel-by-pixel color rendering), **Motion** (an animated ball you
steer, with live physics numbers), **REPL** (a terminal-style calculator
language) and **Widgets** (a form with a text field, button, slider, counter,
chooser and switch). See
[the template app](../docs/app-development/framebuffer-apps.md#the-template-app).

```bash
python3 scripts/new_app.py <template> "My App Name"
```

| Template | Language | UI | Best for |
| --- | --- | --- | --- |
| [`cpp-lvgl`](cpp-lvgl/) | C++17 | LVGL 9.5 widgets via `cp0_lvgl` (same as the launcher) | Apps that should look and behave like the built-in ones |
| [`rust-fb`](rust-fb/) | Rust | Direct framebuffer + keyboard, no crates | Games, tools, anything where you want full control |
| [`zig-fb`](zig-fb/) | Zig 0.17 | Direct framebuffer + keyboard, static binary | Same, with trivial cross-compilation |
| [`ocaml-fb`](ocaml-fb/) | OCaml 5 | Direct framebuffer + keyboard, stdlib + unix | Same, in OCaml |
| [`rust-lvgl`](rust-lvgl/) | Rust | LVGL 9.5 widgets through `cp0_app.h` (FFI) | Forms, menus and text input in Rust, with the launcher's look |
| [`zig-lvgl`](zig-lvgl/) | Zig 0.17 | LVGL 9.5 widgets through `cp0_app.h` (`extern`) | Same, in Zig |
| [`ocaml-lvgl`](ocaml-lvgl/) | OCaml 5 | LVGL 9.5 widgets through `cp0_app.h` (C stubs) | Same, in OCaml |

The `*-lvgl` templates link against the LVGL runtime: run
`scripts/lvgl-runtime/build.sh desktop` once first (and `device` before a
device build). See [LVGL apps in Rust, Zig and OCaml](../docs/app-development/lvgl-apps.md).

Start with the guide: [docs/app-development/README.md](../docs/app-development/README.md).
