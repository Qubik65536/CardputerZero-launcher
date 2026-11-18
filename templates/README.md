<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# App templates

Starting points for your own CardputerZero apps. Each one is a complete,
working app called **Hello Cardputer** that builds for the desktop and for the
device. Do not edit them in place: copy one with the scaffolder, which also
renames everything to your app's name.

```bash
python3 scripts/new_app.py <template> "My App Name"
```

| Template | Language | UI | Best for |
| --- | --- | --- | --- |
| [`cpp-lvgl`](cpp-lvgl/) | C++17 | LVGL 9.5 widgets via `cp0_lvgl` (same as the launcher) | Apps that should look and behave like the built-in ones |
| [`rust-fb`](rust-fb/) | Rust | Direct framebuffer + keyboard, no crates | Games, tools, anything where you want full control |
| [`zig-fb`](zig-fb/) | Zig 0.17 | Direct framebuffer + keyboard, static binary | Same, with trivial cross-compilation |
| [`ocaml-fb`](ocaml-fb/) | OCaml 5 | Direct framebuffer + keyboard, stdlib + unix | Same, in OCaml |

Start with the guide: [docs/app-development/README.md](../docs/app-development/README.md).
