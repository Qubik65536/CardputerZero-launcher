<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# LVGL runtime for other languages

The `rust-lvgl`, `zig-lvgl` and `ocaml-lvgl` templates write their UI with
LVGL, the widget library the launcher and the C++ template use. They link
against this runtime: LVGL 9.5, cp0_lvgl (display, keyboard, top bar, platform
services) and its C API, [`cp0_app.h`](../../ext_components/cp0_lvgl/include/cp0_app.h).

```bash
scripts/lvgl-runtime/build.sh desktop   # once per machine: SDL2 window, fbsim, emulator
scripts/lvgl-runtime/build.sh device    # once, before the first device build
```

Each build takes a minute or two the first time and is incremental after
that. Run it again after pulling changes to `ext_components/cp0_lvgl` or LVGL.
It needs the same setup as the C++ template (the Python environment with
SCons; SDL2 for desktop; the aarch64 cross compiler for device, see
[setup](../../docs/app-development/setup.md)). The first device build
downloads the device sysroot (~440 MB).

## What it produces

`out/<desktop|device>/`:

| File | For |
| --- | --- |
| `ldflags.txt` | Link arguments, one per line: the static libraries (`libcp0_lvgl.a`, `liblvgl_component.a`, `libeventpp.a`), then the system libraries they need, in order |
| `cflags.txt` | `-I`/`-D` flags for compiling C against `lvgl/lvgl.h` and `cp0_app.h` (C stubs, C code) |
| `ldflags.sexp`, `cflags.sexp` | The same, for dune |
| `build/` | The SCons project: libraries, generated LVGL config, log in `../build.log` |

The flags come from the build itself: `main/src/cp0_app_smoke.c`, the
smallest C program using `cp0_app.h`, is compiled and linked in every build,
and `export_flags.py` turns its commands into the files above.

## How a language uses it

1. Declare the C functions it calls: `cp0_app_run`, `cp0_app_quit`, ... and the
   `lv_*` functions for widgets. The templates keep these declarations in one
   file (`src/lvgl.rs`, `src/lvgl.zig`, `src/lvgl_stubs.c` + `src/lvgl.ml`).
2. Link with `ldflags.txt` for the target (the templates' build scripts do it).
3. Call `cp0_app_run(title, setup, on_key, user_data)`: build widgets in
   `setup`, react to keys in `on_key`, call `cp0_app_quit()` to leave.

The device libraries are linked dynamically against libraries every
CardputerZero has (libinput, xkbcommon, FreeType, libstdc++, ...), so a
package only contains the app's own binary. The runtime is compiled with
`-fPIC` (see `profiles/`), because Rust, Zig and Debian's gcc link
position-independent executables.
